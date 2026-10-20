# native/torrent

Placeholder. Planned: a Rust `cdylib` over `librqbit` with a C header, loaded
through `dart:ffi` in-process on every platform. It will serve torrent files
over a loopback-only, token-protected HTTP range endpoint. See
[docs/decisions.md](../../docs/decisions.md). Nothing is built here yet.
