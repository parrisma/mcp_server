#!/usr/bin/env python3
"""
MCP Streamable HTTP Client - Upgraded to follow official MCP library pattern
"""

import argparse
import asyncio
import json
from typing import Optional
from contextlib import AsyncExitStack

from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client


class MCPClient:
    """MCP Client for interacting with an MCP Streamable HTTP server"""

    def __init__(self):
        # Initialize session and client objects
        self.session = None
        self.exit_stack = AsyncExitStack()
        self._streams_context = None
        self._session_context = None

    def _extract_text_content(self, result):
        """Safely extract text content from MCP result"""
        if hasattr(result.content[0], 'text'):
            return result.content[0].text
        else:
            return str(result.content[0])

    async def connect_to_streamable_http_server(
        self, server_url: str, headers: Optional[dict] = None
    ):
        """Connect to an MCP server running with HTTP Streamable transport"""
        self._streams_context = streamablehttp_client(
            url=server_url,
            headers=headers or {},
        )
        read_stream, write_stream, _ = await self._streams_context.__aenter__()

        self._session_context = ClientSession(read_stream, write_stream)
        self.session = await self._session_context.__aenter__()

        await self.session.initialize()

    async def list_tools(self):
        """List available tools from the MCP server"""
        if not self.session:
            raise RuntimeError("Not connected to MCP server")
        
        response = await self.session.list_tools()
        return response

    async def call_tool(self, tool_name: str, arguments: dict):
        """Call a specific tool with given arguments"""
        if not self.session:
            raise RuntimeError("Not connected to MCP server")
        
        result = await self.session.call_tool(tool_name, arguments)
        return result

    async def run_tests(self):
        """Run comprehensive tests with assertions to validate expected results"""
        print("\nRunning MCP client tests...")
        
        try:
            # Test 1: List available tools
            print("\n1. Testing tool listing...")
            tools_response = await self.list_tools()
            print("Available tools:")
            for tool in tools_response.tools:
                print(f"  - {tool.name}: {tool.description}")
            
            # Assert expected tools are available
            tool_names = [tool.name for tool in tools_response.tools]
            assert "put_key_value" in tool_names, "put_key_value tool not found"
            assert "get_value_by_key" in tool_names, "get_value_by_key tool not found"
            print("✓ Tool listing test passed")

            # Test 2: Store a key-value pair
            print("\n2. Testing put_key_value tool...")
            put_result = await self.call_tool(
                "put_key_value",
                {
                    "key": "test_key",
                    "value": "test_value",
                    "group": "test_group"
                }
            )
            print(f"Put result: {put_result.content}")
            
            # Parse and validate the result
            import json
            # Safely extract text content
            put_text = self._extract_text_content(put_result)
            put_data = json.loads(put_text)
            assert put_data["status"] == "stored", f"Expected status 'stored', got {put_data['status']}"
            assert put_data["key"] == "test_key", f"Expected key 'test_key', got {put_data['key']}"
            assert put_data["group"] == "test_group", f"Expected group 'test_group', got {put_data['group']}"
            print("✓ Put key-value test passed")

            # Test 3: Retrieve the stored value
            print("\n3. Testing get_value_by_key tool...")
            get_result = await self.call_tool(
                "get_value_by_key",
                {
                    "key": "test_key",
                    "group": "test_group"
                }
            )
            print(f"Get result: {get_result.content}")
            
            # Parse and validate the result
            get_text = self._extract_text_content(get_result)
            get_data = json.loads(get_text)
            assert get_data["result"] == "test_value", f"Expected result 'test_value', got {get_data['result']}"
            print("✓ Get key-value test passed")

            # Test 4: Test access control (wrong group)
            print("\n4. Testing access control (wrong group)...")
            access_result = await self.call_tool(
                "get_value_by_key",
                {
                    "key": "test_key",
                    "group": "wrong_group"
                }
            )
            print(f"Access control result: {access_result.content}")
            
            # Parse and validate access denial
            access_text = self._extract_text_content(access_result)
            access_data = json.loads(access_text)
            assert access_data["result"] == "Access denied", f"Expected 'Access denied', got {access_data['result']}"
            print("✓ Access control test passed")

            # Test 5: Test non-existent key
            print("\n5. Testing non-existent key...")
            missing_result = await self.call_tool(
                "get_value_by_key",
                {
                    "key": "non_existent_key",
                    "group": "test_group"
                }
            )
            print(f"Missing key result: {missing_result.content}")
            
            # Parse and validate key not found
            missing_text = self._extract_text_content(missing_result)
            missing_data = json.loads(missing_text)
            assert missing_data["result"] == "Key not found", f"Expected 'Key not found', got {missing_data['result']}"
            print("✓ Non-existent key test passed")

            print("\n🎉 All tests passed successfully!")

        except AssertionError as e:
            print(f"\nTest failed: {e}")
            raise
        except Exception as e:
            print(f"\nTest error: {e}")
            raise

    async def cleanup(self):
        """Properly clean up the session and streams"""
        if hasattr(self, '_session_context') and self._session_context:
            await self._session_context.__aexit__(None, None, None)
        if hasattr(self, '_streams_context') and self._streams_context:
            await self._streams_context.__aexit__(None, None, None)


async def health_check(client, server_url):
    """Run a quick health check for Docker health monitoring"""
    try:
        await client.connect_to_streamable_http_server(server_url)
        
        # Quick test: just list tools to verify server is responding
        tools_response = await client.list_tools()
        tool_names = [tool.name for tool in tools_response.tools]
        
        # Verify expected tools are available
        if "put_key_value" not in tool_names or "get_value_by_key" not in tool_names:
            return False
            
        # Quick functional test: store and retrieve a value
        await client.call_tool(
            "put_key_value",
            {"key": "health_check", "value": "ok", "group": "health"}
        )
        
        get_result = await client.call_tool(
            "get_value_by_key",
            {"key": "health_check", "group": "health"}
        )
        
        # Verify the result
        get_text = client._extract_text_content(get_result)
        get_data = json.loads(get_text)
        
        return get_data["result"] == "ok"
        
    except Exception:
        return False


async def main():
    """Main function to run the MCP client"""
    import os
    import sys
    
    parser = argparse.ArgumentParser(description="Run MCP Streamable HTTP Client")
    
    # Default URL depends on environment
    default_url = os.getenv("MCP_SERVER_URL", "http://127.0.0.1:9123/mcp")
    
    parser.add_argument(
        "--server-url",
        default=default_url,
        help="MCP server URL"
    )
    
    parser.add_argument(
        "--health-check",
        action="store_true",
        help="Run health check mode for Docker health monitoring"
    )
    
    args = parser.parse_args()
    
    client = MCPClient()

    try:
        if args.health_check:
            # Health check mode - minimal output, exit codes for Docker
            success = await health_check(client, args.server_url)
            sys.exit(0 if success else 1)
        else:
            # Normal test mode
            print(f"Connecting to MCP server at {args.server_url}...")
            await client.connect_to_streamable_http_server(args.server_url)
            print("Connected successfully!")

            await client.run_tests()
    except Exception as e:
        if args.health_check:
            sys.exit(1)
        else:
            print(f"Error: {e}")
            import traceback
            traceback.print_exc()
    finally:
        await client.cleanup()


if __name__ == "__main__":
    print("Starting MCP Streamable HTTP Client...")
    asyncio.run(main())