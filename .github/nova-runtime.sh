#!/usr/bin/env bash
# Assembles the search-plugin runtime that desktop builds ship next to the app:
#
#   nova-runtime.sh <linux|windows> <dest>    -> <dest>/nova/{python,runtime,nova-sandbox[.exe]}
#
# python-build-standalone (pinned release and sha256, from the release's
# SHA256SUMS), pruned of what plugins never need (tests, IDLE, Tk, pip,
# static libraries); the runner scripts (python/nova/runtime); and the
# sandbox launcher built from native/sandbox (cargo, --locked). Prints the
# compressed size of the result. Needs curl, tar, cargo.
set -euo pipefail

os=${1:?usage: nova-runtime.sh <linux|windows> <dest>}
dest=$(realpath -m "${2:?usage: nova-runtime.sh <linux|windows> <dest>}")
root=$(git rev-parse --show-toplevel)

PBS_RELEASE=20261013
case $os in
  linux)
    file='cpython-3.13.16+20261013-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz'
    sha=d0080766b6b74aeb81e1949ef0d9a20e6c17f7b160fb295a69b936ccb17660be
    exe=nova-sandbox ;;
  windows)
    file='cpython-3.13.16+20261013-x86_64-pc-windows-msvc-install_only_stripped.tar.gz'
    sha=7aba3985d4cee1c7cacb963ca6aa08a5d3e695d7f9609d9fabc56f22ddcf5a06
    exe=nova-sandbox.exe ;;
  *) echo "unknown os $os" >&2; exit 2 ;;
esac

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl -fsSL -o "$work/pbs.tgz" "https://github.com/astral-sh/python-build-standalone/releases/download/$PBS_RELEASE/${file//+/%2B}"
echo "$sha  $work/pbs.tgz" | sha256sum -c -
mkdir -p "$work/x"
tar -xzf "$work/pbs.tgz" -C "$work/x"

py=$work/x/python
before=$(du -sk "$py" | cut -f1)
# What a search plugin never needs.
find "$py" -type d \( -name test -o -name tests -o -name idlelib -o -name tkinter -o -name ensurepip -o -name pydoc_data \
  -o -name turtledemo -o -name __pycache__ -o -name 'config-3*' -o -name include -o -name share \) -prune -exec rm -rf {} +
find "$py" -type d -name site-packages -exec sh -c 'rm -rf "$1"/*' _ {} \;
rm -rf "$py"/lib/tcl* "$py"/lib/tk* "$py"/lib/itcl* "$py"/lib/thread* "$py"/lib/Tix* "$py"/tcl 2>/dev/null || true
find "$py" \( -name '_tkinter*' -o -name 'tcl*.dll' -o -name 'tk*.dll' -o -name '*.a' -o -name 'turtle.py' -o -name 'pydoc.py' \) -delete 2>/dev/null || true
if [[ $os == linux ]]; then
  # The interpreter is statically linked; the shared libpython and the Tcl/Tk libraries are dead weight.
  rm -f "$py"/lib/libpython* "$py"/lib/libtcl* "$py"/lib/libtk* "$py"/bin/idle3* "$py"/bin/pip* "$py"/bin/pydoc3* "$py"/bin/*-config
  rm -rf "$py"/lib/pkgconfig
fi
echo "python pruned: ${before} KiB -> $(du -sk "$py" | cut -f1) KiB"

cargo build --release --locked --manifest-path "$root/native/sandbox/Cargo.toml"

rm -rf "$dest/nova"
mkdir -p "$dest/nova/runtime"
mv "$py" "$dest/nova/python"
cp -r "$root"/python/nova/runtime/. "$dest/nova/runtime/"
find "$dest/nova/runtime" -name __pycache__ -prune -exec rm -rf {} +
cp "$root/native/sandbox/target/release/$exe" "$dest/nova/$exe"
cp "$root/python/nova/NOTICE" "$dest/nova/NOTICE"
tar -czf "$work/size.tgz" -C "$dest" nova
echo "nova runtime: $(du -sk "$dest/nova" | cut -f1) KiB on disk, $(( $(stat -c %s "$work/size.tgz") / 1024 )) KiB compressed"
