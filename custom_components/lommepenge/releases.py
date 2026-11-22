"""Appens versioner: henter den nyeste release fra GitHub.

HA er den eneste, der kender GitHub-nøglen. Enhederne henter selve
APK-filen fra HA, som streamer den videre fra GitHub (intet gemmes på
disken, så den fylder ikke i HA's backups).
"""

from __future__ import annotations

from dataclasses import dataclass
import logging
import re
from typing import Any

import aiohttp
from aiohttp import web

from homeassistant.core import HomeAssistant
from homeassistant.helpers.aiohttp_client import async_get_clientsession
from homeassistant.helpers.update_coordinator import DataUpdateCoordinator, UpdateFailed

from .const import DOMAIN, RELEASE_CHECK_INTERVAL

_LOGGER = logging.getLogger(__name__)

GITHUB_API = "https://api.github.com"
_TAG = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)$")
_SHA256 = re.compile(r"^[0-9a-f]{64}$")


class GitHubError(Exception):
    """GitHub svarede ikke som forventet."""


class GitHubAuthError(GitHubError):
    """Nøglen er ugyldig eller har ikke adgang."""


@dataclass(frozen=True)
class AppRelease:
    version: str
    version_code: int
    sha256: str
    size: int
    asset_url: str
    release_url: str
    notes: str | None

    def as_json(self) -> dict[str, Any]:
        """Det enhederne får at vide om opdateringen."""
        return {
            "version": self.version,
            "versionCode": self.version_code,
            "sha256": self.sha256,
            "size": self.size,
        }


def version_code(tag: str) -> int | None:
    """`v1.2.3` -> 10203 (samme regel som app-repoets release-workflow)."""
    match = _TAG.match(tag)
    if match is None:
        return None
    major, minor, patch = (int(part) for part in match.groups())
    return major * 10000 + minor * 100 + patch


class GitHubReleases:
    """Læser releases fra ét (privat) repo med en læse-nøgle."""

    def __init__(self, session: aiohttp.ClientSession, repo: str, token: str) -> None:
        self._session = session
        self._repo = repo
        self._token = token

    def _headers(self, accept: str = "application/vnd.github+json") -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self._token}",
            "Accept": accept,
            "X-GitHub-Api-Version": "2022-11-28",
        }

    async def _get(self, url: str, accept: str = "application/vnd.github+json") -> aiohttp.ClientResponse:
        try:
            response = await self._session.get(
                url, headers=self._headers(accept), timeout=aiohttp.ClientTimeout(total=30)
            )
        except (aiohttp.ClientError, TimeoutError) as err:
            raise GitHubError(f"Kan ikke nå GitHub: {err}") from err
        if response.status in (401, 403):
            response.release()
            raise GitHubAuthError("GitHub afviste nøglen.")
        return response

    async def validate(self) -> None:
        """Tjekker at nøglen kan læse repoet."""
        response = await self._get(f"{GITHUB_API}/repos/{self._repo}")
        response.release()
        if response.status == 404:
            raise GitHubAuthError("Repoet findes ikke, eller nøglen har ikke adgang.")
        if response.status != 200:
            raise GitHubError(f"GitHub svarede {response.status}.")

    async def latest(self) -> AppRelease | None:
        """Nyeste release med en APK og dens SHA-256, eller `None`."""
        response = await self._get(f"{GITHUB_API}/repos/{self._repo}/releases/latest")
        if response.status == 404:
            response.release()
            return None
        if response.status != 200:
            response.release()
            raise GitHubError(f"GitHub svarede {response.status}.")
        release = await response.json()

        code = version_code(release.get("tag_name", ""))
        assets = {a["name"]: a for a in release.get("assets", [])}
        apk = next((a for name, a in assets.items() if name.endswith(".apk")), None)
        if code is None or apk is None or f"{apk['name']}.sha256" not in assets:
            _LOGGER.warning(
                "Release %s mangler versionsnummer, APK eller .sha256", release.get("tag_name")
            )
            return None

        checksum = await self._get(
            assets[f"{apk['name']}.sha256"]["url"], accept="application/octet-stream"
        )
        sha256 = (await checksum.text()).strip().split()[0].lower() if checksum.status == 200 else ""
        checksum.release()
        if not _SHA256.match(sha256):
            raise GitHubError("Ugyldig SHA-256 på releasen.")

        return AppRelease(
            version=release["tag_name"].lstrip("v"),
            version_code=code,
            sha256=sha256,
            size=apk["size"],
            asset_url=apk["url"],
            release_url=release.get("html_url", ""),
            notes=release.get("body"),
        )

    async def stream_apk(
        self, request: web.Request, release: AppRelease
    ) -> web.StreamResponse:
        """Sender APK'en videre til en enhed uden at gemme den."""
        upstream = await self._get(release.asset_url, accept="application/octet-stream")
        if upstream.status != 200:
            upstream.release()
            raise GitHubError(f"GitHub svarede {upstream.status} på APK'en.")
        response = web.StreamResponse(
            headers={
                "Content-Type": "application/vnd.android.package-archive",
                "Content-Disposition": f'attachment; filename="lommepenge-{release.version}.apk"',
                "Content-Length": str(release.size),
            }
        )
        await response.prepare(request)
        try:
            async for chunk in upstream.content.iter_chunked(256 * 1024):
                await response.write(chunk)
        finally:
            upstream.release()
        await response.write_eof()
        return response


class ReleaseCoordinator(DataUpdateCoordinator[AppRelease | None]):
    """Tjekker GitHub for en ny version af appen nogle gange i døgnet."""

    def __init__(self, hass: HomeAssistant, entry, repo: str, token: str) -> None:
        super().__init__(
            hass,
            _LOGGER,
            config_entry=entry,
            name=f"{DOMAIN}_releases",
            update_interval=RELEASE_CHECK_INTERVAL,
        )
        self.github = GitHubReleases(async_get_clientsession(hass), repo, token)

    async def _async_update_data(self) -> AppRelease | None:
        try:
            return await self.github.latest()
        except GitHubError as err:
            raise UpdateFailed(str(err)) from err
