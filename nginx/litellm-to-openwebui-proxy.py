#!/usr/bin/env python3

# Standard library
import argparse
from datetime import datetime, timezone
import json
import logging
from typing import Any, Dict, Optional

# Third-party
import httpx
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, Response
import litellm
from starlette.middleware.cors import CORSMiddleware
import uvicorn

# Local
from vault import VaultClient


class MCPAdapterProxy:
    class Settings:
        def __init__(
            self,
            litellm_url: str,
            timeout: float,
            log_level: str,
            enable_cors: bool,
            cors_allow_origins: list[str],
            vault_addr: str,
            token: str,
            mount: str,
            path: str
        ) -> None:
            self.litellm_url: str = litellm_url.rstrip("/")
            self.timeout: float = timeout
            self.log_level: str = log_level
            self.enable_cors: bool = enable_cors
            self.cors_allow_origins: list[str] = cors_allow_origins or ["*"]
            self.vault_addr: str = vault_addr
            self.token: str = token
            self.mount: str = mount
            self.path: str = path

    @classmethod
    def build_settings_from_args(cls, args: argparse.Namespace) -> "MCPAdapterProxy.Settings":
        return cls.Settings(
            litellm_url=args.litellm_url,
            timeout=args.timeout,
            log_level=args.log_level,
            enable_cors=args.enable_cors,
            cors_allow_origins=args.cors_allow_origins,
            vault_addr=args.vault_addr,
            token=args.token,
            mount=args.mount,
            path=args.path
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
        parser.add_argument("--vault-addr", "-a", default="http://localhost:8200",
                            help="Vault address (default: %(default)s)")
        parser.add_argument("--token", "-t", required=True,
                            help="Vault token", default="root")
        parser.add_argument("--mount", "-m", default="secret",
                            help="KV mount name (default: %(default)s)")
        parser.add_argument("--path", "-p", required=True, default="openwebui",
                            help="Secret path under the mount (e.g., %(default)s)")

        return parser.parse_args()

    @staticmethod
    def _get_auth_key(text: str) -> str:
        """
        Extract the API key from a bearer-style Authorization header.

        This function expects a string in the form "Bearer sk-xxxxxxx" and returns
        only the key portion ("sk-xxxxxxx"). Leading and trailing whitespace are ignored.
        If the input does not start with 'Bearer' followed by a space and a token,
        a ValueError is raised.

        Args:
            text: The Authorization header value, e.g., "Bearer sk-xxxxxxx".

        Returns:
            The extracted key string.

        Raises:
            ValueError: If the input does not start with 'Bearer'.
        """
        parts = text.strip().split(None, 1)
        if len(parts) != 2 or parts[0] != "Bearer":
            raise ValueError("string does not start with Bearer")
        return parts[1]

    def _fetch_secret_for_authorization(self, authorization: str) -> str:
        """
        Extract 'sk-...' from 'Bearer sk-...' and fetch its secret from Vault.

        Returns:
            The extracted key string.

        Raises:
            ValueError: If the authorization string is of an invalid format.
        """
        key = self._get_auth_key(authorization)
        auth_key: str | None = self._vault_client.get_kv(
            path=self._settings.path,            key=key)
        if auth_key is None:
            raise ValueError("Failed to retrieve auth key from Vault")
        return auth_key

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

        self._vault_client: VaultClient = VaultClient(
            addr=self._settings.vault_addr,
            token=self._settings.token,
            mount=self._settings.mount,
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
            try:
                auth: str = request.headers.get("authorization", "")
                litellm_auth_key = self._fetch_secret_for_authorization(authorization=auth)
                auth = f"Bearer {litellm_auth_key}"
                fwd_headers = {"Content-Type": "application/json"}
                if auth:
                    fwd_headers["Authorization"] = auth
            except Exception as e:
                logging.warning("Failed to forward Authorization header: %s", e)

            # Print incoming request headers to stdout
            try:
                headers_dict = {k: v for k, v in request.headers.items()}
                print(json.dumps(
                    {"incoming_request_headers": headers_dict}, ensure_ascii=False))
            except Exception as e:
                print(f"Failed to serialize headers: {e}")

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
