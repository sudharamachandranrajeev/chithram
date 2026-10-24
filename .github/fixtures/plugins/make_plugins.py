"""Builds the synthetic signed plugin repo used by the end-to-end run and the
app tests. Test keys only: nothing here is a real repository.

  python3 .github/fixtures/plugins/make_plugins.py            (rewrites repo/ and single/; site/ is hand-written).
The end-to-end harness serves repo/* at /plugins/, single/ at /plugins/single/ and site/ at /plugins/site/

Library use (app tests): build_repo(outdir, name, plugins, key="a", trusted=".."),
where plugins is a list of dict(id, name, version, hosts, source(bytes), adult).
"""
import hashlib, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "python", "nova", "dev", "tools"))
import make_test_repo as mt  # noqa: E402  pure-stdlib Ed25519 + minisign file formats

KEYS = {
    "a": (bytes([7]) * 32, bytes.fromhex("0a0b0c0d0e0f1011")),
    "b": (bytes([9]) * 32, bytes.fromhex("2021222324252627")),
}


def build_repo(outdir, name, plugins, key="a", trusted="timestamp:1 file:plugins.json", extra_files=None):
    mt.selftest()
    seed, keyid = KEYS[key]
    os.makedirs(outdir, exist_ok=True)
    entries = []
    for p in plugins:
        src = p["source"]
        entries.append({"id": p["id"], "name": p.get("name", p["id"]), "file": p["id"] + ".py",
                        "sha256": hashlib.sha256(src).hexdigest(), "version": p.get("version", "1.0"),
                        "hosts": p.get("hosts", []), "adult": p.get("adult", False)})
        open(os.path.join(outdir, p["id"] + ".py"), "wb").write(src)
    manifest = (json.dumps({"name": name, "version": 1, "plugins": entries}, indent=1, sort_keys=True) + "\n").encode()
    pub, sig = mt.minisign(seed, keyid, manifest, trusted)
    for fn, data in (("plugins.json", manifest), ("plugins.json.minisig", sig.encode()), ("repo.pub", pub.encode())):
        open(os.path.join(outdir, fn), "wb").write(data if isinstance(data, bytes) else data.encode())
    for fn, data in (extra_files or {}).items():
        open(os.path.join(outdir, fn), "wb").write(data)


def main():
    src = lambda n: open(os.path.join(HERE, "src", n + ".py"), "rb").read()
    out = os.path.join(HERE, "repo")
    build_repo(out, "Fixture repo", [
        {"id": "fx_fixture", "name": "Fixture Plugin", "version": "1.0", "hosts": ["cdn.fixture.test"], "source": src("fx_fixture")},
        {"id": "fx_urlswap", "name": "Fixture Urlswap", "version": "1.0", "source": src("fx_urlswap")},
    ])
    single = os.path.join(HERE, "single")
    os.makedirs(single, exist_ok=True)
    open(os.path.join(single, "fx_single.py"), "wb").write(src("fx_single"))
    print("wrote", out, single)


if __name__ == "__main__":
    main()
