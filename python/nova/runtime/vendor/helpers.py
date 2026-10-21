# VERSION: 1.61 (upstream)
# MODIFIED for Chithram: retrieve_url/download_file go through the host broker
# (nova_broker) instead of urllib sockets; no temp files, no SOCKS in-process.

# Author:
#  Christophe DUMEZ (chris@qbittorrent.org)

# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#    * Redistributions of source code must retain the above copyright notice,
#      this list of conditions and the following disclaimer.
#    * Redistributions in binary form must reproduce the above copyright
#      notice, this list of conditions and the following disclaimer in the
#      documentation and/or other materials provided with the distribution.
#    * Neither the name of the author nor the names of its contributors may be
#      used to endorse or promote products derived from this software without
#      specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

import datetime
import gzip
import html
import io
import logging
import urllib.parse
from collections.abc import Mapping
from typing import Any, Optional

import nova_broker

_logger = logging.getLogger(__name__)


def _getBrowserUserAgent() -> str:
    """
    Disguise as browser to circumvent website blocking
    """
    baseDate = datetime.date(2026, 10, 13)
    baseVersion = 158
    nowDate = datetime.datetime.now(datetime.timezone.utc).date()
    nowVersion = baseVersion + ((nowDate - baseDate).days // 15)
    return f"Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:{nowVersion}.0) Gecko/20100101 Firefox/{nowVersion}.0"


_headers: dict[str, str] = {'User-Agent': _getBrowserUserAgent()}


def enable_socks_proxy(enable: bool) -> None:
    # The host applies the SOCKS5 proxy (VPN guard) inside the broker.
    return None


htmlentitydecode = html.unescape


def _gunzip(data: bytes) -> bytes:
    if data[:2] == b'\x1f\x8b':
        with io.BytesIO(data) as compressedStream, gzip.GzipFile(fileobj=compressedStream) as gzipper:
            return gzipper.read(nova_broker.MAX_BODY + 1)
    return data


def retrieve_url(url: str, custom_headers: Mapping[str, str] = {}, request_data: Optional[Any] = None, ssl_context: Any = None, unescape_html_entities: bool = True) -> str:
    """
    Return the content of the url page as a string (fetched by the host broker)
    """
    method = "POST" if request_data is not None else "GET"
    try:
        response = nova_broker.fetch(method, url, {**_headers, **custom_headers}, request_data)
    except nova_broker.BrokerDenied as errno:
        _logger.warning(f"Retrieve URL error. Reason: '{errno}'. URL: '{url}'.")
        return ""
    if response.status >= 400:
        return ""
    contentType = response.getheader('Content-Type', '') or ''
    data = _gunzip(response.read())
    charset = 'utf-8'
    try:
        charset = contentType.split('charset=', 1)[1]
    except IndexError:
        pass
    try:
        dataStr = data.decode(charset, 'replace')
    except LookupError:
        dataStr = data.decode('utf-8', 'replace')
    if unescape_html_entities:
        dataStr = html.unescape(dataStr)
    return dataStr


_downloads: dict[str, bytes] = {}


def download_file(url: str, referer: Optional[str] = None, ssl_context: Any = None) -> str:
    """
    Upstream writes a temp file. The sandbox cannot write, so the bytes are kept
    in memory and "mem:<n> <url>" is returned; the runner reports the download.
    """
    headers = dict(_headers)
    if referer is not None:
        headers['referer'] = referer
    response = nova_broker.fetch("GET", url, headers)
    if response.status >= 400:
        raise OSError(f"HTTP {response.status}")
    data = _gunzip(response.read())
    key = f"mem:{len(_downloads) + 1}"
    _downloads[key] = data
    return f"{key} {url}"
