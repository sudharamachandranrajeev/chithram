"""Writes the signed repos the plugin registry tests use (test keys, synthetic plugins):
  python3 app/test/plugins/fixtures/make_fixtures.py
v1       key a: alpha 1.0, beta 1.0, adulty (adult)
v2       key a: alpha 1.1 (same site), beta 1.1 (new site), gamma 1.0 (new)
v2_keyb  key b: alpha 1.1 (a different key signs the same repo URL)
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "..", ".github", "fixtures", "plugins"))
from make_plugins import build_repo  # noqa: E402


def plugin(name, url, version, cats="'all': '0', 'movies': '1', 'tv': '2'", extra=""):
    return ("# synthetic test plugin %s\nclass %s(object):\n    url = '%s'\n    name = '%s %s'\n"
            "    supported_categories = {%s}\n%s    def search(self, what, cat='all'):\n        pass\n" % (name, name, url, name.title(), version, cats, extra)).encode()


def main():
    alpha1 = dict(id="alpha", name="Alpha", version="1.0", hosts=["cdn.alpha.example"], source=plugin("alpha", "https://alpha.example", "1.0"))
    alpha2 = dict(id="alpha", name="Alpha", version="1.1", hosts=["cdn.alpha.example"], source=plugin("alpha", "https://alpha.example", "1.1"))
    beta1 = dict(id="beta", name="Beta", version="1.0", source=plugin("beta", "https://beta.example", "1.0"))
    beta2 = dict(id="beta", name="Beta", version="1.1", source=plugin("beta", "https://beta-new.example", "1.1"))
    gamma = dict(id="gamma", name="Gamma", version="1.0", source=plugin("gamma", "https://gamma.example", "1.0"))
    adulty = dict(id="adulty", name="Adulty", version="1.0", adult=True, source=plugin("adulty", "https://adulty.example", "1.0"))
    build_repo(os.path.join(HERE, "v1"), "Test repo", [alpha1, beta1, adulty])
    build_repo(os.path.join(HERE, "v2"), "Test repo", [alpha2, beta2, gamma, adulty])
    build_repo(os.path.join(HERE, "v2_keyb"), "Test repo", [alpha2, beta1], key="b")


if __name__ == "__main__":
    main()
