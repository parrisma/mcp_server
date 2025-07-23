from fastmcp import FastMCP
from pydantic import Field
from typing import Annotated, Dict, Any
from store import SecureStore

store = SecureStore()
mcp = FastMCP(name="DataGroupService", version="1.0.0")


@mcp.tool(name="put_key_value", description="Store a key:value associated with an access group")
async def put_key_value(
    key: Annotated[str, Field(description="The key to store")],
    value: Annotated[str, Field(description="The value to associate with the key")],
    group: Annotated[str, Field(
        description="The access group for this key-value pair")]
) -> Dict[str, Any]:
    store.put(key, value, group)
    return {"status": "stored", "key": key, "group": group}


@mcp.tool(name="get_value_by_key", description="Retrieve value for a key if access group matches")
async def get_value_by_key(
    key: Annotated[str, Field(description="The key to retrieve")],
    group: Annotated[str, Field(
        description="The access group to check against")]
) -> Dict[str, Any]:
    value = store.get(key, group)
    return {"result": value}

if __name__ == "__main__":
    print("Starting MCP server...")

    mcp.run(
        transport="streamable-http",
        host="0.0.0.0",
        port=9123,
        log_level="debug"
    )
    print("Done running MCP server")
