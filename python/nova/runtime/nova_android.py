"""Android entry: CPython (python.org Android build) embedded through JNI inside an
isolated-process service. The service gives us two pipes (NOVA_IN_FD, NOVA_OUT_FD)
carrying the same NDJSON as the desktop runner. Called from the JNI boot code."""
import os
import sys

import nova_broker
import runner


def main():
    t = nova_broker.StdioTransport(int(os.environ["NOVA_IN_FD"]), int(os.environ["NOVA_OUT_FD"]))
    r = runner.Runner(t)
    try:
        r.prepare()
    except BaseException as e:  # noqa
        t.send({"op": "error", "msg": "runner setup failed: %s: %s" % (type(e).__name__, e)})
        return 5
    t.send({"op": "ready", "py": sys.version.split()[0], "uid": os.getuid(), "audit": os.environ.get("NOVA_AUDIT", "1")})
    return r.serve()
