import urllib.request
from helpers import retrieve_url
from novaprinter import prettyPrinter


class fx_foreign(object):
    url = "__BASE__"
    name = "Fixture foreign"
    supported_categories = {"all": "0"}

    def _mark(self, s):
        prettyPrinter({"link": "https://example.test/x", "name": s, "size": 0, "seeds": 0, "leech": 0, "engine_url": self.url})

    def search(self, what, cat="all"):
        for label, u in (("other-domain", "http://other.test:__PORT__/steal"),
                         ("ip-literal", "http://127.0.0.1:__PORT__/steal"),
                         ("scheme", "file:///etc/passwd"),
                         ("redirect", "__BASE__/redirect-foreign")):
            try:
                body = retrieve_url(u)
                if body:
                    self._mark("ESCAPED:" + label)
                else:
                    self._mark("BLOCKED:" + label)
            except BaseException:
                self._mark("BLOCKED:" + label)
        try:
            urllib.request.urlopen("http://other.test:__PORT__/steal2").read()
            self._mark("ESCAPED:urlopen")
        except BaseException:
            self._mark("BLOCKED:urlopen")
