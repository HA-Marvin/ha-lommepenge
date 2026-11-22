"""Fælles test-opsætning: en falsk køleskabsskærm og en opsat integration."""

from __future__ import annotations

import copy
import sys
from typing import Any

import pytest

try:
    # Nyere pycares (DNS under aiodns) starter én global baggrundstråd ved
    # første DNS-opslag. Start den før testene, så HA's tjek for efterladte
    # tråde ikke fejlagtigt tilskriver den den første test.
    import pycares

    pycares._shutdown_manager.start()
except (ImportError, AttributeError):
    pass

if sys.platform == "win32":
    # HA's testværktøj blokerer alle ikke-unix-sockets (pytest_socket), men
    # Windows' asyncio-event-loop skal bruge en lokal TCP-socketpair
    # internt. Kun for at kunne køre testene på Windows; på Linux/CI er
    # blokeringen aktiv som normalt.
    import asyncio

    import pytest_socket

    pytest_socket.disable_socket = lambda *args, **kwargs: None
    # aiodns (HA's DNS-opslag) kræver en SelectorEventLoop på Windows.
    asyncio.get_event_loop_policy()._loop_factory = asyncio.SelectorEventLoop

from homeassistant.const import CONF_HOST, CONF_PORT
from homeassistant.core import HomeAssistant
from homeassistant.core_config import async_process_ha_core_config
from pytest_homeassistant_custom_component.common import MockConfigEntry
from pytest_homeassistant_custom_component.test_util.aiohttp import AiohttpClientMocker

from custom_components.lommepenge.const import CONF_TOKEN, CONF_WEBHOOK_ID, DOMAIN

HOST = "192.168.1.50"
PORT = 8087
BASE = f"http://{HOST}:{PORT}"
SCREEN_ID = "skaerm-123"
TOKEN = "hemmelig-nøgle"
WEBHOOK_ID = "lommepenge-webhook-test"

SUMMARY: dict[str, Any] = {
    "screenId": SCREEN_ID,
    "familyName": "Familien",
    "updatedAt": "2026-11-23T19:00:00",
    "settings": {
        "defaultDueTime": "18:00",
        "restrictionStart": "15:00",
        "restrictionEnd": "21:00",
        "latePauseMinutes": 10,
        "warningMinutes": 60,
        "winterFromWeek": 43,
        "winterToWeek": 13,
    },
    "children": [
        {
            "id": "emma",
            "name": "Emma",
            "balanceOre": 1250,
            "earnedThisWeekOre": 3000,
            "restricted": True,
            "reason": "Mangler: Tøm opvaskeren (frist 18:00)",
            "inWindow": True,
            "suspended": False,
            "latePauseUntil": None,
            "overdue": [{"taskId": "t1", "title": "Tøm opvaskeren", "due": "18:00"}],
            "dueToday": [],
        },
        {
            "id": "oskar",
            "name": "Oskar",
            "balanceOre": 0,
            "earnedThisWeekOre": 0,
            "restricted": False,
            "reason": None,
            "inWindow": True,
            "suspended": False,
            "latePauseUntil": None,
            "overdue": [],
            "dueToday": [],
        },
    ],
    "pending": [
        {
            "completionId": "c-1",
            "childId": "oskar",
            "childName": "Oskar",
            "taskId": "t2",
            "taskTitle": "Rede seng",
            "amountOre": 500,
            "completedAt": "2026-11-23T18:30:00",
            "late": False,
        }
    ],
}


@pytest.fixture(autouse=True)
def auto_enable_custom_integrations(enable_custom_integrations):
    """Indlæs integrationer fra custom_components/ i alle tests."""
    yield


@pytest.fixture
def summary() -> dict[str, Any]:
    return copy.deepcopy(SUMMARY)


@pytest.fixture
def mock_screen(aioclient_mock: AiohttpClientMocker, summary) -> AiohttpClientMocker:
    """Falsk køleskabsskærm med et gyldigt overblik."""
    aioclient_mock.get(f"{BASE}/ha/summary", json=summary)
    aioclient_mock.post(f"{BASE}/ha/action", json=summary)
    aioclient_mock.post(f"{BASE}/ha/webhook", json={"ok": True})
    return aioclient_mock


@pytest.fixture
def config_entry() -> MockConfigEntry:
    return MockConfigEntry(
        domain=DOMAIN,
        title="Familien",
        unique_id=SCREEN_ID,
        data={
            CONF_HOST: HOST,
            CONF_PORT: PORT,
            CONF_TOKEN: TOKEN,
            CONF_WEBHOOK_ID: WEBHOOK_ID,
        },
    )


@pytest.fixture
async def setup_integration(
    hass: HomeAssistant, config_entry: MockConfigEntry, mock_screen
) -> MockConfigEntry:
    await async_process_ha_core_config(hass, {"internal_url": "http://10.0.0.2:8123"})
    config_entry.add_to_hass(hass)
    assert await hass.config_entries.async_setup(config_entry.entry_id)
    await hass.async_block_till_done()
    return config_entry
