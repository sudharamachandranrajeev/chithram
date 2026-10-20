import os
import sys


class fx_bigprint(object):
    url = "__BASE__"
    name = "Fixture bigprint"
    supported_categories = {"all": "0"}

    def search(self, what, cat="all"):
        line = "A" * 1023
        for _ in range(51200):          # ~50 MB through print(): discarded by the runner
            print(line)
        chunk = ("B" * 65535 + "\n").encode()
        for _ in range(800):            # ~50 MB through the raw fd: host must cut it off
            os.write(1, chunk)
