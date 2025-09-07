import uvicorn
import logging
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
import json

"""
This Python script is a test server for the Model Context Protocol (MCP) `securedata` service,
built using the FastAPI framework.

Its primary function is to verify that a proxy, such as LiteLLM, can correctly forward custom HTTP headers
to the MCP server.

It mimics the behavior of the actual MCP service, allowing developers to test their integration without needing
access to the real backend. It fits the mcp/secure_datagroup/openapi.json specification.

Here is a breakdown of what the program does:
- Initializes a FastAPI application: Sets up a web server that can handle incoming HTTP requests.
- Defines Pydantic models: Creates data validation classes (`PutKeyValueFormModel` and `GetValueByKeyFormModel`)
  that match the expected JSON body for the MCP tool calls, ensuring incoming data has the correct structure.
- Logs all incoming headers: A custom middleware intercepts every incoming HTTP request to log all request headers
  to the console. This allows a developer to confirm that specific headers, like `x-mcp-securedata-auth`, are being
  received by the server.
- Handles MCP tool endpoints: It defines API endpoints that match the MCP's OpenAPI specification
  (`put_key_value`, `get_value_by_key`, and `test`).
- Logs received data: For each tool call, the server logs the tool name and the data received in the request body.
- Returns a static response: Each endpoint simply returns a static JSON response of `{"status": "failed"}`.
  It does not perform any actual MCP business logic, as its purpose is purely for testing connectivity and
  header forwarding.
- Starts the server: The script uses the Uvicorn server to run the FastAPI application, listening for
  requests on a specified port.

In summary, this server acts as a simple "black hole" endpoint for MCP calls. It's an indispensable tool for
debugging the communication flow between a client, a LiteLLM proxy, and the backend MCP service by providing clear
evidence of whether expected headers are correctly propagated.
"""

# Configure logging to display INFO level messages to the console
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI()

# Pydantic models were used previously; endpoints now accept arbitrary JSON for flexibility.

# Middleware to log all incoming request headers


@app.middleware("http")
async def log_headers_middleware(request: Request, call_next):
    logger.info("--- Incoming Start ---")
    # Log method and exact path
    logger.info("Request: %s %s", request.method, request.url.path)
    # Log the full set of headers
    logger.info("--- Incoming Request Headers ---")
    for header, value in request.headers.items():
        logger.info(f"{header}: {value}")
    logger.info("--- Incoming End ---")
    logger.info("--------------------")

    # Process the request normally
    response = await call_next(request)
    return response

# Define the endpoint handlers


async def _dump_request(request: Request):
    logger.info("--- Incoming Request ---")
    logger.info("Headers:")
    for header, value in request.headers.items():
        logger.info(f"  {header}: {value}")
    logger.info("Body:")
    body = await request.body()
    logger.info(f"  {body.decode('utf-8', errors='replace')}")
    logger.info("----------------------------------")


@app.post("/")
async def home(request: Request):
    logger.info("/")
    await _dump_request(request)
    return JSONResponse(content={"status": "ok"})


@app.post("/mcp")
async def mcp(request: Request):
    logger.info("/mcp")
    await _dump_request(request)
    return JSONResponse(content={"status": "ok"})


@app.post("/mcp/tools/call")
async def tool_call(request: Request):
    logger.info("/mcp/tools/call")
    await _dump_request(request)
    return JSONResponse(content={"status": "ok"})


@app.post("/mcp/tools/call/put_key_value")
async def tool_put_key_value(request: Request):
    logger.info("/mcp/tools/call/put_key_value")
    await _dump_request(request)
    return JSONResponse(content={"status": "ok"})


@app.post("/mcp/tools/call/get_value_by_key")
async def tool_get_value_by_key(request: Request):
    logger.info("/mcp/tools/call/get_value_by_key")
    await _dump_request(request)
    return JSONResponse(content={"status": "ok"})


@app.post("/mcp/tools/call/test")
async def tool_test(request: Request):
    logger.info("/mcp/tools/call/test")
    await _dump_request(request)
    return JSONResponse(content={"status": "ok"})


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Run the test MCP server")
    parser.add_argument("--host", default="0.0.0.0",
                        help="Bind host (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=9123,
                        help="Bind port (default: 9123)")
    args = parser.parse_args()

    uvicorn.run(app, host=args.host, port=args.port)


if __name__ == "__main__":
    main()
