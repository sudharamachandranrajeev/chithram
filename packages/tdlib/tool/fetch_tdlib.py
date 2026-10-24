#!/usr/bin/env python3
"""Downloads the TDLib binaries built by .github/workflows/tdlib.yml.

  fetch_tdlib.py android-arm64-v8a [android-x86_64 ...]
  fetch_tdlib.py linux-x64
  fetch_tdlib.py windows-x64
  fetch_tdlib.py --has <platform>     exit 0 if the lock has a binary for it

Reads tool/tdlib.lock.json: the GitHub release (`tdlib-<version>` of this
repo), each asset's name and pinned sha256. A hash mismatch is an error. A
platform with no entry in the lock is skipped with a warning, so a build
without that binary still succeeds (Telegram then reports that this build has
no TDLib).

Destinations (all git-ignored), where the packages/tdlib plugin bundles them:
  android/src/main/jniLibs/<abi>/libtdjson.so
  prebuilt/linux-x64/libtdjson.so
  prebuilt/windows-x64/tdjson.dll
"""
import hashlib
import json
import os
import shutil
import sys
import tempfile
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.dirname(HERE)


def destination(platform):
    if platform.startswith("android-"):
        return os.path.join(PKG, "android", "src", "main", "jniLibs", platform[len("android-"):], "libtdjson.so")
    if platform == "linux-x64":
        return os.path.join(PKG, "prebuilt", "linux-x64", "libtdjson.so")
    if platform == "windows-x64":
        return os.path.join(PKG, "prebuilt", "windows-x64", "tdjson.dll")
    sys.exit("unknown platform %r" % platform)


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def main(platforms):
    with open(os.path.join(HERE, "tdlib.lock.json")) as f:
        lock = json.load(f)
    base = "https://github.com/%s/releases/download/tdlib-%s/" % (lock["repo"], lock["version"])
    for platform in platforms:
        entry = lock["assets"].get(platform)
        dest = destination(platform)
        if not entry:
            print("::warning::tdlib.lock.json has no %s binary: this build has no TDLib" % platform)
            continue
        if os.path.exists(dest) and sha256(dest) == entry["sha256"]:
            print("%s: up to date" % platform)
            continue
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        url = base + entry["name"]
        print("downloading", url, file=sys.stderr)
        with tempfile.TemporaryDirectory() as tmp:
            part = os.path.join(tmp, "download")
            urllib.request.urlretrieve(url, part)
            got = sha256(part)
            if got != entry["sha256"]:
                sys.exit("sha256 mismatch for %s: %s != %s" % (entry["name"], got, entry["sha256"]))
            shutil.copyfile(part, dest)
        print("%s: %s (%d bytes)" % (platform, dest, os.path.getsize(dest)))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    if sys.argv[1] == "--has":
        with open(os.path.join(HERE, "tdlib.lock.json")) as f:
            sys.exit(0 if sys.argv[2] in json.load(f)["assets"] else 1)
    main(sys.argv[1:])
