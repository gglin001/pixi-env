"""Exercise a real virtiofsd through vhost-user shared memory and FUSE requests.

No VM, guest image, mount privileges, or third-party Python packages are needed.
The frontend deliberately negotiates split rings without EVENT_IDX so both the
shared used ring and the completion notification pipe are checked on every call.
"""

import argparse
import array
import mmap
import os
from pathlib import Path
import select
import shutil
import socket
import struct
import subprocess
import tempfile
import time


class Frontend:
    QUEUE_SIZE = 256
    MEMORY_SIZE = 2 * 1024 * 1024
    USER_BASE = 0x10000000
    DESC = 0x10000
    AVAIL = 0x20000
    USED = 0x30000
    REQUEST = 0x40000
    RESPONSE = 0x80000
    RESPONSE_SIZE = 128 * 1024

    def __init__(self, sock, memory_file):
        self.sock = sock
        self.pipes = []
        memory_file.truncate(self.MEMORY_SIZE)
        self.memory = mmap.mmap(memory_file.fileno(), self.MEMORY_SIZE)
        self.index = 0
        self.unique = 0
        self.control(3)  # SET_OWNER
        features = struct.unpack("<Q", self.control(1, reply=True))[0]
        required = (1 << 32) | (1 << 30)  # VERSION_1 and PROTOCOL_FEATURES
        assert features & required == required, hex(features)
        self.control(2, struct.pack("<Q", required))
        protocols = struct.unpack("<Q", self.control(15, reply=True))[0]
        assert protocols & 1, "MQ protocol is required"
        self.control(16, struct.pack("<Q", 1))
        queue_count = struct.unpack("<Q", self.control(17, reply=True))[0]
        assert queue_count == 2, queue_count
        region = struct.pack("<IIQQQQ", 1, 0, 0, self.MEMORY_SIZE, self.USER_BASE, 0)
        self.control(5, region, [memory_file.fileno()])
        for queue in range(2):
            # Queue 0 is the high-priority queue; queue 1 carries FUSE requests.
            delta = (queue - 1) * 0x1000
            desc, avail, used = self.DESC + delta, self.AVAIL + delta, self.USED + delta
            self.control(8, struct.pack("<II", queue, self.QUEUE_SIZE))
            self.control(9, struct.pack("<IIQQQQ", queue, 0,
                         self.USER_BASE + desc, self.USER_BASE + used,
                         self.USER_BASE + avail, 0))
            self.control(10, struct.pack("<II", queue, 0))
            if hasattr(os, "eventfd"):
                kick_read = kick_write = os.eventfd(0, os.EFD_NONBLOCK | os.EFD_CLOEXEC)
                call_read = call_write = os.eventfd(0, os.EFD_NONBLOCK | os.EFD_CLOEXEC)
            else:
                kick_read, kick_write = os.pipe()
                call_read, call_write = os.pipe()
            self.pipes.extend(set([kick_read, kick_write, call_read, call_write]))
            for fd in (kick_read, kick_write, call_read, call_write):
                os.set_blocking(fd, False)
            self.control(12, struct.pack("<Q", queue), [kick_read])
            self.control(13, struct.pack("<Q", queue), [call_write])
            self.control(18, struct.pack("<II", queue, 1))
            if queue == 1:
                self.kick, self.call = kick_write, call_read
        # A request/reply round trip ensures all queue setup was processed.
        self.control(1, reply=True)

    def recv_exact(self, length):
        parts = bytearray()
        while len(parts) < length:
            piece = self.sock.recv(length - len(parts))
            if not piece:
                raise RuntimeError("vhost-user disconnected")
            parts.extend(piece)
        return bytes(parts)

    def control(self, request, payload=b"", fds=(), reply=False):
        packet = struct.pack("<III", request, 1, len(payload)) + payload
        ancillary = [(socket.SOL_SOCKET, socket.SCM_RIGHTS, array.array("i", fds))] if fds else []
        sent = self.sock.sendmsg([packet], ancillary)
        if sent != len(packet):
            self.sock.sendall(packet[sent:])
        if reply:
            response, flags, length = struct.unpack("<III", self.recv_exact(12))
            assert response == request and flags & 4, (response, flags)
            return self.recv_exact(length)
        return b""

    def fuse(self, opcode, node=1, payload=b"", error=0):
        self.unique += 1
        packet = struct.pack("<IIQQIIII", 40 + len(payload), opcode, self.unique,
                             node, os.getuid(), os.getgid(), os.getpid(), 0) + payload
        assert len(packet) <= self.RESPONSE - self.REQUEST
        self.memory[self.REQUEST:self.REQUEST + len(packet)] = packet
        # Descriptor 0 supplies the request; descriptor 1 receives the reply.
        struct.pack_into("<QIHH", self.memory, self.DESC, self.REQUEST, len(packet), 1, 1)
        struct.pack_into("<QIHH", self.memory, self.DESC + 16,
                         self.RESPONSE, self.RESPONSE_SIZE, 2, 0)
        struct.pack_into("<H", self.memory, self.AVAIL + 4 + 2 * (self.index % self.QUEUE_SIZE), 0)
        self.index += 1
        struct.pack_into("<H", self.memory, self.AVAIL + 2, self.index & 0xFFFF)
        os.write(self.kick, struct.pack("<Q", 1))
        if not select.select([self.call], [], [], 10)[0]:
            raise TimeoutError(f"FUSE opcode {opcode}, unique {self.unique}: no completion")
        assert os.read(self.call, 4096), "completion pipe closed"
        used_index = struct.unpack_from("<H", self.memory, self.USED + 2)[0]
        assert used_index == self.index & 0xFFFF, (used_index, self.index)
        descriptor, written = struct.unpack_from("<II", self.memory,
                              self.USED + 4 + 8 * ((self.index - 1) % self.QUEUE_SIZE))
        assert descriptor == 0 and written >= 16, (descriptor, written)
        length, status, unique = struct.unpack_from("<IiQ", self.memory, self.RESPONSE)
        assert unique == self.unique and length == written, (unique, length, written)
        assert status == -error, f"FUSE opcode {opcode}: expected {-error}, got {status}"
        return bytes(self.memory[self.RESPONSE + 16:self.RESPONSE + length])

    def close(self):
        self.sock.close()
        self.memory.close()
        for fd in self.pipes:
            os.close(fd)


def exercise(frontend, shared):
    initialized = frontend.fuse(26, payload=struct.pack("<IIII", 7, 38, 0, 0))
    assert struct.unpack_from("<I", initialized)[0] == 7
    entry = frontend.fuse(1, payload=b"existing.txt\0")
    inode = struct.unpack_from("<Q", entry)[0]
    opened = frontend.fuse(14, inode, struct.pack("<II", 0, 0))
    handle = struct.unpack_from("<Q", opened)[0]
    content = frontend.fuse(15, inode, struct.pack("<QQIIQII", handle, 0, 4096, 0, 0, 0, 0))
    assert content == b"host-to-guest\n", content
    frontend.fuse(18, inode, struct.pack("<QIIQ", handle, 0, 0, 0))

    # Linux O_RDWR | O_CREAT | O_EXCL numeric flags, irrespective of host OS.
    flags = 0o302
    created = frontend.fuse(35, payload=struct.pack("<IIII", flags, 0o100640, 0o022, 0) + b"created.txt\0")
    inode = struct.unpack_from("<Q", created)[0]
    handle = struct.unpack_from("<Q", created, 128)[0]
    expected = bytearray()
    for index in range(300):
        chunk = f"guest-record-{index:04d}\n".encode()
        offset = len(expected)
        written = frontend.fuse(16, inode, struct.pack("<QQIIQII", handle, offset,
                                len(chunk), 0, 0, 2, 0) + chunk)
        assert struct.unpack_from("<I", written)[0] == len(chunk)
        expected.extend(chunk)
    content = frontend.fuse(15, inode, struct.pack("<QQIIQII", handle, 0, len(expected), 0, 0, 2, 0))
    assert content == bytes(expected)
    frontend.fuse(20, inode, struct.pack("<QII", handle, 0, 0))  # FSYNC
    frontend.fuse(20, inode, struct.pack("<QII", handle, 1, 0))  # FDATASYNC
    assert (shared / "created.txt").read_bytes() == bytes(expected)
    frontend.fuse(18, inode, struct.pack("<QIIQ", handle, 2, 0, 0))
    frontend.fuse(1, payload=b"missing.txt\0", error=2)  # Linux ENOENT
    # GETATTR on root checks a request after ring wrap and file release.
    frontend.fuse(3, payload=struct.pack("<IIQ", 0, 0, 0))
    directory = frontend.fuse(27, payload=struct.pack("<II", 0, 0))
    dir_handle = struct.unpack_from("<Q", directory)[0]
    frontend.fuse(30, payload=struct.pack("<QII", dir_handle, 0, 0))  # FSYNCDIR
    frontend.fuse(29, payload=struct.pack("<QIIQ", dir_handle, 0, 0, 0))
    frontend.fuse(50, payload=struct.pack("<Q", 0))  # SYNCFS
    print(f"vhost-user/FUSE passed: {frontend.unique} requests, shared mmap, FD passing, "
          "notifications, ring wrap, create/read/write/fsync/fsyncdir/syncfs/release")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", default="virtiofsd")
    parser.add_argument("--thread-pool-size", type=int, default=4)
    args = parser.parse_args()
    binary = shutil.which(args.binary) or str(Path(args.binary).resolve())
    # Keep the Unix socket below macOS's sockaddr_un path length limit.
    with tempfile.TemporaryDirectory(prefix="vfs-test-", dir="/tmp") as work:
        work = Path(work)
        shared = work / "shared"
        shared.mkdir()
        (shared / "existing.txt").write_bytes(b"host-to-guest\n")
        sock_path = work / "vhost.sock"
        with (work / "daemon.log").open("w+") as log, (work / "guest-memory").open("w+b") as memory:
            daemon = subprocess.Popen([binary, "--shared-dir", str(shared), "--socket-path", str(sock_path),
                                       "--sandbox", "none", "--seccomp", "none", "--inode-file-handles=never",
                                       "--thread-pool-size", str(args.thread_pool_size)],
                                      stdout=log, stderr=log)
            frontend = None
            try:
                deadline = time.monotonic() + 10
                while not sock_path.exists():
                    if daemon.poll() is not None or time.monotonic() >= deadline:
                        raise RuntimeError("virtiofsd did not start")
                    time.sleep(0.01)
                sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                sock.settimeout(10)
                sock.connect(str(sock_path))
                frontend = Frontend(sock, memory)
                exercise(frontend, shared)
            except BaseException:
                log.flush()
                log.seek(0)
                print(log.read())
                raise
            finally:
                if frontend is not None:
                    frontend.close()
                if daemon.poll() is None:
                    daemon.terminate()
                try:
                    daemon.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    daemon.kill()
                    daemon.wait()


if __name__ == "__main__":
    main()
