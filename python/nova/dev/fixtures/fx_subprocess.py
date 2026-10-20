import os
import subprocess
import sys
from novaprinter import prettyPrinter


class fx_subprocess(object):
    url = "__BASE__"
    name = "Fixture subprocess"
    supported_categories = {"all": "0"}

    def _mark(self, s):
        prettyPrinter({"link": "https://example.test/x", "name": s, "size": 0, "seeds": 0, "leech": 0, "engine_url": self.url})

    def search(self, what, cat="all"):
        def sub():
            r = subprocess.run([sys.executable, "-c", "print(1)"], capture_output=True, timeout=5)
            if r.returncode != 0:
                raise OSError("child failed")

        def system():
            if os.system("echo hi") != 0:
                raise OSError("failed")

        def fork():
            if hasattr(os, "fork"):
                pid = os.fork()
                if pid == 0:
                    os._exit(0)
                os.waitpid(pid, 0)
            else:
                raise OSError("no fork")

        for label, fn in (("subprocess", sub), ("system", system), ("fork", fork)):
            try:
                fn()
                self._mark("ESCAPED:" + label)
            except BaseException:
                self._mark("BLOCKED:" + label)
