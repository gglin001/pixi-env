"""Exercise seed creation without mounting disks or contacting cloud services."""

from email import policy
from email.parser import BytesParser
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile


def run(*args):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE).stdout


# Upstream 0.34 intentionally exits 1 and writes help to stderr.
metadata_help = subprocess.run(["ec2metadata", "--help"], capture_output=True)
assert metadata_help.returncode == 1
assert b"Query and display EC2 metadata." in metadata_help.stderr


with tempfile.TemporaryDirectory(prefix="cloud-utils test ") as directory:
    root = Path(directory)
    user_data = root / "user data"
    user_data.write_text("#cloud-config\nhostname: cloud-utils-test\n")
    metadata = root / "meta data"
    metadata.write_text('instance-id: cloud-utils-test\n')
    network = root / "network config"
    network.write_text("version: 2\nethernets: {}\n")
    interfaces = root / "interfaces"
    interfaces.write_text("auto eth0\niface eth0 inet dhcp\n")

    # This also checks GNU getopt, GNU tar, GNU sed, and quoted paths.
    for disk_format, member_prefix in (
        ("tar", ""),
        ("tar-seed-local", "var/lib/cloud/seed/nocloud/"),
        ("tar-seed-net", "var/lib/cloud/seed/nocloud-net/"),
    ):
        archive = root / f"{disk_format}.tar"
        run("cloud-localds", "--disk-format", disk_format, "--interfaces",
            str(interfaces), "--hostname", "cloud-utils-test", str(archive),
            str(user_data))
        with tarfile.open(archive) as seed:
            assert seed.extractfile(member_prefix + "user-data").read() == user_data.read_bytes()
            data = json.load(seed.extractfile(member_prefix + "meta-data"))
            assert data["local-hostname"] == "cloud-utils-test"
            assert data["interfaces"] == interfaces.read_text().rstrip("\n")
            assert all(item.uid == 0 and item.gid == 0 for item in seed.getmembers())

    # Verify the native macOS ISO backend through its Joliet filesystem.
    if sys.platform == "darwin":
        iso_path = root / "seed image.iso"
        run("cloud-localds", "--network-config", str(network), str(iso_path),
            str(user_data), str(metadata))
        with iso_path.open("rb") as image:
            image.seek(16 * 2048)
            descriptor = image.read(2048)
        assert descriptor[:7] == b"\x01CD001\x01"
        assert descriptor[40:72].rstrip(b" \x00").lower() == b"cidata"
        # macOS's libarchive tar reads ISO/Joliet without a privileged mount.
        for name, source in (("user-data", user_data), ("meta-data", metadata),
                             ("network-config", network)):
            content = run("/usr/bin/tar", "-xOf", str(iso_path), name)
            assert content == source.read_bytes(), name

    message = BytesParser(policy=policy.default).parsebytes(
        run("write-mime-multipart", str(user_data)))
    parts = list(message.iter_parts())
    assert len(parts) == 1
    assert parts[0].get_content_type() == "text/cloud-config"
    assert parts[0].get_payload(decode=True) == user_data.read_bytes()

print("cloud-utils seed and MIME checks passed")
