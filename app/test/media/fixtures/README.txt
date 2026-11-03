TEST-ONLY throwaway TLS material for app/test/media. Not used by the app.

ca.crt                        a CA that signs server.crt (its key was discarded)
server.crt / server.key       CA-signed P-256 server cert for localhost / 127.0.0.1
selfsigned.crt / .key         self-signed P-256 cert for the same names

All of it was generated once with openssl (valid to 2126), protects nothing and
is trusted by nothing outside these tests. Do not reuse it anywhere. The
gitleaks allowlist (.gitleaks.toml) covers this folder and nothing else.
