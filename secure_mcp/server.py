from fastmcp import FastMCP
from pydantic import Field
from typing import Annotated, Dict, Any
from store import SecureStore
import logging
from datetime import datetime

store = SecureStore()

# Configure basic logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger(__name__)

mcp = FastMCP(name="DataGroupService", version="1.0.0")

@mcp.tool(name="put_key_value", description="Store a key:value associated with an access group")
async def put_key_value(
    key: Annotated[str, Field(description="The key to store")],
    value: Annotated[str, Field(description="The value to associate with the key")],
    group: Annotated[str, Field(
        description="The access group for this key-value pair")]
) -> Dict[str, Any]:
    logger.info(f"put_key_value called with key={key}, group={group}")
    res = store.put(key, value, group)
    logger.info(f"put_key_value returned {res}")
    return res


@mcp.tool(name="get_value_by_key", description="Retrieve value for a key if access group matches")
async def get_value_by_key(
    key: Annotated[str, Field(description="The key to retrieve")],
    group: Annotated[str, Field(
        description="The access group to check against")]
) -> Dict[str, Any]:
    logger.info(f"get_value_by_key called with key={key}, group={group}")
    res = store.get(key, group)
    logger.info(f"get_value_by_key returned {res}")
    return res


@mcp.tool(name="test", description="Test tool that returns server name and current datetime")
async def test() -> Dict[str, Any]:
    """Test tool that returns the MCP server name and current datetime"""
    logger.info("test tool called")
    result = {
        "server_name": "DataGroupService",
        "current_datetime": datetime.now().isoformat(),
        "timestamp_utc": datetime.utcnow().isoformat() + "Z"
    }
    logger.info(f"test tool returned {result}")
    return result

if __name__ == "__main__":
    logger.info("Starting MCP server...")
    mcp.run(
        transport="streamable-http",
        host="0.0.0.0",
        port=9123,
        log_level="info"
    )
    logger.info("MCP server stopped")
