# native/torrent

Rust `cdylib` (+ `rlib` for tests) over [librqbit](https://github.com/ikatson/rqbit) 9.0.1 (Apache-2.0),
loaded in-process through `dart:ffi` by `packages/torrent`.

- `src/engine.rs`: session + loopback server lifecycle, add/stats/remove, quota eviction (oldest torrent first).
- `src/server.rs`: `GET|HEAD /{token}/stream/{id}/{file_idx}` (Range, 206) and `/{token}/health` on
  `127.0.0.1:0`. Wrong token or non-loopback `Host` -> 403, no CORS, media extensions only (else 415).
- `src/lib.rs`: C ABI, JSON in/out: `ct_start(dir, quota, socks5)`, `ct_add(magnet, bytes, len, peers_json)`,
  `ct_stats(id)`, `ct_remove(id, delete_files)`, `ct_stop()`, `ct_free(ptr)`, `ct_version()`.
- With a SOCKS5 URL: no DHT, no listener, no LSD, `tr=udp://` trackers stripped from magnets (UDP is not proxied).
  Caveat: `.torrent` files carrying UDP trackers are not filtered yet.
- `tests/e2e.rs`: seeder + leecher over loopback (`initial_peers`), 200 MB, Range sha256 at 0/50/90%.
- `examples/seeder.rs`, `ci/emulator-test.sh`: the Android TV emulator job.

CI: `.github/workflows/spike-torrent.yml`. No local cargo: CI compiles and tests.
