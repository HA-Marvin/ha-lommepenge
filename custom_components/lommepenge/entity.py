"""Common base for Lommepenge entities.

Three kinds of devices in HA: the family (settings and approvals), each child
(balance and restriction) and each of the app's devices (version and contact).

Entity names are set in the integration's language (`runtime.entity_names`),
so they do not follow HA's language - the translation key is only the
fallback.
"""

from __future__ import annotations

from collections.abc import Callable
from typing import Any

from homeassistant.config_entries import ConfigSubentry
from homeassistant.core import callback
from homeassistant.helpers.device_registry import DeviceInfo
from homeassistant.helpers.entity import Entity
from homeassistant.helpers.entity_platform import AddConfigEntryEntitiesCallback
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from .const import CONF_DEVICE_ID, CONF_ROLE, DOMAIN, ROLE_CHILD, ROLE_PARENT, SUBENTRY_DEVICE
from .coordinator import LommepengeConfigEntry, LommepengeCoordinator
from .http import home_url
from .i18n import translate
from .runtime import LommepengeRuntime


def child_device_name(child: dict[str, Any]) -> str:
    return f"Lommepenge {child.get('name', '')}".strip()


def child_device_identifier(entry_id: str, child_id: str) -> tuple[str, str]:
    return (DOMAIN, f"{entry_id}_{child_id}")


def _set_name(entity: Entity, runtime: LommepengeRuntime, key: str) -> None:
    """The entity's name in the integration's language; HA's own translation
    (in HA's language) is only used if the name is missing."""
    entity._attr_translation_key = key
    if (name := runtime.entity_names.get(key)) is not None:
        entity._attr_name = name


class LommepengeEntity(CoordinatorEntity[LommepengeCoordinator]):
    """Entity on the family's device."""

    _attr_has_entity_name = True

    def __init__(self, coordinator: LommepengeCoordinator, key: str) -> None:
        super().__init__(coordinator)
        entry = coordinator.config_entry
        self._attr_unique_id = f"{entry.entry_id}_{key}"
        _set_name(self, coordinator.runtime, key)
        self._attr_device_info = DeviceInfo(
            identifiers={(DOMAIN, entry.entry_id)},
            name=entry.title,
            manufacturer="Lommepenge",
            model=translate("model_family", coordinator.runtime.language),
            # "Visit" on the device in HA: the app and instructions for new devices.
            configuration_url=home_url(coordinator.hass),
        )


class LommepengeChildEntity(CoordinatorEntity[LommepengeCoordinator]):
    """Entity for one child - every child gets its own device in HA."""

    _attr_has_entity_name = True

    def __init__(self, coordinator: LommepengeCoordinator, child_id: str, key: str) -> None:
        super().__init__(coordinator)
        self.child_id = child_id
        entry = coordinator.config_entry
        child = coordinator.child(child_id) or {}
        self._attr_unique_id = f"{entry.entry_id}_{child_id}_{key}"
        _set_name(self, coordinator.runtime, key)
        self._attr_device_info = DeviceInfo(
            identifiers={child_device_identifier(entry.entry_id, child_id)},
            name=child_device_name(child),
            manufacturer="Lommepenge",
            model=translate("model_child", coordinator.runtime.language),
            via_device=(DOMAIN, entry.entry_id),
        )

    @property
    def child(self) -> dict[str, Any] | None:
        return self.coordinator.child(self.child_id)

    @property
    def available(self) -> bool:
        # A child deleted in the app becomes unavailable instead of showing
        # stale values.
        return super().available and self.child is not None


def async_setup_child_entities(
    coordinator: LommepengeCoordinator,
    async_add_entities: AddConfigEntryEntitiesCallback,
    factory: Callable[[str], list[LommepengeChildEntity]],
) -> None:
    """Creates entities per child - also for children added later."""
    known: set[str] = set()

    @callback
    def _add_new_children() -> None:
        new_ids = [c["id"] for c in coordinator.children if c["id"] not in known]
        if not new_ids:
            return
        known.update(new_ids)
        async_add_entities([entity for child_id in new_ids for entity in factory(child_id)])

    _add_new_children()
    coordinator.config_entry.async_on_unload(coordinator.async_add_listener(_add_new_children))


_MODELS = {ROLE_CHILD: "role_child", ROLE_PARENT: "role_parent"}


class LommepengeAppDeviceEntity(Entity):
    """Entity for one of the app's devices (a subentry under the integration)."""

    _attr_has_entity_name = True
    _attr_should_poll = False

    def __init__(self, runtime: LommepengeRuntime, subentry: ConfigSubentry, key: str) -> None:
        self.runtime = runtime
        self.device_id: str = subentry.data[CONF_DEVICE_ID]
        self._attr_unique_id = f"{self.device_id}_{key}"
        _set_name(self, runtime, key)
        self._attr_device_info = DeviceInfo(
            identifiers={(DOMAIN, self.device_id)},
            name=subentry.title,
            manufacturer="Lommepenge",
            model=translate(
                _MODELS.get(subentry.data[CONF_ROLE], "role_screen"), runtime.language
            ),
            via_device=(DOMAIN, runtime.entry.entry_id),
        )

    @property
    def device(self) -> dict[str, Any] | None:
        """The device's data, or `None` if it is not paired yet."""
        return self.runtime.devices.get(self.device_id)

    async def async_added_to_hass(self) -> None:
        self.async_on_remove(self.runtime.async_add_listener(self.async_write_ha_state))


def async_setup_app_device_entities(
    entry: LommepengeConfigEntry,
    async_add_entities: AddConfigEntryEntitiesCallback,
    factory: Callable[[ConfigSubentry], list[Entity]],
) -> None:
    """One group of entities per added device, attached to its subentry."""
    for subentry in entry.subentries.values():
        if subentry.subentry_type == SUBENTRY_DEVICE:
            async_add_entities(factory(subentry), config_subentry_id=subentry.subentry_id)
