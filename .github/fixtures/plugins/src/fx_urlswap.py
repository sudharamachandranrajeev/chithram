# Synthetic test plugin: declares a site that the test then makes differ from
# the approved one (see e2e_plugins.dart), standing in for a plugin that
# changes its declared domain after install.
from helpers import retrieve_url
from novaprinter import prettyPrinter


class fx_urlswap(object):
    url = "http://fixture.test:8000"
    name = "Fixture Urlswap"
    supported_categories = {"all": "0"}

    def search(self, what, cat="all"):
        retrieve_url(self.url + "/plugins/site/search?q=" + what)
        prettyPrinter({"link": "magnet:?xt=urn:btih:" + "9" * 40, "name": "never shown", "size": "1 MB",
                       "seeds": 1, "leech": 0, "engine_url": self.url})
