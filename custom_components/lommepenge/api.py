"""Klient til lommepenge-appens HA-API på køleskabsskærmen (`/ha/*`)."""

from __future__ import annotations

import asyncio
from typing import Any

import aiohttp

REQUEST_TIMEOUT = 10


class LommepengeError(Exception):
    """Generel fejl fra skærmen (fx ugyldig værdi)."""


class CannotConnect(LommepengeError):
    """Skærmen kunne ikke nås."""


class InvalidAuth(LommepengeError):
    """Forkert PIN eller ugyldig/tilbagekaldt nøgle."""


class TooManyAttempts(LommepengeError):
    """For mange forkerte PIN-forsøg - skærmen er midlertidigt låst."""


class LommepengeApi:
    """Tynd async-klient. Én instans pr. køleskabsskærm."""

    def __init__(
        self,
        session: aiohttp.ClientSession,
        host: str,
        port: int,
        token: str | None = None,
    ) -> None:
        self._session = session
        self._base = f"http://{host}:{port}"
        self._token = token

    async def _request(
        self,
        method: str,
        path: str,
        body: dict[str, Any] | None = None,
        *,
        auth: bool = True,
    ) -> dict[str, Any]:
        headers = {}
        if auth and self._token:
            headers["Authorization"] = f"Bearer {self._token}"
        try:
            async with asyncio.timeout(REQUEST_TIMEOUT):
                async with self._session.request(
                    method, f"{self._base}{path}", json=body, headers=headers
                ) as response:
                    try:
                        data = await response.json(content_type=None)
                    except ValueError:
                        data = {}
                    if not isinstance(data, dict):
                        data = {}
                    message = data.get("error") or f"HTTP {response.status}"
                    if response.status == 401:
                        raise InvalidAuth(message)
                    if response.status == 429:
                        raise TooManyAttempts(message)
                    if response.status >= 400:
                        raise LommepengeError(message)
                    return data
        except (aiohttp.ClientError, TimeoutError) as err:
            raise CannotConnect(str(err)) from err

    async def pair(self, pin: str) -> dict[str, Any]:
        """Bytter forælder-PIN til en nøgle: `{token, screenId, familyName}`."""
        return await self._request("POST", "/ha/pair", {"pin": pin}, auth=False)

    async def summary(self) -> dict[str, Any]:
        """Samlet overblik: børn, spærring, ventende godkendelser, indstillinger."""
        return await self._request("GET", "/ha/summary")

    async def action(
        self, action_type: str, payload: dict[str, Any]
    ) -> dict[str, Any]:
        """Udfører en tilladt handling og returnerer et frisk overblik."""
        return await self._request(
            "POST", "/ha/action", {"type": action_type, "payload": payload}
        )

    async def register_webhook(self, url: str) -> None:
        """Fortæller skærmen hvor den skal skubbe hændelser hen."""
        await self._request("POST", "/ha/webhook", {"url": url})
