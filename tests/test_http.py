"""Appens HTTP-API: installation, parring, signerede kald og roller."""

from __future__ import annotations

import time

from homeassistant.core import HomeAssistant
from pytest_homeassistant_custom_component.common import MockConfigEntry
from pytest_homeassistant_custom_component.test_util.aiohttp import AiohttpClientMocker

from custom_components.lommepenge.const import (
    CONF_GITHUB_TOKEN,
    ROLE_CHILD,
    ROLE_PARENT,
    ROLE_SCREEN,
)

from .conftest import AppClient, add_child, paired_app, setup_entry

GITHUB = "https://api.github.com/repos/HA-Marvin/lommepenge-app"
SHA = "a" * 64


def mock_github(aioclient_mock: AiohttpClientMocker, tag: str = "v1.1.0") -> None:
    version = tag.lstrip("v")
    aioclient_mock.get(
        f"{GITHUB}/releases/latest",
        json={
            "tag_name": tag,
            "html_url": f"https://github.com/HA-Marvin/lommepenge-app/releases/{tag}",
            "body": "Nyt",
            "assets": [
                {"name": f"lommepenge-{version}.apk", "url": f"{GITHUB}/releases/assets/1", "size": 4},
                {
                    "name": f"lommepenge-{version}.apk.sha256",
                    "url": f"{GITHUB}/releases/assets/2",
                    "size": 65,
                },
            ],
        },
    )
    aioclient_mock.get(f"{GITHUB}/releases/assets/2", text=f"{SHA}  lommepenge-{version}.apk\n")
    aioclient_mock.get(f"{GITHUB}/releases/assets/1", content=b"APK!")


async def test_install_page_and_pairing(
    hass: HomeAssistant, config_entry: MockConfigEntry, hass_client_no_auth
) -> None:
    runtime = await setup_entry(hass, config_entry)
    client = await hass_client_no_auth()
    token, _ = runtime.async_create_pairing("dev-1", "Køleskab", ROLE_SCREEN, None)

    page = await client.get(f"/api/lommepenge/install/{token}")
    html = await page.text()
    assert page.status == 200
    assert "Køleskab" in html and "Fælles skærm" in html
    assert f"token={token}" in html and "scheme=lommepenge" in html
    # Ingen GitHub-nøgle endnu: forklaring i stedet for download-knap.
    assert "GitHub-nøgle" in html

    qr = await client.get(f"/api/lommepenge/qr/{token}.svg")
    assert qr.status == 200 and qr.content_type == "image/svg+xml"

    app = AppClient(client)
    paired = await app.pair(token)
    assert paired["status"] == 200
    assert paired["role"] == ROLE_SCREEN and paired["familyName"] == "Familien"

    # Linket virker kun én gang.
    assert (await AppClient(client).pair(token))["status"] == 410
    page = await client.get(f"/api/lommepenge/install/{token}")
    assert "udløbet" in await page.text()

    response = await app.state()
    state = await response.json()
    assert response.status == 200
    assert state["device"]["role"] == ROLE_SCREEN
    assert state["pinHash"] == config_entry.data["pin_hash"]
    assert state["appUpdate"] is None


async def test_signature_is_required(
    hass: HomeAssistant, config_entry: MockConfigEntry, hass_client_no_auth
) -> None:
    await setup_entry(hass, config_entry)
    client = await hass_client_no_auth()
    app = await paired_app(hass, config_entry, client, "Mor", ROLE_PARENT)

    assert (await client.get("/api/lommepenge/state")).status == 401

    headers = app.headers("GET", "/api/lommepenge/state", b"")
    headers["X-Signature"] = "0" * 64
    assert (await client.get("/api/lommepenge/state", headers=headers)).status == 401

    headers = app.headers("GET", "/api/lommepenge/state", b"")
    headers["X-Timestamp"] = str(int(time.time()) - 3600)
    assert (await client.get("/api/lommepenge/state", headers=headers)).status == 401


async def test_parent_runs_the_family(
    hass: HomeAssistant, config_entry: MockConfigEntry, hass_client_no_auth
) -> None:
    await setup_entry(hass, config_entry)
    client = await hass_client_no_auth()
    app = await paired_app(hass, config_entry, client, "Mor", ROLE_PARENT)

    assert (await app.action("add_child", {"id": "emma", "name": "Emma"})).status == 200
    response = await app.action(
        "create_task",
        {"id": "t1", "title": "Rede seng", "amountOre": 500, "recurrence": "daily"},
    )
    state = await response.json()
    assert [t["title"] for t in state["tasks"]] == ["Rede seng"]

    response = await app.action("complete_task", {"taskId": "t1", "childId": "nobody"})
    assert response.status == 400
    assert (await response.json())["error"] == "Opgaven er ikke tildelt dette barn."

    family = config_entry.runtime_data.family
    assert family.child("emma")["name"] == "Emma"


async def test_child_tablet_is_limited(
    hass: HomeAssistant, config_entry: MockConfigEntry, hass_client_no_auth
) -> None:
    runtime = await setup_entry(hass, config_entry)
    await add_child(runtime, "emma", "Emma")
    await add_child(runtime, "oskar", "Oskar")
    await runtime.async_apply(
        {
            "type": "create_task",
            "payload": {"id": "t1", "title": "Rede seng", "amountOre": 500, "recurrence": "daily"},
        }
    )
    client = await hass_client_no_auth()
    tablet = await paired_app(hass, config_entry, client, "Emmas tablet", ROLE_CHILD, "emma")

    state = await (await tablet.state()).json()
    assert [c["name"] for c in state["children"]] == ["Emma"]
    assert "pinHash" not in state

    assert (await tablet.action("complete_task", {"taskId": "t1", "childId": "emma"})).status == 200
    assert (await tablet.action("complete_task", {"taskId": "t1", "childId": "oskar"})).status == 403
    pending = config_entry.runtime_data.family.data["completions"][0]
    response = await tablet.action("approve_completion", {"completionId": pending["id"]})
    assert response.status == 403
    assert (await tablet.action("add_child", {"name": "Hacker"})).status == 403


async def test_removed_device_is_revoked(
    hass: HomeAssistant, config_entry: MockConfigEntry, hass_client_no_auth
) -> None:
    await setup_entry(hass, config_entry)
    client = await hass_client_no_auth()
    app = await paired_app(hass, config_entry, client, "Mor", ROLE_PARENT)
    assert (await app.state()).status == 200

    subentry_id = next(iter(config_entry.subentries))
    hass.config_entries.async_remove_subentry(config_entry, subentry_id)
    await hass.async_block_till_done()

    assert (await app.state()).status == 401
    assert config_entry.runtime_data.devices == {}


async def test_unfinished_pairing_expires(
    hass: HomeAssistant, config_entry: MockConfigEntry, hass_client_no_auth, freezer
) -> None:
    runtime = await setup_entry(hass, config_entry)
    client = await hass_client_no_auth()
    token, _ = runtime.async_create_pairing("dev-x", "Glemt", ROLE_PARENT, None)
    app = AppClient(client)
    await app.pair(token)
    # "Tilføj enhed" blev aldrig gjort færdig i HA.
    freezer.tick(60 * 20)
    runtime.async_sync_subentries()
    assert "dev-x" not in runtime.devices


async def test_app_download_and_update_info(
    hass: HomeAssistant,
    config_entry: MockConfigEntry,
    hass_client_no_auth,
    aioclient_mock: AiohttpClientMocker,
) -> None:
    mock_github(aioclient_mock)
    config_entry.add_to_hass(hass)
    hass.config_entries.async_update_entry(config_entry, options={CONF_GITHUB_TOKEN: "ghp_x"})
    runtime = await setup_entry(hass, config_entry)
    client = await hass_client_no_auth()

    token, _ = runtime.async_create_pairing("dev-t", "Tablet", ROLE_PARENT, None)
    page = await (await client.get(f"/api/lommepenge/install/{token}")).text()
    assert "Hent appen" in page and "1.1.0" in page

    download = await client.get(f"/api/lommepenge/download/{token}/lommepenge-1.1.0.apk")
    assert download.status == 200
    assert download.content_type == "application/vnd.android.package-archive"
    assert await download.read() == b"APK!"
    assert (await client.get("/api/lommepenge/download/forkert/x.apk")).status == 404

    app = await paired_app(hass, config_entry, client, "Mor", ROLE_PARENT)
    state = await (await app.state()).json()
    assert state["appUpdate"] == {"version": "1.1.0", "versionCode": 10100, "sha256": SHA, "size": 4}

    apk = await app.get_signed("/api/lommepenge/apk")
    assert apk.status == 200 and await apk.read() == b"APK!"
    assert (await client.get("/api/lommepenge/apk")).status == 401

    # Opdateringsentiteten viser at enheden kører 1.0.0 og 1.1.0 findes.
    update = hass.states.get("update.mor_app")
    assert update.state == "on"
    assert update.attributes["installed_version"] == "1.0.0"
    assert update.attributes["latest_version"] == "1.1.0"
