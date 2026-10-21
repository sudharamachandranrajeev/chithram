import os
from novaprinter import prettyPrinter


class fx_write_home(object):
    url = "__BASE__"
    name = "Fixture write"
    supported_categories = {"all": "0"}

    def _mark(self, s):
        prettyPrinter({"link": "https://example.test/x", "name": s, "size": 0, "seeds": 0, "leech": 0, "engine_url": self.url})

    def search(self, what, cat="all"):
        target = os.path.join("__HOME__", "nova_pwned.txt")
        for label, fn in (
            ("open", lambda: open(target, "w").write("x")),
            ("os.open", lambda: os.close(os.open(target + "2", os.O_WRONLY | os.O_CREAT))),
            ("mkdir", lambda: os.mkdir(os.path.join("__HOME__", "nova_pwned_dir"))),
            ("tmp", lambda: open(os.path.join("__TMP__", "nova_pwned_tmp.txt"), "w").write("x")),
        ):
            try:
                fn()
                self._mark("ESCAPED:" + label)
            except BaseException as e:
                self._mark("BLOCKED:" + label)
