git config filter.masksecrets.clean "\
sed -E 's/(sk|v1)-[A-Za-z0-9_]{8,}/<REDACTED>/g; \
s/AKIA[0-9A-Z]{16}/<REDACTED>/g; \
s/(?i)aws(.{0,20})?(secret|access)?.{0,20}[\"''][0-9a-zA-Z\/+]{40}[\"'']/<REDACTED>/g; \
s/ghp_[A-Za-z0-9]{36}/<REDACTED>/g; \
s/xox[baprs]-[A-Za-z0-9]{10,48}/<REDACTED>/g; \
s/AIza[0-9A-Za-z\-_]{35}/<REDACTED>/g; \
s/sk_(live|test)_[0-9a-zA-Z]{24}/<REDACTED>/g; \
s/[A-Za-z0-9-_]{20,}\.[A-Za-z0-9-_]{20,}\.[A-Za-z0-9-_]{20,}/<REDACTED-JWT>/g; \
s/-----BEGIN (RSA|EC|DSA|OPENSSH) PRIVATE KEY-----/<REDACTED-PRIVATE-KEY>/g; \
s/<REDACTED-PRIVATE-KEY>/<REDACTED-PRIVATE-KEY>/g; \
s/<REDACTED-CERTIFICATE>/<REDACTED-CERTIFICATE>/g'"
git config filter.masksecrets.smudge "cat"
