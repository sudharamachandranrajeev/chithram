# Test fixture engine: talks only to the local fixture server (example.test).
import re
from helpers import retrieve_url
from novaprinter import prettyPrinter


class fx_good(object):
    url = "__BASE__"
    name = "Fixture Good"
    supported_categories = {"all": "0", "movies": "1"}

    def search(self, what, cat="all"):
        page = retrieve_url(self.url + "/search?q=" + what)
        for m in re.finditer(r'<a class="r" href="([^"]+)" data-size="([^"]+)" data-s="(\d+)" data-l="(\d+)">([^<]+)</a>', page):
            prettyPrinter({
                "link": m.group(1), "name": m.group(5), "size": m.group(2),
                "seeds": int(m.group(3)), "leech": int(m.group(4)),
                "engine_url": self.url, "desc_link": self.url + "/item/" + m.group(3),
            })
