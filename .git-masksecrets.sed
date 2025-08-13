s/(sk|v1)-[A-Za-z0-9_]{8,}/<REDACTED>/g
s/AKIA[0-9A-Z]{16}/<REDACTED>/g
s/[Aa][Ww][Ss].{0,20}([Ss]ecret|[Aa]ccess)?.{0,20}["'][0-9A-Za-z\/+]{40}["']/<REDACTED>/g
s/ghp_[A-Za-z0-9]{36}/<REDACTED>/g
s/xox[baprs]-[A-Za-z0-9]{10,48}/<REDACTED>/g
s/AIza[0-9A-Za-z_\-]{35}/<REDACTED>/g
s/sk_(live|test)_[0-9A-Za-z]{24}/<REDACTED>/g
s/[A-Za-z0-9_\-]{20,}\.[A-Za-z0-9_\-]{20,}\.[A-Za-z0-9_\-]{20,}/<REDACTED-JWT>/g
s/-----BEGIN (RSA|EC|DSA|OPENSSH) PRIVATE KEY-----/<REDACTED-PRIVATE-KEY>/g
s/-----BEGIN PRIVATE KEY-----/<REDACTED-PRIVATE-KEY>/g
s/-----BEGIN CERTIFICATE-----/<REDACTED-CERTIFICATE>/g