#!/usr/bin/env python3
import argparse
import json
import socket
import subprocess
import sys
import time
from typing import Dict, Any

import requests

#
# This uses MCPO as a bit of cheat, as MCPO can interrogate an standard MCP server and extract the OpenAPI spec (openapi.json).
# We then take this spec and rewrite it to match the LiteLLM server's expected paths, so when OPenWebUi reads the spec, 
# it can call the LiteLLM server directly.
#
# So, this script is run once and generates openai.json as static json content that nghinx serves as /mcp/<mcp-server-name>/openapi.json.
# This is then used by OpenWebUI to discover the tools available on the MCP server, which are called and re-mapped as below.
#
# So every time you add a new tool to the MCP server, you need to run this script to regenerate the openapi.json file.
#
# Sadly this is not the end of the story. OpenWebUI expects the URI to include the tool name, but LiteLLM expects the tool name 
# to be in the body. So we then need a side-car service for nginx to rewrite the request to take the tool name from the 
# openWebUI request and put it into the body of the request to LiteLLM.
#
# ** OpenWebUI sends requests like this:
#
#  curl -X POST "http://localhost:9000/mcp-rest/tools/call/secure_datagroup-get_value_by_key"
#  -H "Authorization: Bearer <REDACTED>" \
#  -H "Content-Type: application/json" \
#  -d '{
#    "arguments": {
#      "key": "name",
#      "group": "people"
#    }
#  }'     
#
# ** LITE_LLM expects:
#
#  curl -X POST "http://localhost:9000/mcp-rest/tools/call" \
#  -H "Authorization: Bearer <REDACTED>" \
#  -H "Content-Type: application/json" \
#  -d '{
#    "name": "secure_datagroup-get_value_by_key",
#    "arguments": {
#      "key": "name",
#      "group": "people"
#    }
#  }'
#

def find_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("", 0))
        return s.getsockname()[1]


def wait_for(url: str, timeout: float = 20.0, interval: float = 0.25) -> None:
    start = time.time()
    while True:
        try:
            r = requests.get(url, timeout=3)
            if r.status_code == 200:
                return
        except Exception:
            pass
        if time.time() - start > timeout:
            raise TimeoutError(f"Timed out waiting for {url}")
        time.sleep(interval)


def rewrite_paths(spec: Dict[str, Any], base_path: str, server_label: str) -> Dict[str, Any]:
    def last_segment(p: str) -> str:
        parts = [seg for seg in p.split("/") if seg]
        return parts[-1] if parts else ""

    new_paths: Dict[str, Any] = {}
    for path, item in (spec.get("paths") or {}).items():
        suffix = last_segment(path)
        if not suffix:
            continue
        new_key = f"{base_path.rstrip('/')}/{server_label}-{suffix}"
        new_paths[new_key] = item
    out = dict(spec)
    out["paths"] = new_paths
    return out


def main():
    ap = argparse.ArgumentParser(
        description="Start a temporary mcpo, fetch openapi.json, and rewrite paths for LiteLLM."
    )
    ap.add_argument(
        "mcp_url",
        help='Target MCP server URL passed to mcpo after "--", e.g. http://localhost:9123/mcp',
    )
    ap.add_argument(
        "--mcpo-cmd",
        default="mcpo",
        help='mcpo executable (default: "mcpo")',
    )
    ap.add_argument(
        "--server-type",
        default="streamable-http",
        help='mcpo --server-type value (default: "streamable-http")',
    )
    ap.add_argument(
        "--litellm-base-path",
        default="/mcp-rest/tools/call",
        help='Prefix for rewritten paths (default: "/mcp-rest/tools/call")',
    )
    ap.add_argument(
        "--litellm-server-label",
        help='The name of the mcp server as configured in litellm = http://<litellm_host>:<port>/ui/?login=success&page=mcp-servers',
    )
    ap.add_argument(
        "--output",
        default="./mcp-openapi.json",
        help='Output file (default: mcp-openapi.json, use "-" or "stdout" for stdout)',
    )
    ap.add_argument(
        "--timeout",
        type=float,
        default=20.0,
        help="Seconds to wait for mcpo to serve openapi.json (default: 20)",
    )
    args = ap.parse_args()

    port = find_free_port()
    openapi_url = f"http://localhost:{port}/openapi.json"

    cmd = [
        args.mcpo_cmd,
        "--port", str(port),
        "--server-type", args.server_type,
        "--",
        args.mcp_url,
    ]

    proc = None
    try:
        proc = subprocess.Popen(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        # Wait until openapi.json is live
        wait_for(openapi_url, timeout=args.timeout)

        # Fetch spec
        spec = requests.get(openapi_url, timeout=10).json()

        # Rewrite paths
        rewritten = rewrite_paths(
            spec, base_path=args.litellm_base_path, server_label=args.litellm_server_label)

        # Emit
        if args.output == "-" or args.output.lower() == "stdout":
            json.dump(rewritten, sys.stdout, indent=2, ensure_ascii=False)
            sys.stdout.write("\n")
        else:
            with open(args.output, "w", encoding="utf-8") as f:
                json.dump(rewritten, f, indent=2, ensure_ascii=False)
            print(f"Wrote {args.output}")
    finally:
        if proc is not None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except Exception:
                proc.kill()


if __name__ == "__main__":
    main()
