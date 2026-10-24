"""Limits for the public laptop deployment. No filesystem or shell API is exposed."""
from __future__ import annotations

import asyncio
import ipaddress
import json
import time
from collections import OrderedDict, deque
from dataclasses import dataclass


@dataclass(frozen=True)
class PublicSettings:
    enabled: bool = False
    proxy: str = "none"
    json_limit: int = 64 * 1024
    upload_limit: int = 8 * 1024 * 1024 + 64 * 1024
    requests_per_minute: int = 240
    writes_per_minute: int = 60
    uploads_per_minute: int = 12
    concurrent_requests: int = 24
    body_timeout: float = 30


def client_address(scope, proxy: str = "none") -> str:
    peer = (scope.get("client") or ("unknown", 0))[0]
    # Uvicorn must run with --no-proxy-headers. Only the selected local
    # connector is allowed to supply the address used for abuse limits.
    if proxy == "cloudflare" and peer in ("127.0.0.1", "::1"):
        headers = dict(scope.get("headers", []))
        try:
            return str(ipaddress.ip_address(headers.get(b"cf-connecting-ip", b"").decode("ascii")))
        except (ValueError, UnicodeError):
            pass
    return peer


class PublicGuard:
    def __init__(self, app, settings: PublicSettings):
        self.app, self.settings = app, settings
        self.active = 0
        self.windows: OrderedDict[tuple[str, str], deque] = OrderedDict()

    def allow(self, identity: str, kind: str, maximum: int) -> bool:
        key, instant = (identity, kind), time.monotonic()
        values = self.windows.pop(key, deque())
        while values and values[0] <= instant - 60:
            values.popleft()
        allowed = len(values) < maximum
        if allowed:
            values.append(instant)
        self.windows[key] = values
        while len(self.windows) > 10_000:
            self.windows.popitem(last=False)
        return allowed

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        config = self.settings
        scope.setdefault("state", {})["pulse_address"] = client_address(scope, config.proxy)

        async def secure_send(message):
            if message["type"] == "http.response.start":
                headers = list(message.get("headers", []))
                headers.extend([(b"x-content-type-options", b"nosniff"),
                                (b"x-frame-options", b"DENY"),
                                (b"referrer-policy", b"no-referrer")])
                if config.enabled:
                    headers.extend([(b"strict-transport-security", b"max-age=86400"),
                                    (b"cache-control", b"no-store")])
                message["headers"] = headers
            await send(message)

        async def reject(status, detail, retry=False):
            content = json.dumps({"detail": detail}, ensure_ascii=False).encode()
            headers = [(b"content-type", b"application/json; charset=utf-8"),
                       (b"content-length", str(len(content)).encode())]
            if retry:
                headers.append((b"retry-after", b"60"))
            await secure_send({"type": "http.response.start", "status": status, "headers": headers})
            await secure_send({"type": "http.response.body", "body": content})

        if not config.enabled:
            return await self.app(scope, receive, secure_send)
        path, method = scope["path"], scope["method"]
        if not (path.startswith("/api/") or path.startswith("/uploads/") or path.startswith("/media/covers/")):
            return await reject(404, "Страница не найдена")
        if len(scope.get("query_string", b"")) > 4096 or len(path) > 1024:
            return await reject(414, "Слишком длинный адрес запроса")
        address = scope["state"]["pulse_address"]
        if not self.allow(address, "all", config.requests_per_minute):
            return await reject(429, "Слишком много запросов. Подождите минуту", True)
        headers = dict(scope.get("headers", []))
        # Per-address limits cannot be bypassed by inventing bearer tokens.
        if method not in ("GET", "HEAD", "OPTIONS"):
            if not self.allow(address, "write", config.writes_per_minute):
                return await reject(429, "Слишком много действий. Подождите минуту", True)
        uploading = method == "POST" and (path == "/api/uploads" or path.endswith("/images"))
        if uploading and not self.allow(address, "upload", config.uploads_per_minute):
            return await reject(429, "Слишком много фотографий. Подождите минуту", True)
        if self.active >= config.concurrent_requests:
            return await reject(503, "Сервер занят. Повторите немного позже", True)
        limit = config.upload_limit if uploading else config.json_limit
        try:
            declared = int(headers.get(b"content-length", b"0"))
        except ValueError:
            return await reject(400, "Некорректная длина запроса")
        if declared < 0 or declared > limit:
            return await reject(413, "Слишком большой запрос")
        self.active += 1
        try:
            body, more = bytearray(), True
            try:
                async with asyncio.timeout(config.body_timeout):
                    while more:
                        message = await receive()
                        if message["type"] == "http.disconnect":
                            return
                        chunk = message.get("body", b"")
                        if len(body) + len(chunk) > limit:
                            return await reject(413, "Слишком большой запрос")
                        body.extend(chunk)
                        more = message.get("more_body", False)
            except TimeoutError:
                return await reject(408, "Передача запроса заняла слишком много времени")
            delivered = False

            async def replay():
                nonlocal delivered
                if not delivered:
                    delivered = True
                    return {"type": "http.request", "body": bytes(body), "more_body": False}
                return await receive()

            await self.app(scope, replay, secure_send)
        finally:
            self.active -= 1
