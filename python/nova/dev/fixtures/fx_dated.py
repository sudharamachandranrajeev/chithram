# Test fixture engine: results with and without pub_date, local fixture server only.
import re
from helpers import retrieve_url, download_file
from novaprinter import prettyPrinter


class fx_dated(object):
    url = "__BASE__"
    name = "Fixture Dated"
    supported_categories = {"all": "0", "movies": "1", "tv": "2"}

    def search(self, what, cat="all"):
        retrieve_url(self.url + "/search?q=" + what)
        base = {"engine_url": self.url, "size": "1 GB", "seeds": 5, "leech": 1}
        prettyPrinter(dict(base, link="magnet:?xt=urn:btih:" + "c" * 40, name="Dated item", pub_date=1760000000,
                           desc_link=self.url + "/item/1"))
        prettyPrinter(dict(base, link="magnet:?xt=urn:btih:" + "d" * 40, name="Undated item"))
        prettyPrinter(dict(base, link="magnet:?xt=urn:btih:" + "e" * 40, name="Bad date item", pub_date="soon"))
        prettyPrinter(dict(base, link="magnet:?xt=urn:btih:" + "f" * 40, name="Negative date item", pub_date=-5))

    def download_torrent(self, info):
        print(download_file(info))
