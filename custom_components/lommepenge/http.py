"""The HTTP API the app talks to - home network only.

The app does not use HA's own users/tokens. Every device has its own key
(from pairing) and signs all requests, so a child's tablet never gets access
to the rest of Home Assistant.

    GET  /api/lommepenge                        start page: the app and instructions
    GET  /api/lommepenge/install/{token}        add-device page (code, QR, app)
    GET  /api/lommepenge/qr/{token}.svg         the QR code for "Add device"
    GET  /api/lommepenge/download/{token}/...   APK for the first installation
    GET  /api/lommepenge/app.apk                APK without a code (devices without camera)
    POST /api/lommepenge/pair                   pairing code -> device key
    GET  /api/lommepenge/state                  the family's data   (signed)
    POST /api/lommepenge/action                 perform an action   (signed)
    GET  /api/lommepenge/apk                    APK for an update   (signed)

Error messages for the app follow the language chosen in the app (sent in
`X-Lommepenge-Language`); everything else follows the language chosen for the
integration. Neither the browser's nor HA's language is ever used.
"""

from __future__ import annotations

from html import escape
from http import HTTPStatus
from ipaddress import ip_address
import io
import json
import logging
import time
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
from .i18n import normalize_language, translate
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
    ROLE_SCREEN: "role_screen",
    ROLE_PARENT: "role_parent",
    ROLE_CHILD: "role_child",
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
    """HA's address on the home network. Uses the local IP, so a new device
    can reach it without knowing `homeassistant.local`."""
    api = hass.config.api
    if api is not None and api.local_ip and api.local_ip != "127.0.0.1":
        scheme = "https" if api.use_ssl else "http"
        return f"{scheme}://{api.local_ip}:{api.port}"
    try:
        return get_url(hass, allow_external=False, allow_cloud=False, prefer_external=False)
    except NoURLAvailableError:
        return ""


def install_url(hass: HomeAssistant, token: str) -> str:
    """The link in the QR code (and for typing into a browser)."""
    return f"{base_url(hass)}{API_PREFIX}/install/{token}"


def home_url(hass: HomeAssistant) -> str:
    """Fixed page with the app and instructions ("Visit" on Lommepenge in HA)."""
    return f"{base_url(hass)}{API_PREFIX}"


def app_url(hass: HomeAssistant) -> str:
    """Fixed link to the app - requires no code."""
    return f"{base_url(hass)}{API_PREFIX}/app.apk"


LANGUAGE_HEADER = "X-Lommepenge-Language"


def _language(request: web.Request, runtime: LommepengeRuntime | None = None) -> str | None:
    """The language chosen in the app, else the integration's. Deliberately not
    `Accept-Language`, which browsers fill in from the device's language."""
    return normalize_language(request.headers.get(LANGUAGE_HEADER)) or (
        runtime.language if runtime is not None else None
    )


def _runtime(request: web.Request) -> LommepengeRuntime:
    runtime = request.app[KEY_HASS].data.get(DOMAIN)
    if runtime is None:
        raise web.HTTPServiceUnavailable(text=translate("not_set_up", _language(request)))
    return runtime


def _require_local(request: web.Request) -> None:
    """Home network only - never via HA's external address or the cloud."""
    hass = request.app[KEY_HASS]
    try:
        local = not is_cloud_connection(hass) and network_util.is_local(
            ip_address(request.remote or "")
        )
    except ValueError:
        local = False
    if not local:
        raise web.HTTPForbidden(text=translate("local_only", _language(request)))


def _error(status: HTTPStatus, message: str) -> web.Response:
    return web.json_response({"error": message}, status=status)


class _LocalView(HomeAssistantView):
    """The app's endpoints: no HA login, but always local only."""

    requires_auth = False
    cors_allowed = False


class _SignedView(_LocalView):
    """Endpoints that require a paired device's signature."""

    async def _device(self, request: web.Request, body: bytes) -> tuple[LommepengeRuntime, dict[str, Any]]:
        _require_local(request)
        runtime = _runtime(request)
        headers = request.headers  # case-insensitive lookups
        try:
            device = runtime.verify(headers, request.method, request.path, body)
        except AuthError as err:
            # `code` tells the app what to do: only an unknown/revoked device
            # or a wrong key means "connect again". On `clock_skew` the app
            # corrects its clock with `serverTime` (Unix time) and retries -
            # a wrong clock must never require a new pairing.
            raise web.HTTPUnauthorized(
                text=json.dumps(
                    {
                        "error": err.translate(_language(request, runtime)),
                        "code": err.key,
                        "serverTime": int(time.time()),
                    }
                ),
                content_type="application/json",
            ) from err
        runtime.async_device_seen(device, headers)
        return runtime, device


# ---- Installation and pairing ----------------------------------------------------


def _release_version(runtime: LommepengeRuntime) -> str | None:
    release = runtime.releases.data if runtime.releases is not None else None
    return release.version if release is not None else None


def _download_button(runtime: LommepengeRuntime) -> str:
    language = runtime.language
    version = _release_version(runtime)
    if version is None:
        return f'<p class="hint">{escape(translate("page_no_app", language))}</p>'
    return (
        f'<a class="button" href="{API_PREFIX}/app.apk" download="lommepenge-{escape(version)}.apk">'
        f"{escape(translate('page_download', language, version=version))}</a>"
        f'<p class="hint">{escape(translate("page_download_hint", language))}</p>'
    )


class HomePageView(_LocalView):
    """Fixed page with the app and instructions - "Visit" on Lommepenge in HA."""

    url = API_PREFIX
    name = "api:lommepenge:home"

    async def get(self, request: web.Request) -> web.Response:
        _require_local(request)
        runtime = _runtime(request)
        language = runtime.language
        # The step texts contain trusted markup (<b>) from i18n.py.
        body = (
            f"<p>{escape(runtime.family_name)}</p>"
            f"{_download_button(runtime)}"
            f"<h2>{escape(translate('page_add_device', language))}</h2>"
            "<ol>"
            f"<li>{escape(translate('page_home_step_install', language))}</li>"
            f"<li>{translate('page_home_step_add', language)}</li>"
            f"<li>{escape(translate('page_home_step_code', language))}</li>"
            "</ol>"
        )
        return _page("Lommepenge", body, language)


class InstallPageView(_LocalView):
    """The page behind "Add device": code, QR code and the app. Can be opened
    both on the new device (via the QR code) and on the computer (via the link
    in HA)."""

    url = f"{API_PREFIX}/install/{{token}}"
    name = "api:lommepenge:install"

    async def get(self, request: web.Request, token: str) -> web.Response:
        _require_local(request)
        runtime = _runtime(request)
        language = runtime.language
        hass = request.app[KEY_HASS]
        pairing = runtime.pairing(token)
        if pairing is None or pairing.get("used"):
            return _page(
                translate("page_code_used_title", language),
                f"<p>{translate('page_code_used_body', language)}</p>"
                f"{_download_button(runtime)}",
                language,
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
                f"{escape(translate('page_open_app', language))}</a>"
                f'<p class="hint">{escape(translate("page_open_app_hint", language))}</p>'
            )
        role = ROLE_LABELS.get(pairing["role"])
        body = (
            f"<p>{escape(runtime.family_name)} · "
            f"{escape(translate(role, language) if role else '')}</p>"
            f'<p class="label">{escape(translate("page_code_label", language))}</p>'
            f'<p class="code">{escape(code)}</p>'
            f'<p class="hint">{escape(translate("page_code_valid", language, expires=expires))} '
            f"Home Assistant: {escape(base_url(hass))}</p>"
            f"{open_app}"
            f"<h2>{escape(translate('page_how_to', language))}</h2>"
            "<ol>"
            f"<li>{escape(translate('page_step_install', language))}</li>"
            f"<li>{translate('page_step_code', language)}</li>"
            f"<li>{escape(translate('page_step_qr', language))}</li>"
            f"<li>{escape(translate('page_step_confirm', language))}</li>"
            "</ol>"
            f'<div class="qr">{qr.getvalue().decode()}</div>'
            f"{_download_button(runtime)}"
        )
        return _page(translate("page_add_title", language, name=pairing["name"]), body, language)


def _page(title: str, body: str, language: str) -> web.Response:
    html = f"""<!doctype html>
<html lang="{escape(language)}"><head><meta charset="utf-8">
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
        # The code may already have been used for pairing - the app is often
        # downloaded afterwards.
        if runtime.pairing(token) is None:
            raise web.HTTPNotFound(text=translate("link_expired", _language(request, runtime)))
        return await _stream_apk(request, runtime)


async def _stream_apk(request: web.Request, runtime: LommepengeRuntime) -> web.StreamResponse:
    language = _language(request, runtime)
    release = runtime.releases.data if runtime.releases is not None else None
    if release is None:
        raise web.HTTPNotFound(text=translate("app_not_fetched", language))
    try:
        return await runtime.releases.github.stream_apk(request, release)
    except GitHubError as err:
        _LOGGER.warning("Could not fetch the APK from GitHub: %s", err)
        raise web.HTTPBadGateway(text=translate("app_fetch_failed", language)) from err


class PairView(_LocalView):
    url = f"{API_PREFIX}/pair"
    name = "api:lommepenge:pair"

    async def post(self, request: web.Request) -> web.Response:
        _require_local(request)
        runtime = _runtime(request)
        language = _language(request, runtime)
        try:
            body = json.loads(await request.read() or b"{}")
            token = body["token"]
        except (ValueError, KeyError, TypeError):
            return _error(HTTPStatus.BAD_REQUEST, translate("invalid_request", language))
        try:
            device = await runtime.async_redeem_pairing(
                str(token),
                {
                    "appVersion": body.get("appVersion"),
                    "appVersionCode": body.get("appVersionCode"),
                },
            )
        except TooManyPairingAttempts as err:
            return _error(HTTPStatus.TOO_MANY_REQUESTS, err.translate(language))
        except PairingError as err:
            return _error(HTTPStatus.GONE, err.translate(language))
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


# ---- Signed endpoints -----------------------------------------------------------


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
            return _error(
                HTTPStatus.REQUEST_ENTITY_TOO_LARGE,
                translate("request_too_large", _language(request)),
            )
        runtime, device = await self._device(request, body)
        language = _language(request, runtime)
        try:
            action = json.loads(body)
            if not isinstance(action, dict):
                raise ValueError
        except ValueError:
            return _error(HTTPStatus.BAD_REQUEST, translate("invalid_action", language))
        try:
            await runtime.async_apply(action, device=device)
        except ForbiddenError as err:
            return _error(HTTPStatus.FORBIDDEN, err.translate(language))
        except FamilyError as err:
            return _error(HTTPStatus.BAD_REQUEST, err.translate(language))
        return web.json_response(runtime.state_for(device))


class AppApkView(_LocalView):
    """The app without a code, for typing into a browser on a device without a
    camera. The APK is public on GitHub anyway; it cannot connect to anything
    without a pairing code."""

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
