"""Lommepenge: familiens opgaver og lommepenge fra køleskabsskærmen i HA.

Integrationen taler med lommepenge-appens indbyggede server på
køleskabsskærmen (kun LAN). Den henter overblikket jævnligt, modtager
hændelser med det samme via en webhook, og stiller entiteter, services og
hændelsen `lommepenge_event` til rådighed for automationer/blueprints.
"""

from __future__ import annotations

import logging
from typing import Any

from aiohttp import web
import voluptuous as vol

from homeassistant.components import webhook
from homeassistant.config_entries import ConfigEntryState
from homeassistant.const import CONF_HOST, CONF_PORT, Platform
from homeassistant.core import HomeAssistant, ServiceCall, callback
from homeassistant.exceptions import HomeAssistantError, ServiceValidationError
from homeassistant.helpers import config_validation as cv
from homeassistant.helpers.aiohttp_client import async_get_clientsession
from homeassistant.helpers.network import NoURLAvailableError, get_url
from homeassistant.helpers.typing import ConfigType

from .api import LommepengeApi, LommepengeError
from .const import (
    ATTR_CHILD_ID,
    ATTR_COMPLETION_ID,
    ATTR_CONFIG_ENTRY_ID,
    CONF_TOKEN,
    CONF_WEBHOOK_ID,
    DOMAIN,
    EVENT_LOMMEPENGE,
    SERVICE_APPROVE,
    SERVICE_REJECT,
    SERVICE_SUSPEND_RESTRICTION,
)
from .coordinator import LommepengeConfigEntry, LommepengeCoordinator

_LOGGER = logging.getLogger(__name__)

PLATFORMS = [
    Platform.BINARY_SENSOR,
    Platform.BUTTON,
    Platform.NUMBER,
    Platform.SENSOR,
    Platform.TIME,
]

CONFIG_SCHEMA = cv.config_entry_only_config_schema(DOMAIN)

_COMPLETION_SCHEMA = vol.Schema(
    {
        vol.Required(ATTR_COMPLETION_ID): cv.string,
        vol.Optional(ATTR_CONFIG_ENTRY_ID): cv.string,
    }
)
_CHILD_SCHEMA = vol.Schema(
    {
        vol.Required(ATTR_CHILD_ID): cv.string,
        vol.Optional(ATTR_CONFIG_ENTRY_ID): cv.string,
    }
)


async def async_setup(hass: HomeAssistant, config: ConfigType) -> bool:
    """Registrerer integrationens services (én gang, uanset antal skærme)."""

    def _find_coordinator(call: ServiceCall, match) -> LommepengeCoordinator:
        entries: list[LommepengeConfigEntry] = _loaded_entries(hass)
        if entry_id := call.data.get(ATTR_CONFIG_ENTRY_ID):
            entries = [e for e in entries if e.entry_id == entry_id]
        if not entries:
            raise ServiceValidationError("Ingen køleskabsskærm er sat op.")
        for entry in entries:
            if match(entry.runtime_data):
                return entry.runtime_data
        return entries[0].runtime_data

    async def _run(coordinator: LommepengeCoordinator, action: str, payload: dict) -> None:
        try:
            await coordinator.async_action(action, payload)
        except LommepengeError as err:
            raise HomeAssistantError(f"Lommepenge: {err}") from err

    async def approve(call: ServiceCall) -> None:
        completion_id = call.data[ATTR_COMPLETION_ID]
        coordinator = _find_coordinator(
            call,
            lambda c: any(p.get("completionId") == completion_id for p in c.pending),
        )
        await _run(coordinator, "approve_completion", {"completionId": completion_id})

    async def reject(call: ServiceCall) -> None:
        completion_id = call.data[ATTR_COMPLETION_ID]
        coordinator = _find_coordinator(
            call,
            lambda c: any(p.get("completionId") == completion_id for p in c.pending),
        )
        await _run(coordinator, "reject_completion", {"completionId": completion_id})

    async def suspend_restriction(call: ServiceCall) -> None:
        child_id = call.data[ATTR_CHILD_ID]
        coordinator = _find_coordinator(call, lambda c: c.child(child_id) is not None)
        await _run(coordinator, "suspend_restriction", {"childId": child_id})

    hass.services.async_register(DOMAIN, SERVICE_APPROVE, approve, _COMPLETION_SCHEMA)
    hass.services.async_register(DOMAIN, SERVICE_REJECT, reject, _COMPLETION_SCHEMA)
    hass.services.async_register(
        DOMAIN, SERVICE_SUSPEND_RESTRICTION, suspend_restriction, _CHILD_SCHEMA
    )
    return True


async def async_setup_entry(hass: HomeAssistant, entry: LommepengeConfigEntry) -> bool:
    """Sætter én køleskabsskærm op."""
    api = LommepengeApi(
        async_get_clientsession(hass),
        entry.data[CONF_HOST],
        entry.data[CONF_PORT],
        entry.data[CONF_TOKEN],
    )
    coordinator = LommepengeCoordinator(hass, entry, api)
    await coordinator.async_config_entry_first_refresh()
    entry.runtime_data = coordinator

    webhook_id = entry.data[CONF_WEBHOOK_ID]

    @callback
    def _unregister_webhook() -> None:
        webhook.async_unregister(hass, webhook_id)

    webhook.async_register(
        hass,
        DOMAIN,
        f"Lommepenge ({entry.title})",
        webhook_id,
        _handle_webhook,
        local_only=True,
        allowed_methods=["POST"],
    )
    entry.async_on_unload(_unregister_webhook)

    await _async_send_webhook_url(hass, entry, api, webhook_id)

    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)
    return True


async def async_unload_entry(hass: HomeAssistant, entry: LommepengeConfigEntry) -> bool:
    return await hass.config_entries.async_unload_platforms(entry, PLATFORMS)


async def _async_send_webhook_url(
    hass: HomeAssistant,
    entry: LommepengeConfigEntry,
    api: LommepengeApi,
    webhook_id: str,
) -> None:
    """Fortæller skærmen hvor den skal sende hændelser hen.

    Fejler det (fx ingen intern URL konfigureret), virker integrationen
    stadig - bare kun via polling (op til et minuts forsinkelse).
    """
    try:
        base = get_url(hass, allow_internal=True, allow_external=False, prefer_external=False)
    except NoURLAvailableError:
        _LOGGER.warning(
            "Lommepenge: HA har ingen intern URL; hændelser hentes kun ved polling. "
            "Sæt en intern URL under Indstillinger > System > Netværk"
        )
        return
    try:
        await api.register_webhook(f"{base}{webhook.async_generate_path(webhook_id)}")
    except LommepengeError as err:
        _LOGGER.warning("Lommepenge: kunne ikke registrere webhook: %s", err)


def _loaded_entries(hass: HomeAssistant) -> list[LommepengeConfigEntry]:
    return [
        entry
        for entry in hass.config_entries.async_entries(DOMAIN)
        if entry.state is ConfigEntryState.LOADED
    ]


async def _handle_webhook(
    hass: HomeAssistant, webhook_id: str, request: web.Request
) -> web.Response:
    """Hændelse fra køleskabsskærmen: genudsend på event-bussen og opdatér."""
    try:
        data: dict[str, Any] = await request.json()
    except ValueError:
        return web.Response(status=400)
    if not isinstance(data, dict) or "event" not in data:
        return web.Response(status=400)

    entry = next(
        (e for e in _loaded_entries(hass) if e.data.get(CONF_WEBHOOK_ID) == webhook_id),
        None,
    )
    if entry is None:
        return web.Response(status=404)

    hass.bus.async_fire(EVENT_LOMMEPENGE, {**data, "config_entry_id": entry.entry_id})
    await entry.runtime_data.async_request_refresh()
    return web.Response(status=200)
