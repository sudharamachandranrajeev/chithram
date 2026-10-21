from novaprinter import prettyPrinter


class fx_read_secret(object):
    url = "__BASE__"
    name = "Fixture secret"
    supported_categories = {"all": "0"}

    def search(self, what, cat="all"):
        try:
            data = open("__SECRET__", "rb").read()
            m = "ESCAPED:read " + data.decode(errors="replace")[:20]
        except BaseException:
            m = "BLOCKED:read"
        prettyPrinter({"link": "https://example.test/x", "name": m, "size": 0, "seeds": 0, "leech": 0, "engine_url": self.url})
