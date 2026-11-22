"""App version per device: shows when a device is missing an update.

The installation itself happens on the device (Android requires a tap), so
the entity cannot install - it only shows the status. The app fetches the new
version from HA by itself and asks for permission to install it.
"""

from __future__ import annotations

from homeassistant.components.update import UpdateEntity
from homeassistant.config_entries import ConfigSubentry
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddConfigEntryEntitiesCallback

from .coordinator import LommepengeConfigEntry
from .entity import LommepengeAppDeviceEntity, async_setup_app_device_entities
from .runtime import LommepengeRuntime


async def async_setup_entry(
    hass: HomeAssistant,
    entry: LommepengeConfigEntry,
    async_add_entities: AddConfigEntryEntitiesCallback,
) -> None:
    runtime = entry.runtime_data
    async_setup_app_device_entities(
        entry, async_add_entities, lambda subentry: [AppUpdate(runtime, subentry)]
    )


class AppUpdate(LommepengeAppDeviceEntity, UpdateEntity):
    _attr_title = "Lommepenge app"

    def __init__(self, runtime: LommepengeRuntime, subentry: ConfigSubentry) -> None:
        super().__init__(runtime, subentry, "app")

    async def async_added_to_hass(self) -> None:
        await super().async_added_to_hass()
        if self.runtime.releases is not None:
            self.async_on_remove(
                self.runtime.releases.async_add_listener(self.async_write_ha_state)
            )

    @property
    def installed_version(self) -> str | None:
        device = self.device
        return device.get("appVersion") if device else None

    @property
    def latest_version(self) -> str | None:
        release = self.runtime.releases.data if self.runtime.releases is not None else None
        if release is None:
            # No release found: just show the installed version.
            return self.installed_version
        return release.version

    @property
    def release_url(self) -> str | None:
        release = self.runtime.releases.data if self.runtime.releases is not None else None
        return release.release_url if release is not None else None

    def version_is_newer(self, latest_version: str, installed_version: str) -> bool:
        def parts(version: str) -> tuple[int, ...]:
            try:
                return tuple(int(p) for p in version.split("+")[0].split("."))
            except ValueError:
                return (0,)

        return parts(latest_version) > parts(installed_version)
