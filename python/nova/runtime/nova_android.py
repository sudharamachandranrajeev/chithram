"""Android entry (Chaquopy, :nova service). The Java side feeds NDJSON lines in
with feed() and receives lines through sink.line(String)."""
import json
import queue
import sys

import nova_broker
import runner


class QueueTransport:
    def __init__(self, sink):
        self.q = queue.Queue()
        self.sink = sink
        self.written = 0

    def send(self, obj):
        data = json.dumps(obj, separators=(",", ":"), ensure_ascii=True)
        if len(data) + 1 > nova_broker.MAX_LINE:
            raise ValueError("line over limit")
        if self.written + len(data) + 1 > nova_broker.MAX_STDOUT:
            raise ValueError("stdout budget exhausted")
        self.written += len(data) + 1
        self.sink.line(data)

    def recv(self):
        item = self.q.get()
        return None if item is None else json.loads(item)


_t = None
_r = None


def init(sink):
    """Builds the runner and installs the audit hook. Call before run()."""
    global _t, _r
    # Make the Java bridge fully loaded BEFORE the audit hook is installed
    # (it must not import ctypes lazily afterwards), and prove callbacks work.
    import java  # noqa
    from java import jclass  # noqa
    sink.line("")
    _t = QueueTransport(sink)
    _r = runner.Runner(_t)
    _r.prepare()


def run():
    """Blocking. Call from a dedicated Java thread."""
    return _r.serve()


def feed(line):
    _t.q.put(line)


def stop():
    _t.q.put(None)


def version():
    return sys.version.split()[0]
