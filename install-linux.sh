#!/usr/bin/env bash
# Installs (or updates) Chithram for the current user on x86_64 Linux:
#   curl -fsSL https://raw.githubusercontent.com/sudharamachandranrajeev/chithram/main/install-linux.sh | bash
#
# What it does:
#   1. Installs the runtime libraries with your package manager (pacman, apt or
#      dnf; asks for sudo): libmpv, libsecret, GTK 3.
#   2. Downloads the newest release's Linux tarball and checks it against the
#      release's SHA256SUMS.txt.
#   3. Unpacks it to ~/.local/share/chithram, links ~/.local/bin/chithram and
#      adds a menu entry (~/.local/share/applications/dev.chithram.chithram.desktop).
#
# Options: --no-deps (skip step 1), --uninstall (remove what step 3 added).
set -euo pipefail

repo=sudharamachandranrajeev/chithram
prefix=${XDG_DATA_HOME:-$HOME/.local/share}
dest=$prefix/chithram
bin=$HOME/.local/bin
desktop=$prefix/applications/dev.chithram.chithram.desktop

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

deps=1
for arg in "$@"; do
  case $arg in
    --no-deps) deps=0 ;;
    --uninstall)
      rm -rf "$dest" "$desktop"
      [[ -L $bin/chithram ]] && rm -f "$bin/chithram"
      say "Removed Chithram. Your settings stay in ~/.local/share/dev.chithram.chithram."
      exit 0 ;;
    *) die "unknown option $arg (use --no-deps or --uninstall)" ;;
  esac
done

[[ $(uname -m) == x86_64 ]] || die "only x86_64 builds are published"
for tool in curl tar sha256sum; do
  command -v "$tool" >/dev/null || die "$tool is needed"
done

if ((deps)); then
  sudo=; ((EUID == 0)) || sudo=sudo
  if command -v pacman >/dev/null; then
    say "Installing mpv, libsecret and gtk3 (pacman)"
    $sudo pacman -S --needed --noconfirm mpv libsecret gtk3
  elif command -v apt-get >/dev/null; then
    say "Installing libmpv2, libsecret and GTK 3 (apt)"
    $sudo apt-get update -qq
    $sudo apt-get install -y libmpv2 libsecret-1-0 libgtk-3-0t64 ||
      $sudo apt-get install -y libmpv2 libsecret-1-0 libgtk-3-0
  elif command -v dnf >/dev/null; then
    say "Installing mpv-libs, libsecret and gtk3 (dnf)"
    $sudo dnf install -y mpv-libs libsecret gtk3
  else
    say "Unknown package manager: install libmpv (libmpv.so.2), libsecret and GTK 3 yourself"
  fi
fi

say "Finding the newest release"
api=$(curl -fsSL "https://api.github.com/repos/$repo/releases?per_page=20")
tarball=$(grep -o "https://[^\"]*/releases/download/v[^\"]*-linux-x64\.tar\.gz" <<<"$api" | head -n1)
[[ -n $tarball ]] || die "no Linux tarball found in the releases"
sums=${tarball%/*}/SHA256SUMS.txt
name=${tarball##*/}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
say "Downloading $name"
curl -fL --progress-bar -o "$tmp/$name" "$tarball"
curl -fsSL -o "$tmp/SHA256SUMS.txt" "$sums"
(cd "$tmp" && grep " \*\?$name\$" SHA256SUMS.txt | sha256sum -c --quiet -) ||
  die "checksum mismatch for $name"

say "Installing to $dest"
mkdir -p "$tmp/x"
tar -xzf "$tmp/$name" -C "$tmp/x"
src=$(find "$tmp/x" -mindepth 1 -maxdepth 1 -type d | head -n1)
[[ -x $src/chithram ]] || die "the tarball has no chithram binary"
mkdir -p "$prefix"
rm -rf "$dest.new"
mv "$src" "$dest.new"
rm -rf "$dest"
mv "$dest.new" "$dest"

mkdir -p "$bin" "${desktop%/*}"
ln -sfn "$dest/chithram" "$bin/chithram"
cat >"$desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Chithram
Comment=YouTube, live TV and torrents
Exec=$dest/chithram %U
Icon=$dest/chithram.png
Terminal=false
Categories=AudioVideo;Video;Player;
StartupWMClass=dev.chithram.chithram
EOF
command -v update-desktop-database >/dev/null && update-desktop-database -q "${desktop%/*}" || true

say "Installed ${name%-linux-x64.tar.gz}. Start it from your app launcher or run: chithram"
case ":$PATH:" in *":$bin:"*) ;; *) say "Add $bin to your PATH to run 'chithram' from a terminal." ;; esac
