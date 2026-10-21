#!/usr/bin/env bash
# Interop check against the upstream LocalSend command-line app (test-only,
# built from source in CI, never shipped). It sends to our receiver:
#   - a text message (a magnet)              -> must arrive intact
#   - a .torrent file                        -> must arrive intact
#   - a picture                              -> must be refused
# Usage: tool/interop.sh /path/to/localsend-cli
# The CLI's --to <ip> always probes port 53317, so the receiver listens there
# and the CLI's own server moves to 53318. Loopback first; if the CLI will not
# talk to loopback, the runner's private address.
set -uo pipefail

cli=$(realpath "$1")
here=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
recv_pid=""
cleanup() {
  [ -n "$recv_pid" ] && kill "$recv_pid" 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT

export XDG_CONFIG_HOME="$work/config" HOME="$work/home"
export LOCALSEND_PORT=53318 LOCALSEND_ALIAS=interop-sender LOCALSEND_DESTINATION="$work/downloads"
mkdir -p "$work/home" "$work/downloads"

magnet='magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=Interop'
printf 'd8:announce3:foo4:infod6:lengthi1e4:name1:aee' >"$work/film.torrent"
printf '\x89PNG\r\n\x1a\n0000' >"$work/picture.png"
torrent_size=$(stat -c %s "$work/film.torrent")

fail() { echo "INTEROP FAIL: $*"; echo "--- receiver log"; cat "$work/recv.log" 2>/dev/null; exit 1; }

wait_for() { # <pattern> <seconds>
  for _ in $(seq 1 $(($2 * 4))); do
    grep -Fq -- "$1" "$work/recv.log" && return 0
    sleep 0.25
  done
  return 1
}

start_receiver() { # <recv.dart flags>
  : >"$work/recv.log"
  (cd "$here" && exec dart run tool/recv.dart "$@" --auto-accept --identity-dir "$work/id") >"$work/recv.log" 2>&1 &
  recv_pid=$!
  # The first start makes an RSA key: allow a while.
  wait_for READY 120 || fail "receiver did not start"
}

stop_receiver() {
  kill "$recv_pid" 2>/dev/null
  wait "$recv_pid" 2>/dev/null
  recv_pid=""
}

attempt() { # <target ip>
  local target=$1
  "$cli" send --to "$target" --text "$magnet" || return 1
  wait_for "TEXT $magnet" 10 || fail "text did not arrive intact"
  "$cli" send --to "$target" "$work/film.torrent" || return 1
  wait_for "FILE film.torrent $torrent_size" 10 || fail ".torrent did not arrive intact"
  if "$cli" send --to "$target" "$work/picture.png"; then
    fail "the picture was not refused"
  fi
  grep -q "FILE picture.png" "$work/recv.log" && fail "the picture was delivered"
  return 0
}

echo "== loopback"
start_receiver --loopback
if attempt 127.0.0.1; then
  echo "INTEROP OK (loopback)"
  exit 0
fi
stop_receiver

ip=$(hostname -I | tr ' ' '\n' | grep -E '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)' | head -n1)
[ -n "$ip" ] || fail "loopback did not work and there is no private address"
echo "== private address $ip"
start_receiver --bind "$ip"
attempt "$ip" || fail "the CLI could not deliver to $ip either"
echo "INTEROP OK ($ip)"
