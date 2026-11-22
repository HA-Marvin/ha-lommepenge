"""Lommepenge: the family's tasks and pocket money with Home Assistant as the server.

HA stores the family's data, calculates follow-up and restrictions, and is the
only place the app (family screen, parents' phones and children's tablets)
talks to. Devices are added under the integration with a code, and the app and
its updates are also fetched from HA.
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
    CONF_LANGUAGE,
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
from .i18n import async_entity_names
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


def action_error(runtime: LommepengeRuntime, err: FamilyError) -> HomeAssistantError:
    """A rejected action from HA itself, in the integration's language."""
    return HomeAssistantError(f"Lommepenge: {err.translate(runtime.language)}")


async def async_setup(hass: HomeAssistant, config: ConfigType) -> bool:
    """Registers the app's HTTP API and the integration's services (once)."""
    async_register_views(hass)

    def _runtime() -> LommepengeRuntime:
        runtime: LommepengeRuntime | None = hass.data.get(DOMAIN)
        if runtime is None or runtime.coordinator is None:
            raise ServiceValidationError(translation_domain=DOMAIN, translation_key="not_set_up")
        return runtime

    async def _run(action: str, payload: dict) -> None:
        runtime = _runtime()
        try:
            await runtime.coordinator.async_action(action, payload)
        except FamilyError as err:
            raise action_error(runtime, err) from err

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
    # An error here (e.g. no internet) must not stop the rest.
    await runtime.releases.async_refresh()

    entry.runtime_data = runtime
    hass.data[DOMAIN] = runtime
    # Entity names in the integration's language, not HA's.
    runtime.entity_names = await async_entity_names(hass, runtime.language)

    @callback
    def _sync_child_devices() -> None:
        _async_sync_child_devices(hass, entry)

    _sync_child_devices()
    entry.async_on_unload(runtime.coordinator.async_add_listener(_sync_child_devices))
    # New/deleted device, new GitHub token, PIN, language or currency: reload.
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
    """The integration is deleted: the family's data and device keys are deleted too."""
    await LommepengeRuntime(hass, entry).async_remove_storage()


async def async_migrate_entry(hass: HomeAssistant, entry: LommepengeConfigEntry) -> bool:
    if entry.version == 1:
        _LOGGER.error(
            "Lommepenge 0.2 uses Home Assistant as the server instead of the "
            "family screen. Delete the integration and add it again"
        )
        return False
    if entry.version == 2 and entry.minor_version < 2:
        # Installations from before the language choice were Danish-only, so
        # they keep Danish. New installations choose (English by default).
        hass.config_entries.async_update_entry(
            entry, data={**entry.data, CONF_LANGUAGE: "da"}, minor_version=2
        )
    return True


@callback
def _async_sync_child_devices(hass: HomeAssistant, entry: LommepengeConfigEntry) -> None:
    """The children's devices in HA follow the app: rename and delete."""
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
            continue  # the family itself or one of the app's devices
        if not device.identifiers & current:
            dev_reg.async_update_device(device.id, remove_config_entry_id=entry.entry_id)


async def async_remove_config_entry_device(
    hass: HomeAssistant, entry: LommepengeConfigEntry, device: dr.DeviceEntry
) -> bool:
    """A child's device can be deleted in HA when the child no longer exists in the app."""
    if not any(i[1].startswith(f"{entry.entry_id}_") for i in device.identifiers):
        return False
    return not any(
        child_device_identifier(entry.entry_id, child["id"]) in device.identifiers
        for child in entry.runtime_data.coordinator.children
    )
