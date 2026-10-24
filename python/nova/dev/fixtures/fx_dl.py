# Test fixture engine: download_torrent through the host broker (local fixture server only).
from helpers import download_file


class fx_dl(object):
    url = "__BASE__"
    name = "Fixture Download"
    supported_categories = {"all": "0"}

    def search(self, what, cat="all"):
        pass

    def download_torrent(self, info):
        print(download_file(info))
