# Uses urllib.request and http.client directly (both are broker shims).
import http.client
import urllib.request
from novaprinter import prettyPrinter


class fx_urllib(object):
    url = "__BASE__"
    name = "Fixture urllib"
    supported_categories = {"all": "0"}

    def search(self, what, cat="all"):
        body = urllib.request.urlopen(self.url + "/plain").read().decode()
        prettyPrinter({"link": "magnet:?xt=urn:btih:" + "1" * 40, "name": "urllib:" + body.strip(),
                       "size": "1 MB", "seeds": 1, "leech": 0, "engine_url": self.url})
        c = http.client.HTTPConnection("example.test", __PORT__)
        c.request("GET", "/plain")
        r = c.getresponse()
        prettyPrinter({"link": "magnet:?xt=urn:btih:" + "2" * 40, "name": "httpclient:%d:%s" % (r.status, r.read().decode().strip()),
                       "size": "2 MB", "seeds": 2, "leech": 0, "engine_url": self.url})
