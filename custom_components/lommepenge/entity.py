"""Fælles basis for Lommepenge-entiteter.

Tre slags enheder i HA: familien (indstillinger og godkendelser), hvert
barn (saldo og spærring) og hver af appens enheder (version og kontakt).
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
from .runtime import LommepengeRuntime


def child_device_name(child: dict[str, Any]) -> str:
    return f"Lommepenge {child.get('name', '')}".strip()


def child_device_identifier(entry_id: str, child_id: str) -> tuple[str, str]:
    return (DOMAIN, f"{entry_id}_{child_id}")


class LommepengeEntity(CoordinatorEntity[LommepengeCoordinator]):
    """Entitet på familiens enhed."""

    _attr_has_entity_name = True

    def __init__(self, coordinator: LommepengeCoordinator, key: str) -> None:
        super().__init__(coordinator)
        entry = coordinator.config_entry
        self._attr_unique_id = f"{entry.entry_id}_{key}"
        self._attr_translation_key = key
        self._attr_device_info = DeviceInfo(
            identifiers={(DOMAIN, entry.entry_id)},
            name=entry.title,
            manufacturer="Lommepenge",
            model="Familie",
        )


class LommepengeChildEntity(CoordinatorEntity[LommepengeCoordinator]):
    """Entitet for ét barn - hvert barn får sin egen enhed i HA."""

    _attr_has_entity_name = True

    def __init__(self, coordinator: LommepengeCoordinator, child_id: str, key: str) -> None:
        super().__init__(coordinator)
        self.child_id = child_id
        entry = coordinator.config_entry
        child = coordinator.child(child_id) or {}
        self._attr_unique_id = f"{entry.entry_id}_{child_id}_{key}"
        self._attr_translation_key = key
        self._attr_device_info = DeviceInfo(
            identifiers={child_device_identifier(entry.entry_id, child_id)},
            name=child_device_name(child),
            manufacturer="Lommepenge",
            model="Barn",
            via_device=(DOMAIN, entry.entry_id),
        )

    @property
    def child(self) -> dict[str, Any] | None:
        return self.coordinator.child(self.child_id)

    @property
    def available(self) -> bool:
        # Et barn der er slettet i appen bliver utilgængeligt i stedet for
        # at vise forældede værdier.
        return super().available and self.child is not None


def async_setup_child_entities(
    coordinator: LommepengeCoordinator,
    async_add_entities: AddConfigEntryEntitiesCallback,
    factory: Callable[[str], list[LommepengeChildEntity]],
) -> None:
    """Opretter entiteter pr. barn - også for børn der tilføjes senere."""
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


_MODELS = {ROLE_CHILD: "Barnets tablet", ROLE_PARENT: "Forælder"}


class LommepengeAppDeviceEntity(Entity):
    """Entitet for én af appens enheder (en subentry under integrationen)."""

    _attr_has_entity_name = True
    _attr_should_poll = False

    def __init__(self, runtime: LommepengeRuntime, subentry: ConfigSubentry, key: str) -> None:
        self.runtime = runtime
        self.device_id: str = subentry.data[CONF_DEVICE_ID]
        self._attr_unique_id = f"{self.device_id}_{key}"
        self._attr_translation_key = key
        self._attr_device_info = DeviceInfo(
            identifiers={(DOMAIN, self.device_id)},
            name=subentry.title,
            manufacturer="Lommepenge",
            model=_MODELS.get(subentry.data[CONF_ROLE], "Fælles skærm"),
            via_device=(DOMAIN, runtime.entry.entry_id),
        )

    @property
    def device(self) -> dict[str, Any] | None:
        """Enhedens data, eller `None` hvis den ikke er parret endnu."""
        return self.runtime.devices.get(self.device_id)

    async def async_added_to_hass(self) -> None:
        self.async_on_remove(self.runtime.async_add_listener(self.async_write_ha_state))


def async_setup_app_device_entities(
    entry: LommepengeConfigEntry,
    async_add_entities: AddConfigEntryEntitiesCallback,
    factory: Callable[[ConfigSubentry], list[Entity]],
) -> None:
    """Én gruppe entiteter pr. tilføjet enhed, knyttet til dens subentry."""
    for subentry in entry.subentries.values():
        if subentry.subentry_type == SUBENTRY_DEVICE:
            async_add_entities(factory(subentry), config_subentry_id=subentry.subentry_id)
