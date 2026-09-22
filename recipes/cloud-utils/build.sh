#!/usr/bin/env bash
set -euo pipefail

# The upstream Makefile uses DESTDIR for Debian's /usr layout and passes the
# GNU-only trailing --mode option to install. Install the same files directly
# so the recipe also works with macOS's BSD install implementation.
mkdir -p "$PREFIX/bin" "$PREFIX/share/man/man1" "$PREFIX/share/doc/cloud-utils"
for source in "$SRC_DIR"/bin/*; do
  install -m 0755 "$source" "$PREFIX/bin/"
done
for source in "$SRC_DIR"/man/*.1; do
  install -m 0644 "$source" "$PREFIX/share/man/man1/"
done
install -m 0644 "$SRC_DIR/LICENSE" "$PREFIX/share/doc/cloud-utils/"

# cloud-utils ships Python entry points with a system-only shebang. Use the
# interpreter supplied by the environment instead of requiring Apple's
# Command Line Tools Python on macOS.
sed -i.bak '1s|^#!/usr/bin/python3$|#!/usr/bin/env python3|' \
  "$PREFIX/bin/ec2metadata" "$PREFIX/bin/write-mime-multipart"
rm -f "$PREFIX/bin/ec2metadata.bak" "$PREFIX/bin/write-mime-multipart.bak"
