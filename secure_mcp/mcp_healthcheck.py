#!/usr/bin/env python3
"""Ultra-minimal MCP streamable HTTP connectivity check.

Success (exit 0) means we were able to:
    1. Open the streamable HTTP transport to the MCP server URL.
    2. Create a ClientSession.
    3. Run session.initialize().

Anything failing returns exit 1.

Environment:
    MCP_SERVER_URL (optional) default: http://python-mcp:9123/mcp
"""

import os
import sys
import asyncio
from mcp import ClientSession  # type: ignore
from mcp.client.streamable_http import streamablehttp_client  # type: ignore

URL = os.getenv("MCP_SERVER_URL", "http://python-mcp:9123/mcp")


async def run() -> int:
        try:
                async with streamablehttp_client(url=URL, headers={}) as (read_stream, write_stream, _):
                        async with ClientSession(read_stream, write_stream) as session:
                                await session.initialize()
                return 0
        except Exception as e:
                print(f"mcp connection failed: {e}", file=sys.stderr)
                return 1


if __name__ == "__main__":
        sys.exit(asyncio.run(run()))
