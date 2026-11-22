"""HTTP-API'et som appen taler med - kun på hjemmenettet.

Appen bruger ikke HA's egne brugere/tokens. Hver enhed har sin egen nøgle
(fra parringen) og signerer alle forespørgsler, så en barne-tablet aldrig
får adgang til resten af Home Assistant.

    GET  /api/lommepenge/install/{token}        installationsside (QR-koden)
    GET  /api/lommepenge/qr/{token}.svg         QR-koden til "Tilføj enhed"
    GET  /api/lommepenge/download/{token}/...   APK til første installation
    GET  /api/lommepenge/app.apk                APK uden kode (enheder uden kamera)
    POST /api/lommepenge/pair                   parringslink -> enhedsnøgle
    GET  /api/lommepenge/state                  familiens data   (signeret)
    POST /api/lommepenge/action                 udfør handling   (signeret)
    GET  /api/lommepenge/apk                    APK til opdatering (signeret)
"""

from __future__ import annotations

from html import escape
from http import HTTPStatus
from ipaddress import ip_address
import io
import json
import logging
from typing import Any
from urllib.parse import quote

from aiohttp import web
import segno

from homeassistant.components.http import KEY_HASS, HomeAssistantView
from homeassistant.core import HomeAssistant
from homeassistant.helpers.network import NoURLAvailableError, get_url, is_cloud_connection
from homeassistant.util import network as network_util

from .const import API_PREFIX, DOMAIN, ROLE_CHILD, ROLE_PARENT, ROLE_SCREEN
from .family import FamilyError
from .releases import GitHubError
from .runtime import (
    AuthError,
    ForbiddenError,
    LommepengeRuntime,
    PairingError,
    TooManyPairingAttempts,
)

_LOGGER = logging.getLogger(__name__)

APP_PACKAGE = "dk.familie.lommepenge_app"
MAX_BODY = 64 * 1024

ROLE_LABELS = {
    ROLE_SCREEN: "Fælles skærm",
    ROLE_PARENT: "Forælder",
    ROLE_CHILD: "Barnets tablet",
}


def async_register_views(hass: HomeAssistant) -> None:
    for view in (
        InstallPageView,
        QrCodeView,
        DownloadView,
        PairView,
        StateView,
        ActionView,
        UpdateApkView,
        AppApkView,
    ):
        hass.http.register_view(view())


def base_url(hass: HomeAssistant) -> str:
    """HA's adresse på hjemmenettet. Bruger den lokale IP, så en ny enhed kan
    nå den uden at kende `homeassistant.local`."""
    api = hass.config.api
    if api is not None and api.local_ip and api.local_ip != "127.0.0.1":
        scheme = "https" if api.use_ssl else "http"
        return f"{scheme}://{api.local_ip}:{api.port}"
    try:
        return get_url(hass, allow_external=False, allow_cloud=False, prefer_external=False)
    except NoURLAvailableError:
        return ""


def install_url(hass: HomeAssistant, token: str) -> str:
    """Link i QR-koden (og til at taste i en browser)."""
    return f"{base_url(hass)}{API_PREFIX}/install/{token}"


def app_url(hass: HomeAssistant) -> str:
    """Fast link til appen - kræver ingen kode."""
    return f"{base_url(hass)}{API_PREFIX}/app.apk"


def _runtime(request: web.Request) -> LommepengeRuntime:
    runtime = request.app[KEY_HASS].data.get(DOMAIN)
    if runtime is None:
        raise web.HTTPServiceUnavailable(text="Lommepenge er ikke sat op i Home Assistant.")
    return runtime


def _require_local(request: web.Request) -> None:
    """Kun hjemmenettet - aldrig via HA's eksterne adresse eller skyen."""
    hass = request.app[KEY_HASS]
    try:
        local = not is_cloud_connection(hass) and network_util.is_local(
            ip_address(request.remote or "")
        )
    except ValueError:
        local = False
    if not local:
        raise web.HTTPForbidden(text="Kun tilgængelig på hjemmenettet.")


def _error(status: HTTPStatus, message: str) -> web.Response:
    return web.json_response({"error": message}, status=status)


class _LocalView(HomeAssistantView):
    """Appens endpoints: ingen HA-login, men altid kun lokalt."""

    requires_auth = False
    cors_allowed = False


class _SignedView(_LocalView):
    """Endpoints der kræver en parret enheds signatur."""

    async def _device(self, request: web.Request, body: bytes) -> tuple[LommepengeRuntime, dict[str, Any]]:
        _require_local(request)
        runtime = _runtime(request)
        headers = request.headers  # opslag uden hensyn til store/små bogstaver
        try:
            device = runtime.verify(headers, request.method, request.path, body)
        except AuthError as err:
            raise web.HTTPUnauthorized(
                text=json.dumps({"error": str(err)}), content_type="application/json"
            ) from err
        runtime.async_device_seen(device, headers)
        return runtime, device


# ---- Installation og parring -------------------------------------------------


class InstallPageView(_LocalView):
    url = f"{API_PREFIX}/install/{{token}}"
    name = "api:lommepenge:install"

    async def get(self, request: web.Request, token: str) -> web.Response:
        _require_local(request)
        runtime = _runtime(request)
        pairing = runtime.pairing(token)
        if pairing is None or pairing.get("used"):
            return _page(
                "Linket er udløbet",
                "<p>Lav en ny QR-kode i Home Assistant under "
                "<b>Lommepenge → Tilføj enhed</b>.</p>",
            )
        origin = f"{request.scheme}://{request.host}"
        pair_link = (
            f"intent://pair?url={quote(origin, safe='')}&token={quote(token, safe='')}"
            f"#Intent;scheme=lommepenge;package={APP_PACKAGE};end"
        )
        release = runtime.releases.data if runtime.releases is not None else None
        if release is not None:
            download = (
                f'<a class="button" href="{API_PREFIX}/download/{token}/'
                f'lommepenge-{escape(release.version)}.apk">1. Hent appen</a>'
                f"<p class=\"hint\">Version {escape(release.version)}. Android spørger én gang, "
                "om browseren må installere apps - sig ja.</p>"
            )
        else:
            download = (
                "<p class=\"hint\">Home Assistant har ikke kunnet hente appen fra GitHub "
                "endnu. Har enheden allerede appen, kan du springe trin 1 over.</p>"
            )
        body = (
            f"<p>{escape(runtime.family_name)} · {escape(ROLE_LABELS.get(pairing['role'], ''))}"
            f": <b>{escape(pairing['name'])}</b></p>"
            f"{download}"
            f'<a class="button" href="{escape(pair_link)}">2. Åbn appen og forbind</a>'
            "<p class=\"hint\">Har du lige installeret appen, så kom tilbage hertil og tryk "
            "på knap 2.</p>"
        )
        return _page("Lommepenge", body)


def _page(title: str, body: str) -> web.Response:
    html = f"""<!doctype html>
<html lang="da"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{escape(title)}</title>
<style>
body {{ font-family: system-ui, sans-serif; margin: 0 auto; max-width: 28rem; padding: 1.5rem 1rem;
       background: #f4f7f6; color: #1b2b28; }}
h1 {{ font-size: 1.5rem; color: #00695c; }}
.button {{ display: block; margin: 1.25rem 0 .5rem; padding: 1rem; border-radius: .75rem;
           background: #00796b; color: #fff; text-align: center; text-decoration: none;
           font-size: 1.15rem; font-weight: 600; }}
.hint {{ color: #4a5d59; font-size: .95rem; }}
@media (prefers-color-scheme: dark) {{
  body {{ background: #101a18; color: #e3ece9; }} h1 {{ color: #4db6ac; }} .hint {{ color: #a3b5b1; }}
}}
</style></head>
<body><h1>{escape(title)}</h1>{body}</body></html>"""
    return web.Response(text=html, content_type="text/html", headers={"Cache-Control": "no-store"})


class QrCodeView(_LocalView):
    url = f"{API_PREFIX}/qr/{{token}}.svg"
    name = "api:lommepenge:qr"

    async def get(self, request: web.Request, token: str) -> web.Response:
        _require_local(request)
        runtime = _runtime(request)
        if runtime.pairing(token) is None:
            raise web.HTTPNotFound
        buffer = io.BytesIO()
        segno.make(install_url(request.app[KEY_HASS], token), error="m").save(
            buffer, kind="svg", scale=6, border=2, dark="#000", light="#fff"
        )
        return web.Response(
            body=buffer.getvalue(),
            content_type="image/svg+xml",
            headers={"Cache-Control": "no-store"},
        )


class DownloadView(_LocalView):
    url = f"{API_PREFIX}/download/{{token}}/{{filename}}"
    name = "api:lommepenge:download"

    async def get(self, request: web.Request, token: str, filename: str) -> web.StreamResponse:
        _require_local(request)
        runtime = _runtime(request)
        # Linket må gerne være brugt til parring - appen hentes ofte bagefter.
        if runtime.pairing(token) is None:
            raise web.HTTPNotFound(text="Linket er udløbet.")
        return await _stream_apk(request, runtime)


async def _stream_apk(request: web.Request, runtime: LommepengeRuntime) -> web.StreamResponse:
    release = runtime.releases.data if runtime.releases is not None else None
    if release is None:
        raise web.HTTPNotFound(text="Home Assistant har ikke hentet appen endnu.")
    try:
        return await runtime.releases.github.stream_apk(request, release)
    except GitHubError as err:
        _LOGGER.warning("Kunne ikke hente APK fra GitHub: %s", err)
        raise web.HTTPBadGateway(text="Kunne ikke hente appen fra GitHub.") from err


class PairView(_LocalView):
    url = f"{API_PREFIX}/pair"
    name = "api:lommepenge:pair"

    async def post(self, request: web.Request) -> web.Response:
        _require_local(request)
        runtime = _runtime(request)
        try:
            body = json.loads(await request.read() or b"{}")
            token = body["token"]
        except (ValueError, KeyError, TypeError):
            return _error(HTTPStatus.BAD_REQUEST, "Ugyldig forespørgsel.")
        try:
            device = await runtime.async_redeem_pairing(
                str(token),
                {
                    "appVersion": body.get("appVersion"),
                    "appVersionCode": body.get("appVersionCode"),
                },
            )
        except TooManyPairingAttempts as err:
            return _error(HTTPStatus.TOO_MANY_REQUESTS, str(err))
        except PairingError as err:
            return _error(HTTPStatus.GONE, str(err))
        return web.json_response(
            {
                "deviceId": device["id"],
                "deviceKey": device["key"],
                "role": device["role"],
                "childId": device["childId"],
                "deviceName": device["name"],
                "familyName": runtime.family_name,
            }
        )


# ---- Signerede endpoints -----------------------------------------------------


class StateView(_SignedView):
    url = f"{API_PREFIX}/state"
    name = "api:lommepenge:state"

    async def get(self, request: web.Request) -> web.Response:
        runtime, device = await self._device(request, b"")
        return web.json_response(runtime.state_for(device))


class ActionView(_SignedView):
    url = f"{API_PREFIX}/action"
    name = "api:lommepenge:action"

    async def post(self, request: web.Request) -> web.Response:
        body = await request.content.read(MAX_BODY + 1)
        if len(body) > MAX_BODY:
            return _error(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, "For stor forespørgsel.")
        runtime, device = await self._device(request, body)
        try:
            action = json.loads(body)
            if not isinstance(action, dict):
                raise ValueError
        except ValueError:
            return _error(HTTPStatus.BAD_REQUEST, "Ugyldig handling.")
        try:
            await runtime.async_apply(action, device=device)
        except ForbiddenError as err:
            return _error(HTTPStatus.FORBIDDEN, str(err))
        except FamilyError as err:
            return _error(HTTPStatus.BAD_REQUEST, str(err))
        return web.json_response(runtime.state_for(device))


class AppApkView(_LocalView):
    """Appen uden kode, til at taste i en browser på en enhed uden kamera.
    APK'en er alligevel offentlig på GitHub; den kan ikke forbinde til noget
    uden en parringskode."""

    url = f"{API_PREFIX}/app.apk"
    name = "api:lommepenge:app"

    async def get(self, request: web.Request) -> web.StreamResponse:
        _require_local(request)
        return await _stream_apk(request, _runtime(request))


class UpdateApkView(_SignedView):
    url = f"{API_PREFIX}/apk"
    name = "api:lommepenge:apk"

    async def get(self, request: web.Request) -> web.StreamResponse:
        runtime, _ = await self._device(request, b"")
        return await _stream_apk(request, runtime)
