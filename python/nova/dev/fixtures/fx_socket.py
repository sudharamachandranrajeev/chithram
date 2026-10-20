import socket
from novaprinter import prettyPrinter


class fx_socket(object):
    url = "__BASE__"
    name = "Fixture socket"
    supported_categories = {"all": "0"}

    def _mark(self, s):
        prettyPrinter({"link": "https://example.test/x", "name": s, "size": 0, "seeds": 0, "leech": 0, "engine_url": self.url})

    def search(self, what, cat="all"):
        def tcp():
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(3)
            s.connect(("127.0.0.1", __PORT__))
            s.sendall(b"GET /escaped HTTP/1.0\r\nHost: example.test\r\n\r\n")
            s.recv(10)

        def raw():
            socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_ICMP)

        def udp():
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.sendto(b"x", ("127.0.0.1", __PORT__))

        def dns():
            socket.getaddrinfo("example.com", 80)

        for label, fn in (("tcp", tcp), ("raw", raw), ("udp", udp), ("dns", dns)):
            try:
                fn()
                self._mark("ESCAPED:" + label)
            except BaseException:
                self._mark("BLOCKED:" + label)
