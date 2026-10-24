# Synthetic test plugin (nova3 format) for the end-to-end run. It only talks to
# the local fixture server, standing in for the site "fixture.test".
import re
from helpers import retrieve_url
from novaprinter import prettyPrinter


class fx_single(object):
    url = "http://fixture.test:8000"
    name = "Fixture Single"
    supported_categories = {"all": "0", "movies": "1"}

    def search(self, what, cat="all"):
        page = retrieve_url(self.url + "/plugins/site/search?q=" + what)
        for m in re.finditer(r'<a class="r" href="([^"]+)" data-size="([^"]+)" data-s="(\d+)" data-l="(\d+)" data-d="(\d+)">([^<]+)</a>', page):
            prettyPrinter({
                "link": m.group(1), "name": m.group(6), "size": m.group(2),
                "seeds": int(m.group(3)), "leech": int(m.group(4)),
                "engine_url": self.url, "desc_link": self.url + "/plugins/site/item/" + m.group(3),
                "pub_date": int(m.group(5)),
            })

    def download_torrent(self, info):
        from helpers import download_file
        print(download_file(info))
