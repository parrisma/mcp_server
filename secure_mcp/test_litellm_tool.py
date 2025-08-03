import asyncio
from litellm import acompletion

async def test_put_key_value():
    response = await acompletion(
        model="gpt-4",
        api_base="http://localhost:4000",
        api_key="sk-1234567890abcdef",
        messages=[
            {
                "role": "user",
                "content": "Store key test_cli with value litellm_test in group verify."
            }
        ],
        tools=[
            {
                "type": "function",
                "function": {
                    "name": "put_key_value",
                    "description": "Stores a key-value pair",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "key": {"type": "string"},
                            "value": {"type": "string"},
                            "group": {"type": "string"}
                        },
                        "required": ["key", "value", "group"]
                    }
                }
            }
        ],
        tool_choice={"type": "function", "function": {"name": "put_key_value"}}
    )

    print("Put Key Response:\n", response.choices[0].message.tool_calls)

async def test_get_value_by_key():
    response = await acompletion(
        model="gpt-4",
        api_base="http://localhost:4000",
        api_key="sk-1234567890abcdef",
        messages=[
            {
                "role": "user",
                "content": "Retrieve key test_cli from group verify."
            }
        ],
        tools=[
            {
                "type": "function",
                "function": {
                    "name": "get_value_by_key",
                    "description": "Retrieves a key-value pair",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "key": {"type": "string"},
                            "group": {"type": "string"}
                        },
                        "required": ["key", "group"]
                    }
                }
            }
        ],
        tool_choice={"type": "function", "function": {"name": "get_value_by_key"}}
    )

    print("Put Value Response:\n", response.choices[0].message.tool_calls)

if __name__ == "__main__":
    asyncio.run(test_put_key_value())
    asyncio.run(test_get_value_by_key())