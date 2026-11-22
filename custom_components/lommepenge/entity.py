"""Fælles basis for Lommepenge-entiteter."""

from __future__ import annotations

from collections.abc import Callable
from typing import Any

from homeassistant.core import callback
from homeassistant.helpers.device_registry import DeviceInfo
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from .const import DOMAIN
from .coordinator import LommepengeCoordinator


class LommepengeEntity(CoordinatorEntity[LommepengeCoordinator]):
    """Entitet på familiens enhed (køleskabsskærmen)."""

    _attr_has_entity_name = True

    def __init__(self, coordinator: LommepengeCoordinator, key: str) -> None:
        super().__init__(coordinator)
        entry = coordinator.config_entry
        self._attr_unique_id = f"{entry.unique_id}_{key}"
        self._attr_translation_key = key
        self._attr_device_info = DeviceInfo(
            identifiers={(DOMAIN, entry.unique_id or entry.entry_id)},
            name=entry.title,
            manufacturer="Lommepenge",
            model="Køleskabsskærm",
        )


def child_device_name(child: dict[str, Any]) -> str:
    return f"Lommepenge {child.get('name', '')}".strip()


def child_device_identifier(screen: str, child_id: str) -> tuple[str, str]:
    return (DOMAIN, f"{screen}_{child_id}")


class LommepengeChildEntity(CoordinatorEntity[LommepengeCoordinator]):
    """Entitet for ét barn - hvert barn får sin egen enhed i HA."""

    _attr_has_entity_name = True

    def __init__(self, coordinator: LommepengeCoordinator, child_id: str, key: str) -> None:
        super().__init__(coordinator)
        self.child_id = child_id
        entry = coordinator.config_entry
        screen = entry.unique_id or entry.entry_id
        child = coordinator.child(child_id) or {}
        self._attr_unique_id = f"{screen}_{child_id}_{key}"
        self._attr_translation_key = key
        self._attr_device_info = DeviceInfo(
            identifiers={child_device_identifier(screen, child_id)},
            name=child_device_name(child),
            manufacturer="Lommepenge",
            model="Barn",
            via_device=(DOMAIN, screen),
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
    async_add_entities: AddEntitiesCallback,
    factory: Callable[[str], list[LommepengeChildEntity]],
) -> None:
    """Opretter entiteter pr. barn - også for børn der tilføjes i appen senere."""
    known: set[str] = set()

    @callback
    def _add_new_children() -> None:
        new_ids = [
            c["id"] for c in coordinator.children if "id" in c and c["id"] not in known
        ]
        if not new_ids:
            return
        known.update(new_ids)
        async_add_entities([entity for child_id in new_ids for entity in factory(child_id)])

    _add_new_children()
    coordinator.config_entry.async_on_unload(coordinator.async_add_listener(_add_new_children))
