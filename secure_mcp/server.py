import logging
import httpx
import argparse
from fastmcp import FastMCP
from fastmcp.server.dependencies import get_http_headers
from pydantic import Field
from typing import Annotated, Dict, Any, Optional
from store import SecureStore
from datetime import datetime

# Configure basic logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)


class DataGroupServiceServer:
    """Class-based MCP server exposing key-value tools."""

    def __init__(self, host: str = "0.0.0.0",
                 port: int = 9123,
                 token: Optional[str] = None) -> None:
        self.logger = logging.getLogger(__name__)
        self.store = SecureStore()
        # Private server configuration with defaults
        self._host = host
        self._port = port
        self._token = token
        # Configure optional Bearer token for outbound API client
        self.mcp = FastMCP(name="DataGroupService", version="1.0.0")
        self._register_tools()

    def get_base_url(self, scheme: str = "http") -> str:
        """Return the server base URL constructed from host and port.
        Example: http://0.0.0.0:9123
        """
        return f"{scheme}://{self._host}:{self._port}"

    def _register_tools(self) -> None:
        """Register MCP tools, capturing `self` via closure."""

        @self.mcp.tool(name="put_key_value", description="Store a key:value associated with an access group")
        async def put_key_value(
            key: Annotated[str, Field(description="The key to store")],
            value: Annotated[str, Field(description="The value to associate with the key")],
            group: Annotated[str, Field(
                description="The access group for this key-value pair")]
        ) -> Dict[str, Any]:
            self.logger.info(
                f"put_key_value called with key={key}, group={group}")
            res = self.store.put(key, value, group)
            self.logger.info(f"put_key_value returned {res}")
            return res

        @self.mcp.tool(name="get_value_by_key", description="Retrieve value for a key if access group matches")
        async def get_value_by_key(
            key: Annotated[str, Field(description="The key to retrieve")],
            group: Annotated[str, Field(
                description="The access group to check against")]
        ) -> Dict[str, Any]:
            self.logger.info(
                f"get_value_by_key called with key={key}, group={group}")
            res = self.store.get(key, group)
            self.logger.info(f"get_value_by_key returned {res}")
            return res

        @self.mcp.tool(name="test", description="Test tool that returns server name and current datetime")
        async def test() -> Dict[str, Any]:
            """Test tool that returns the MCP server name and current datetime"""
            self.logger.info("test tool called")
            headers = get_http_headers()
            self.logger.debug(f"Headers: {headers}")
            result = {
                "server_name": "DataGroupService",
                "current_datetime": datetime.now().isoformat(),
                "timestamp_utc": datetime.utcnow().isoformat() + "Z",
                "headers": headers,
            }
            self.logger.info(f"test tool returned {result}")
            return result

    def run(self, log_level: str = "info") -> None:
        self.logger.info("Starting MCP server...")
        self.mcp.run(
            transport="streamable-http",
            host=self._host,
            port=self._port,
            log_level=log_level,
        )
        self.logger.info("MCP server stopped")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Run DataGroupService MCP server")
    parser.add_argument("--host", "-H", default="0.0.0.0",
                        help="Host/IP to bind (default: 0.0.0.0)")
    parser.add_argument("--port", "-P", type=int, default=9123,
                        help="Port to bind (default: 9123)")
    parser.add_argument("--token", "-t", dest="token", default=None,
                        help="Bearer token for outbound API requests (sets Authorization header)")
    args = parser.parse_args()

    app = DataGroupServiceServer(
        host=args.host, port=args.port, token=args.token)
    app.run()
