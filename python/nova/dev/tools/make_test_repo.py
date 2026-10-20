"""Builds the signed test plugin repos used by packages/nova_host tests.
Pure stdlib Ed25519 (RFC 8032) + BLAKE2b, minisign file formats (prehashed "ED").
Run: python3 python/nova/dev/tools/make_test_repo.py   (writes packages/nova_host/test/fixtures/)"""
import base64, hashlib, json, os, sys

P = 2**255 - 19
D = -121665 * pow(121666, P - 2, P) % P
L = 2**252 + 27742317777372353535851937790883648493
I = pow(2, (P - 1) // 4, P)


def inv(x): return pow(x, P - 2, P)


def add(p, q):
    A = (p[1] - p[0]) * (q[1] - q[0]) % P
    B = (p[1] + p[0]) * (q[1] + q[0]) % P
    C = p[3] * 2 * D * q[3] % P
    Dd = p[2] * 2 * q[2] % P
    E, F, G, H = B - A, Dd - C, Dd + C, B + A
    return (E * F % P, G * H % P, F * G % P, E * H % P)


def mul(s, pt):
    r = (0, 1, 1, 0)
    while s:
        if s & 1: r = add(r, pt)
        pt = add(pt, pt)
        s >>= 1
    return r


def enc(pt):
    zi = inv(pt[2]); x = pt[0] * zi % P; y = pt[1] * zi % P
    return (y | ((x & 1) << 255)).to_bytes(32, "little")


def recover_x(y, sign):
    x2 = (y * y - 1) * inv(D * y * y + 1) % P
    x = pow(x2, (P + 3) // 8, P)
    if (x * x - x2) % P: x = x * I % P
    if (x * x - x2) % P: raise ValueError
    if x & 1 != sign: x = P - x
    return x


GY = 4 * inv(5) % P
GX = recover_x(GY, 0)
G = (GX, GY, 1, GX * GY % P)


def sha512_int(b): return int.from_bytes(hashlib.sha512(b).digest(), "little")


def keypair(seed):
    h = hashlib.sha512(seed).digest()
    a = int.from_bytes(h[:32], "little")
    a &= (1 << 254) - 8; a |= 1 << 254
    return a, h[32:], enc(mul(a, G))


def sign(seed, msg):
    a, prefix, A = keypair(seed)
    r = sha512_int(prefix + msg) % L
    R = enc(mul(r, G))
    k = sha512_int(R + A + msg) % L
    return R + ((r + k * a) % L).to_bytes(32, "little")


def selftest():
    # RFC 8032 section 7.1 test 1: empty message
    seed = bytes.fromhex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
    assert keypair(seed)[2].hex() == "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
    assert sign(seed, b"").hex() == ("e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155"
                                     "5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b")
    assert hashlib.blake2b(b"abc").hexdigest().startswith("ba80a53f981c4d0d")


def minisign(seed, keyid, msg, trusted):
    pk = keypair(seed)[2]
    pub = "untrusted comment: minisign public key %s\n%s\n" % (keyid[::-1].hex().upper(), base64.b64encode(b"Ed" + keyid + pk).decode())
    digest = hashlib.blake2b(msg).digest()
    sig = sign(seed, digest)
    gsig = sign(seed, sig + trusted.encode())
    sigfile = ("untrusted comment: signature from minisign secret key\n%s\ntrusted comment: %s\n%s\n" %
               (base64.b64encode(b"ED" + keyid + sig).decode(), trusted, base64.b64encode(gsig).decode()))
    return pub, sigfile


def main():
    selftest()
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "packages", "nova_host", "test", "fixtures")
    out = os.path.abspath(out)
    plugin = (b"# chithram: adult=false\nclass demo(object):\n    url = 'http://example.test'\n    name = 'Demo'\n    supported_categories = {'all': '0'}\n"
              b"    def search(self, what, cat='all'):\n        pass\n")
    adult = b"# chithram: adult=true\nclass adultdemo(object):\n    url = 'http://example.test'\n    name = 'Adult demo'\n    supported_categories = {'all': '0'}\n    def search(self, what, cat='all'):\n        pass\n"
    manifest = {
        "name": "Test repo", "version": 1,
        "plugins": [
            {"id": "demo", "name": "Demo", "file": "demo.py", "sha256": hashlib.sha256(plugin).hexdigest(), "version": "1.0", "hosts": ["cdn.example.test"], "adult": False},
            {"id": "adultdemo", "name": "Adult demo", "file": "adultdemo.py", "sha256": hashlib.sha256(adult).hexdigest(), "version": "1.0", "adult": True},
        ],
    }
    mb = (json.dumps(manifest, indent=1, sort_keys=True) + "\n").encode()
    for name, seed, keyid in (("a", bytes([1]) * 32, bytes.fromhex("0102030405060708")), ("b", bytes([2]) * 32, bytes.fromhex("1112131415161718"))):
        d = os.path.join(out, "repo_" + name)
        os.makedirs(d, exist_ok=True)
        pub, sigfile = minisign(seed, keyid, mb, "timestamp:1 file:plugins.json repo:%s" % name)
        for fn, data in (("plugins.json", mb), ("plugins.json.minisig", sigfile.encode()), ("repo.pub", pub.encode()), ("demo.py", plugin), ("adultdemo.py", adult)):
            open(os.path.join(d, fn), "wb").write(data)
    print("wrote", out)


if __name__ == "__main__":
    main()
