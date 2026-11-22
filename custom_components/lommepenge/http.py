"""HTTP-API'et som appen taler med - kun på hjemmenettet.

Appen bruger ikke HA's egne brugere/tokens. Hver enhed har sin egen nøgle
(fra parringen) og signerer alle forespørgsler, så en barne-tablet aldrig
får adgang til resten af Home Assistant.

    GET  /api/lommepenge                        startside: appen og vejledning
    GET  /api/lommepenge/install/{token}        tilføj-enhed-side (kode, QR, app)
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
from homeassistant.util import dt as dt_util, network as network_util

from .const import API_PREFIX, DOMAIN, ROLE_CHILD, ROLE_PARENT, ROLE_SCREEN
from .family import FamilyError
from .releases import GitHubError
from .runtime import (
    AuthError,
    ForbiddenError,
    LommepengeRuntime,
    PairingError,
    TooManyPairingAttempts,
    pairing_code,
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
        HomePageView,
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


def home_url(hass: HomeAssistant) -> str:
    """Fast side med appen og vejledningen ("Besøg" på Lommepenge i HA)."""
    return f"{base_url(hass)}{API_PREFIX}"


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


def _release_version(runtime: LommepengeRuntime) -> str | None:
    release = runtime.releases.data if runtime.releases is not None else None
    return release.version if release is not None else None


def _download_button(runtime: LommepengeRuntime) -> str:
    version = _release_version(runtime)
    if version is None:
        return (
            '<p class="hint">Home Assistant har ikke kunnet hente appen fra GitHub '
            "endnu. Prøv igen om lidt.</p>"
        )
    return (
        f'<a class="button" href="{API_PREFIX}/app.apk" download="lommepenge-{escape(version)}.apk">'
        f"Hent appen (.apk, version {escape(version)})</a>"
        '<p class="hint">Har enheden ingen browser, så hent filen her på computeren og '
        "flyt den over, fx med et USB-kabel. Android spørger én gang, om appen må "
        "installeres.</p>"
    )


class HomePageView(_LocalView):
    """Fast side med appen og vejledningen - "Besøg" på Lommepenge i HA."""

    url = API_PREFIX
    name = "api:lommepenge:home"

    async def get(self, request: web.Request) -> web.Response:
        _require_local(request)
        runtime = _runtime(request)
        body = (
            f"<p>{escape(runtime.family_name)}</p>"
            f"{_download_button(runtime)}"
            "<h2>Tilføj en enhed</h2>"
            "<ol>"
            "<li>Installér appen på enheden.</li>"
            "<li>I Home Assistant: <b>Indstillinger → Enheder og tjenester → Lommepenge "
            "→ Tilføj enhed</b>. Vælg navn og rolle.</li>"
            "<li>Åbn appen på enheden, og tast koden, som Home Assistant viser - eller "
            "scan QR-koden, hvis enheden har kamera.</li>"
            "</ol>"
        )
        return _page("Lommepenge", body)


class InstallPageView(_LocalView):
    """Siden bag "Tilføj enhed": kode, QR-kode og appen. Kan åbnes både på
    den nye enhed (via QR-koden) og på computeren (via linket i HA)."""

    url = f"{API_PREFIX}/install/{{token}}"
    name = "api:lommepenge:install"

    async def get(self, request: web.Request, token: str) -> web.Response:
        _require_local(request)
        runtime = _runtime(request)
        hass = request.app[KEY_HASS]
        pairing = runtime.pairing(token)
        if pairing is None or pairing.get("used"):
            return _page(
                "Koden er brugt eller udløbet",
                "<p>Lav en ny i Home Assistant: <b>Lommepenge → Tilføj enhed</b> - eller "
                "<b>Omkonfigurér</b> på en enhed, der allerede findes.</p>"
                f"{_download_button(runtime)}",
            )
        code = pairing_code(token)
        expires = dt_util.as_local(dt_util.parse_datetime(pairing["expires"])).strftime("%H:%M")
        qr = io.BytesIO()
        segno.make(install_url(hass, code), error="m").save(
            qr, kind="svg", scale=6, border=2, dark="#000", light="#fff", xmldecl=False
        )
        android = "android" in request.headers.get("User-Agent", "").lower()
        open_app = ""
        if android:
            origin = f"{request.scheme}://{request.host}"
            pair_link = (
                f"intent://pair?url={quote(origin, safe='')}&token={quote(code, safe='')}"
                f"#Intent;scheme=lommepenge;package={APP_PACKAGE};end"
            )
            open_app = (
                f'<a class="button secondary" href="{escape(pair_link)}">'
                "Åbn appen og forbind</a>"
                '<p class="hint">Når appen er installeret på denne enhed.</p>'
            )
        body = (
            f"<p>{escape(runtime.family_name)} · "
            f"{escape(ROLE_LABELS.get(pairing['role'], ''))}</p>"
            '<p class="label">Kode</p>'
            f'<p class="code">{escape(code)}</p>'
            f'<p class="hint">Gælder én gang, indtil kl. {escape(expires)}. '
            f"Home Assistant: {escape(base_url(hass))}</p>"
            f"{open_app}"
            "<h2>Sådan gør du</h2>"
            "<ol>"
            "<li>Installér appen på enheden (knappen herunder).</li>"
            "<li>Åbn appen, vælg <b>Forbind med kode</b>, og tast koden. Appen finder "
            "selv Home Assistant.</li>"
            "<li>Har enheden kamera, kan den i stedet scanne QR-koden.</li>"
            "<li>Tryk <b>Send</b> i Home Assistant, når enheden er forbundet.</li>"
            "</ol>"
            f'<div class="qr">{qr.getvalue().decode()}</div>'
            f"{_download_button(runtime)}"
        )
        return _page(f"Tilføj {pairing['name']}", body)


def _page(title: str, body: str) -> web.Response:
    html = f"""<!doctype html>
<html lang="da"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{escape(title)}</title>
<style>
body {{ font-family: system-ui, sans-serif; margin: 0 auto; max-width: 34rem; padding: 1.5rem 1rem;
       background: #f4f7f6; color: #1b2b28; line-height: 1.45; }}
h1 {{ font-size: 1.6rem; color: #00695c; margin-bottom: .25rem; }}
h2 {{ font-size: 1.15rem; margin-top: 1.75rem; }}
.button {{ display: block; margin: 1.25rem 0 .5rem; padding: 1rem; border-radius: .75rem;
           background: #00796b; color: #fff; text-align: center; text-decoration: none;
           font-size: 1.15rem; font-weight: 600; }}
.button.secondary {{ background: #455a64; }}
.label {{ margin: 1.25rem 0 0; color: #4a5d59; text-transform: uppercase; font-size: .8rem;
          letter-spacing: .08em; }}
.code {{ margin: .25rem 0; font: 700 2.6rem/1.1 ui-monospace, monospace; letter-spacing: .18em; }}
.hint {{ color: #4a5d59; font-size: .95rem; }}
.qr svg {{ display: block; width: 14rem; height: auto; margin: 1rem 0; background: #fff;
           border-radius: .5rem; }}
@media (prefers-color-scheme: dark) {{
  body {{ background: #101a18; color: #e3ece9; }} h1 {{ color: #4db6ac; }}
  .hint, .label {{ color: #a3b5b1; }}
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
