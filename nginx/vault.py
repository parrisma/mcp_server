#!/usr/bin/env python3
"""
vault.py
Simple Vault client to read a key from HashiCorp Vault KV (v1 or v2).
All configuration can be provided via CLI flags; usable as a tiny library too.

Examples:
  python3 vault.py --token root --path openwebui --key litellm_api_key
  python3 vault.py -t $VAULT_TOKEN -a http://localhost:8200 -m secret -p openwebui -k litellm_api_key --json
"""
from __future__ import annotations
import json
import sys
import argparse
import urllib.request
import urllib.error
from typing import Any, Optional


class VaultError(RuntimeError):
    pass


class VaultClient:
    def __init__(self,
                 addr: str,
                 token: str,
                 mount: str = "secret",
                 timeout: float = 10.0):
        self.addr = addr.rstrip("/")
        self.token = token
        self.mount = mount.strip("/")
        self.timeout = timeout

    def _req(self, method: str, path: str) -> Any:
        url = f"{self.addr}{path}"
        req = urllib.request.Request(url, method=method, headers={
            "X-Vault-Token": self.token,
            "Accept": "application/json",
        })
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                data = resp.read()
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="replace") if hasattr(e, 'read') else ""
            raise VaultError(f"HTTP {e.code} for {url}: {body}") from None
        except urllib.error.URLError as e:
            raise VaultError(f"URL error for {url}: {e}") from None
        if not data:
            return {}
        try:
            return json.loads(data.decode("utf-8"))
        except json.JSONDecodeError:
            raise VaultError(f"Non-JSON response from {url}") from None

    def detect_kv_version(self, mount: Optional[str] = None) -> int:
        """Return 1 or 2 based on mount options; defaults to 1 if unknown."""
        mnt = (mount or self.mount).strip("/")
        resp = self._req("GET", "/v1/sys/mounts")
        try:
            version = resp["data"][f"{mnt}/"]["options"].get("version", "1")
        except Exception:
            return 1
        return 2 if str(version) == "2" else 1

    def get_kv(self,
               path: str,
               key: str,
               mount: Optional[str] = None,
               version: Optional[int] = None) -> Optional[str]:
        """
        Read a single key from a KV secret. Returns the value string or None if missing.
        path: logical secret path under the mount (e.g., 'openwebui').
        key: the field inside the secret to fetch (e.g., 'litellm_api_key').
        mount: override mount name (defaults to client mount).
        version: force 1 or 2; if None, detect.
        """
        mnt = (mount or self.mount).strip("/")
        ver = version or self.detect_kv_version(mnt)
        if ver == 2:
            api_path = f"/v1/{mnt}/data/{path}"
        else:
            api_path = f"/v1/{mnt}/{path}"
        resp = self._req("GET", api_path)
        data = resp.get("data") or {}
        # unwrap for v2
        if ver == 2 and isinstance(data, dict) and "data" in data:
            data = data.get("data") or {}
        val = data.get(key)
        if val is None:
            return None
        return str(val)


def _parse_args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Get a value from HashiCorp Vault KV")
    p.add_argument("--addr", "-a", default="http://localhost:8200",
                   help="Vault address (default: %(default)s)")
    p.add_argument("--token", "-t", required=True, help="Vault token")
    p.add_argument("--mount", "-m", default="secret",
                   help="KV mount name (default: %(default)s)")
    p.add_argument("--path", "-p", required=True,
                   help="Secret path under the mount (e.g., openwebui)")
    p.add_argument("--key", "-k", required=True,
                   help="Field name inside the secret")
    p.add_argument("--version", type=int, choices=(1, 2),
                   help="Force KV version (auto-detect if omitted)")
    p.add_argument("--timeout", type=float, default=10.0,
                   help="HTTP timeout seconds (default: %(default)s)")
    out = p.add_mutually_exclusive_group()
    out.add_argument("--json", action="store_true",
                     help="Print JSON {key:value}")
    out.add_argument("--export", action="store_true",
                     help="Print KEY=VALUE export format")
    return p.parse_args(argv)


def main(argv: list[str]) -> int:
    args = _parse_args(argv)
    client = VaultClient(addr=args.addr,
                         token=args.token,
                         mount=args.mount,
                         timeout=args.timeout)
    try:
        value = client.get_kv(
            path=args.path,
            key=args.key,
            version=args.version)
    except VaultError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 2
    if value is None:
        print("", end="")
        return 3
    if args.json:
        print(json.dumps({args.key: value}))
    elif args.export:
        # naive shell escaping; for complex values consider shlex.quote
        print(f"{args.key}={value}")
    else:
        print(value, end="")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
