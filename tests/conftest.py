"""Fælles test-opsætning: en familie i HA og hjælpere til appens enheder."""

from __future__ import annotations

import json
import sys
import time
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

from types import MappingProxyType

from homeassistant.config_entries import ConfigSubentry
from homeassistant.core import HomeAssistant
from homeassistant.core_config import async_process_ha_core_config
from pytest_homeassistant_custom_component.common import MockConfigEntry

from custom_components.lommepenge.config_flow import hash_pin
from custom_components.lommepenge.const import (
    CONF_CHILD_ID,
    CONF_DEVICE_ID,
    CONF_FAMILY_NAME,
    CONF_ROLE,
    DOMAIN,
    SUBENTRY_DEVICE,
)
from custom_components.lommepenge.runtime import LommepengeRuntime, sign

PIN = "1234"


@pytest.fixture(autouse=True)
def auto_enable_custom_integrations(enable_custom_integrations):
    """Indlæs integrationer fra custom_components/ i alle tests."""
    yield


@pytest.fixture
def config_entry() -> MockConfigEntry:
    return MockConfigEntry(
        domain=DOMAIN,
        version=2,
        title="Familien",
        data={CONF_FAMILY_NAME: "Familien", **hash_pin(PIN)},
    )


def device_subentry(
    device_id: str, name: str, role: str, child_id: str | None = None
) -> ConfigSubentry:
    return ConfigSubentry(
        data=MappingProxyType({CONF_DEVICE_ID: device_id, CONF_ROLE: role, CONF_CHILD_ID: child_id}),
        subentry_type=SUBENTRY_DEVICE,
        title=name,
        unique_id=device_id,
    )


async def setup_entry(hass: HomeAssistant, entry: MockConfigEntry) -> LommepengeRuntime:
    await async_process_ha_core_config(hass, {"internal_url": "http://192.168.1.129:8123"})
    if hass.config_entries.async_get_entry(entry.entry_id) is None:
        entry.add_to_hass(hass)
    assert await hass.config_entries.async_setup(entry.entry_id)
    await hass.async_block_till_done()
    return entry.runtime_data


@pytest.fixture
async def runtime(hass: HomeAssistant, config_entry: MockConfigEntry) -> LommepengeRuntime:
    return await setup_entry(hass, config_entry)


async def add_child(runtime: LommepengeRuntime, child_id: str, name: str) -> None:
    await runtime.async_apply({"type": "add_child", "payload": {"id": child_id, "name": name}})


class AppClient:
    """Simulerer appen: parring og signerede forespørgsler."""

    def __init__(self, client) -> None:
        self.client = client
        self.device_id: str | None = None
        self.key: str | None = None
        self.version = "1.0.0"
        self.version_code = 10000

    async def pair(self, token: str) -> dict[str, Any]:
        response = await self.client.post(
            "/api/lommepenge/pair",
            json={"token": token, "appVersion": self.version, "appVersionCode": self.version_code},
        )
        body = await response.json()
        if response.status == 200:
            self.device_id = body["deviceId"]
            self.key = body["deviceKey"]
        return {"status": response.status, **body}

    def headers(self, method: str, path: str, body: bytes) -> dict[str, str]:
        timestamp = str(int(time.time()))
        return {
            "X-Device-Id": self.device_id or "",
            "X-Timestamp": timestamp,
            "X-Signature": sign(self.key or "", timestamp, method, path, body),
            "X-App-Version": self.version,
            "X-App-Version-Code": str(self.version_code),
        }

    async def state(self):
        path = "/api/lommepenge/state"
        return await self.client.get(path, headers=self.headers("GET", path, b""))

    async def action(self, action_type: str, payload: dict[str, Any]):
        path = "/api/lommepenge/action"
        body = json.dumps({"type": action_type, "payload": payload}).encode()
        headers = {**self.headers("POST", path, body), "Content-Type": "application/json"}
        return await self.client.post(path, data=body, headers=headers)

    async def get_signed(self, path: str):
        return await self.client.get(path, headers=self.headers("GET", path, b""))


async def paired_app(
    hass: HomeAssistant,
    entry: MockConfigEntry,
    client,
    name: str,
    role: str,
    child_id: str | None = None,
) -> AppClient:
    """Tilføjer en enhed som i "Tilføj enhed" og parrer en app med den."""
    runtime: LommepengeRuntime = entry.runtime_data
    device_id = f"dev-{name.lower()}"
    token, _ = runtime.async_create_pairing(device_id, name, role, child_id)
    app = AppClient(client)
    assert (await app.pair(token))["status"] == 200
    hass.config_entries.async_add_subentry(entry, device_subentry(device_id, name, role, child_id))
    await hass.async_block_till_done()
    return app
