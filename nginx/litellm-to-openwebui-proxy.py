#!/usr/bin/env python3
import argparse
import json
import logging
from typing import Any, Dict, Optional

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, Response
from starlette.middleware.cors import CORSMiddleware
import uvicorn
from datetime import datetime, timezone


class MCPAdapterProxy:
    class Settings:
        def __init__(
            self,
            litellm_url: str = "http://litellm:4000/mcp-rest/tools/call",
            timeout: float = 30.0,
            log_level: str = "info",
            enable_cors: bool = False,
            cors_allow_origins: Optional[list[str]] = None,
        ) -> None:
            self.litellm_url = litellm_url.rstrip("/")
            self.timeout = timeout
            self.log_level = log_level
            self.enable_cors = enable_cors
            self.cors_allow_origins = cors_allow_origins or ["*"]

    @classmethod
    def build_settings_from_args(cls, args: argparse.Namespace) -> "MCPAdapterProxy.Settings":
        return cls.Settings(
            litellm_url=args.litellm_url,
            timeout=args.timeout,
            log_level=args.log_level,
            enable_cors=args.enable_cors,
            cors_allow_origins=args.cors_allow_origins,
        )

    @staticmethod
    def parse_args() -> argparse.Namespace:
        parser = argparse.ArgumentParser(
            description="MCP Adapter: /mcp-rest/tools/call/<tool-id> -> LiteLLM /mcp-rest/tools/call"
        )
        parser.add_argument("--host", default="0.0.0.0",
                            help="Host to bind (default: 0.0.0.0)")
        parser.add_argument("--port", type=int, default=8088,
                            help="Port to bind (default: 8088)")
        parser.add_argument(
            "--litellm-url",
            dest="litellm_url",
            default="http://litellm:4000/mcp-rest/tools/call",
            help="LiteLLM tools call URL",
        )
        parser.add_argument("--timeout", type=float, default=30.0,
                            help="Upstream timeout seconds (default: 30.0)")
        parser.add_argument(
            "--log-level",
            default="info",
            choices=["debug", "info", "warning", "error", "critical"],
            help="Log level (default: info)",
        )
        parser.add_argument("--enable-cors", action="store_true",
                            help="Enable CORS on the adapter")
        parser.add_argument(
            "--cors-allow-origins",
            nargs="*",
            default=["*"],
            help="Allowed origins for CORS (default: *)",
        )
        return parser.parse_args()

    def __init__(self,
                 settings: Optional["MCPAdapterProxy.Settings"] = None,
                 args: Optional[argparse.Namespace] = None) -> None:

        # Parse args and build settings here if not provided
        if args is None:
            args = MCPAdapterProxy.parse_args()
        self._args = args

        if settings is None:
            settings = MCPAdapterProxy.build_settings_from_args(args)
        self._settings = settings

        # Logging setup using configured log level
        logging.basicConfig(
            level=getattr(logging, str(
                self._settings.log_level).upper(), logging.INFO),
            format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        )
        _logger = logging.getLogger("mcp_adapter")

        self.app = FastAPI(title="LiteLLM <-> OpenWebUI MCP Adapter")

        # Optional CORS
        if self._settings.enable_cors:
            self.app.add_middleware(
                CORSMiddleware,
                allow_origins=self._settings.cors_allow_origins,
                allow_credentials=False,
                allow_methods=["GET", "POST", "PUT", "OPTIONS"],
                allow_headers=["*"],
                max_age=86400,
            )

        settings_snapshot = {
            "app_title": self.app.title,
            "litellm_url": self._settings.litellm_url,
            "timeout": self._settings.timeout,
            "log_level": self._settings.log_level,
            "enable_cors": self._settings.enable_cors,
            "cors_allow_origins": self._settings.cors_allow_origins,
            "bind_host": getattr(self._args, "host", "0.0.0.0"),
            "bind_port": getattr(self._args, "port", 8088),
        }
        _logger.info("Adapter settings: %s", json.dumps(
            settings_snapshot, ensure_ascii=False))

        # Routes defined within init to capture `self`
        @self.app.get("/health")
        async def health() -> Dict[str, Any]:
            now = datetime.now(timezone.utc)
            return {
                "status": "ok",
                "date": now.date().isoformat(),
                "timestamp": now.isoformat(),
                "service": {
                    "title": self.app.title,
                    "description": "Adapter proxying /mcp-rest/tools/call to LiteLLM",
                },
                "settings": {
                    "litellm_url": self._settings.litellm_url,
                    "timeout": self._settings.timeout,
                    "log_level": self._settings.log_level,
                    "enable_cors": self._settings.enable_cors,
                    "cors_allow_origins": self._settings.cors_allow_origins,
                },
            }

        @self.app.options("/mcp-rest/tools/call/{tool_id:path}")
        async def options_tool(tool_id: str) -> Response:  # noqa: ARG001
            return Response(status_code=204)

        @self.app.post("/mcp-rest/tools/call/{tool_id:path}")
        async def call_tool(tool_id: str, request: Request) -> Response:
            # Read body
            content_type = request.headers.get("content-type", "")
            body_bytes = await request.body()
            body_json: Optional[Dict[str, Any]] = None

            if content_type.startswith("application/json") and body_bytes:
                try:
                    parsed = json.loads(body_bytes.decode("utf-8"))
                    if isinstance(parsed, dict):
                        body_json = parsed
                except Exception as e:  # pragma: no cover - log parse errors
                    logging.warning("Invalid JSON body: %s", e)

            # Build payload for LiteLLM
            payload: Dict[str, Any]
            if body_json is None:
                # No/invalid JSON: treat as empty arguments
                payload = {"name": tool_id, "arguments": {}}
            else:
                if "name" in body_json and "arguments" in body_json:
                    payload = body_json
                elif "arguments" in body_json and isinstance(body_json["arguments"], dict):
                    # Add name if missing
                    payload = {"name": body_json.get(
                        "name", tool_id), "arguments": body_json["arguments"]}
                else:
                    # Treat whole body as arguments
                    payload = {"name": tool_id, "arguments": body_json}

            # Forward Authorization
            auth = request.headers.get("authorization", "")
            fwd_headers = {"Content-Type": "application/json"}
            if auth:
                fwd_headers["Authorization"] = auth

            # POST to LiteLLM endpoint
            try:
                async with httpx.AsyncClient(timeout=self._settings.timeout) as client:
                    r = await client.post(self._settings.litellm_url, json=payload, headers=fwd_headers)
                # Pass through response
                media_type = r.headers.get("content-type", "application/json")
                return Response(content=r.content, status_code=r.status_code, media_type=media_type)
            except httpx.RequestError as e:
                logging.error("Upstream request error: %s", e)
                return JSONResponse({"detail": "Upstream unavailable", "error": str(e)}, status_code=502)

    def run(self, host: Optional[str] = None, port: Optional[int] = None) -> None:
        # Default to CLI args if not explicitly provided and ensure concrete types
        host_val: str = host if host is not None else getattr(
            self._args, "host", "0.0.0.0")
        port_val: int = port if port is not None else getattr(
            self._args, "port", 8088)
        uvicorn.run(self.app, host=host_val, port=port_val,
                    log_level=self._settings.log_level)


if __name__ == "__main__":
    proxy = MCPAdapterProxy()
    proxy.run()
