from helpers import retrieve_url
from novaprinter import prettyPrinter


class fx_flood(object):
    url = "__BASE__"
    name = "Fixture flood"
    supported_categories = {"all": "0"}

    def search(self, what, cat="all"):
        ok = 0
        for i in range(40):                       # limit is 20 requests per search
            if retrieve_url(self.url + "/plain?i=%d" % i):
                ok += 1
        prettyPrinter({"link": "https://example.test/x", "name": "ok=%d" % ok, "size": 0, "seeds": 0, "leech": 0, "engine_url": self.url})
        for i in range(700):                      # limit is 500 results
            prettyPrinter({"link": "magnet:?xt=urn:btih:%040d" % i, "name": "r%d" % i, "size": 1, "seeds": 1, "leech": 1, "engine_url": self.url})
