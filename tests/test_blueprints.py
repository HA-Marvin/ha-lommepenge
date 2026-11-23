"""The blueprints pass HA's own schemas, filled in with sample input."""

from __future__ import annotations

from pathlib import Path

import pytest

from homeassistant.components.automation.config import PLATFORM_SCHEMA
from homeassistant.components.blueprint.models import Blueprint, BlueprintInputs
from homeassistant.components.blueprint.schemas import BLUEPRINT_SCHEMA
from homeassistant.core import HomeAssistant
from homeassistant.util.yaml import load_yaml

BLUEPRINTS = Path(__file__).parent.parent / "blueprints" / "automation" / "lommepenge"

# The required inputs; the texts keep their (English) defaults.
SAMPLE_INPUT = {
    "notify_services": ["notify.mobile_app_pixel_8", "notify.mobile_app_iphone"],
    "parents": ["person.mum", "person.dad"],
    "restricted_sensor": "binary_sensor.lommepenge_emma_tablet_restricted",
    "block_switch": "switch.unifi_emma_tablet_entertainment",
}


@pytest.mark.parametrize("path", sorted(BLUEPRINTS.glob("*.yaml")), ids=lambda p: p.name)
async def test_blueprint_is_valid(hass: HomeAssistant, path: Path) -> None:
    blueprint = Blueprint(load_yaml(path), expected_domain="automation", schema=BLUEPRINT_SCHEMA)
    assert blueprint.metadata["source_url"].endswith(path.name)
    inputs = {key: SAMPLE_INPUT[key] for key in blueprint.inputs if key in SAMPLE_INPUT}
    config = BlueprintInputs(blueprint, {"use_blueprint": {"path": path.name, "input": inputs}})
    PLATFORM_SCHEMA(config.async_substitute())


def test_restriction_blueprint_only_drives_the_switch() -> None:
    """Del H4: no notifications to the parents about locks (they are in the
    history) - the blueprint only follows the "Tablet restricted" sensor."""
    blueprint = Blueprint(
        load_yaml(BLUEPRINTS / "restriction.yaml"),
        expected_domain="automation",
        schema=BLUEPRINT_SCHEMA,
    )
    assert set(blueprint.inputs) == {"restricted_sensor", "block_switch"}
