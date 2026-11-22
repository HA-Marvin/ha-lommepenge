"""Lommepenge: familiens opgaver og lommepenge med Home Assistant som server.

HA gemmer familiens data, regner opfølgning og spærring, og er det eneste
sted appen (fælles skærm, forældres telefoner og børnenes tablets) taler
med. Enheder tilføjes under integrationen med en QR-kode, og appen og dens
opdateringer hentes også fra HA.
"""

from __future__ import annotations

import logging

import voluptuous as vol

from homeassistant.const import Platform
from homeassistant.core import HomeAssistant, ServiceCall, callback
from homeassistant.exceptions import HomeAssistantError, ServiceValidationError
from homeassistant.helpers import config_validation as cv, device_registry as dr
from homeassistant.helpers.typing import ConfigType

from .const import (
    ATTR_CHILD_ID,
    ATTR_COMPLETION_ID,
    CONF_GITHUB_REPO,
    CONF_GITHUB_TOKEN,
    DEFAULT_GITHUB_REPO,
    DOMAIN,
    SERVICE_APPROVE,
    SERVICE_REJECT,
    SERVICE_SUSPEND_RESTRICTION,
)
from .coordinator import LommepengeConfigEntry, LommepengeCoordinator
from .entity import child_device_identifier, child_device_name
from .family import FamilyError
from .http import async_register_views
from .releases import ReleaseCoordinator
from .runtime import LommepengeRuntime

_LOGGER = logging.getLogger(__name__)

PLATFORMS = [
    Platform.BINARY_SENSOR,
    Platform.BUTTON,
    Platform.NUMBER,
    Platform.SENSOR,
    Platform.TIME,
    Platform.UPDATE,
]

CONFIG_SCHEMA = cv.config_entry_only_config_schema(DOMAIN)


async def async_setup(hass: HomeAssistant, config: ConfigType) -> bool:
    """Registrerer appens HTTP-API og integrationens services (én gang)."""
    async_register_views(hass)

    def _coordinator() -> LommepengeCoordinator:
        runtime: LommepengeRuntime | None = hass.data.get(DOMAIN)
        if runtime is None or runtime.coordinator is None:
            raise ServiceValidationError("Lommepenge er ikke sat op.")
        return runtime.coordinator

    async def _run(action: str, payload: dict) -> None:
        try:
            await _coordinator().async_action(action, payload)
        except FamilyError as err:
            raise HomeAssistantError(f"Lommepenge: {err}") from err

    async def approve(call: ServiceCall) -> None:
        await _run("approve_completion", {"completionId": call.data[ATTR_COMPLETION_ID]})

    async def reject(call: ServiceCall) -> None:
        await _run("reject_completion", {"completionId": call.data[ATTR_COMPLETION_ID]})

    async def suspend_restriction(call: ServiceCall) -> None:
        await _run("suspend_restriction", {"childId": call.data[ATTR_CHILD_ID]})

    completion_schema = vol.Schema({vol.Required(ATTR_COMPLETION_ID): cv.string})
    child_schema = vol.Schema({vol.Required(ATTR_CHILD_ID): cv.string})
    hass.services.async_register(DOMAIN, SERVICE_APPROVE, approve, completion_schema)
    hass.services.async_register(DOMAIN, SERVICE_REJECT, reject, completion_schema)
    hass.services.async_register(
        DOMAIN, SERVICE_SUSPEND_RESTRICTION, suspend_restriction, child_schema
    )
    return True


async def async_setup_entry(hass: HomeAssistant, entry: LommepengeConfigEntry) -> bool:
    runtime = LommepengeRuntime(hass, entry)
    await runtime.async_load()
    runtime.async_sync_subentries()

    runtime.coordinator = LommepengeCoordinator(hass, entry, runtime)
    await runtime.coordinator.async_config_entry_first_refresh()

    runtime.releases = ReleaseCoordinator(
        hass,
        entry,
        entry.options.get(CONF_GITHUB_REPO, DEFAULT_GITHUB_REPO),
        entry.options.get(CONF_GITHUB_TOKEN) or None,
    )
    # En fejl her (fx ingen internet) må ikke stoppe resten.
    await runtime.releases.async_refresh()

    entry.runtime_data = runtime
    hass.data[DOMAIN] = runtime

    @callback
    def _sync_child_devices() -> None:
        _async_sync_child_devices(hass, entry)

    _sync_child_devices()
    entry.async_on_unload(runtime.coordinator.async_add_listener(_sync_child_devices))
    # Ny/slettet enhed, ny GitHub-nøgle eller PIN: genindlæs.
    entry.async_on_unload(entry.add_update_listener(_async_reload))

    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)
    return True


async def _async_reload(hass: HomeAssistant, entry: LommepengeConfigEntry) -> None:
    hass.config_entries.async_schedule_reload(entry.entry_id)


async def async_unload_entry(hass: HomeAssistant, entry: LommepengeConfigEntry) -> bool:
    unloaded = await hass.config_entries.async_unload_platforms(entry, PLATFORMS)
    if unloaded:
        await entry.runtime_data.async_save_now()
        hass.data.pop(DOMAIN, None)
    return unloaded


async def async_remove_entry(hass: HomeAssistant, entry: LommepengeConfigEntry) -> None:
    """Integrationen slettes: familiens data og enhedsnøgler slettes også."""
    await LommepengeRuntime(hass, entry).async_remove_storage()


async def async_migrate_entry(hass: HomeAssistant, entry: LommepengeConfigEntry) -> bool:
    if entry.version == 1:
        _LOGGER.error(
            "Lommepenge 0.2 bruger Home Assistant som server i stedet for "
            "køleskabsskærmen. Slet integrationen og tilføj den igen"
        )
        return False
    return True


@callback
def _async_sync_child_devices(hass: HomeAssistant, entry: LommepengeConfigEntry) -> None:
    """Børnenes enheder i HA følger appen: omdøb og slet."""
    coordinator = entry.runtime_data.coordinator
    if not coordinator.last_update_success or coordinator.data is None:
        return
    dev_reg = dr.async_get(hass)
    current: set[tuple[str, str]] = set()
    for child in coordinator.children:
        identifier = child_device_identifier(entry.entry_id, child["id"])
        current.add(identifier)
        device = dev_reg.async_get_device(identifiers={identifier})
        name = child_device_name(child)
        if device is not None and device.name != name:
            dev_reg.async_update_device(device.id, name=name)

    for device in dr.async_entries_for_config_entry(dev_reg, entry.entry_id):
        identifier = next(iter(device.identifiers), None)
        if identifier is None or not identifier[1].startswith(f"{entry.entry_id}_"):
            continue  # familien selv eller en af appens enheder
        if not device.identifiers & current:
            dev_reg.async_update_device(device.id, remove_config_entry_id=entry.entry_id)


async def async_remove_config_entry_device(
    hass: HomeAssistant, entry: LommepengeConfigEntry, device: dr.DeviceEntry
) -> bool:
    """Et barns enhed kan slettes i HA, når barnet ikke findes i appen."""
    if not any(i[1].startswith(f"{entry.entry_id}_") for i in device.identifiers):
        return False
    return not any(
        child_device_identifier(entry.entry_id, child["id"]) in device.identifiers
        for child in entry.runtime_data.coordinator.children
    )
