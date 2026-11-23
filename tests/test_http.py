"""The app's HTTP API: installation, pairing, signed requests and roles."""

from __future__ import annotations

import time

from homeassistant.core import HomeAssistant
from homeassistant.helpers import device_registry as dr
from pytest_homeassistant_custom_component.common import MockConfigEntry
from pytest_homeassistant_custom_component.test_util.aiohttp import AiohttpClientMocker

from custom_components.lommepenge.const import DOMAIN, ROLE_CHILD, ROLE_PARENT, ROLE_SCREEN
from custom_components.lommepenge.runtime import sign

from .conftest import GITHUB, AppClient, add_child, family_entry, paired_app, setup_entry

DOWNLOADS = "https://github.com/HA-Marvin/ha-lommepenge/releases/download"
SHA = "a" * 64


def mock_github(aioclient_mock: AiohttpClientMocker, tag: str = "v1.1.0") -> None:
    """A release with the app: fetched without a token via the plain download links."""
    version = tag.lstrip("v")
    aioclient_mock.clear_requests()
    aioclient_mock.get(
        f"{GITHUB}/releases/latest",
        json={
            "tag_name": tag,
            "html_url": f"https://github.com/HA-Marvin/lommepenge-app/releases/{tag}",
            "body": "New",
            "assets": [
                {
                    "name": f"lommepenge-{version}.apk",
                    "url": f"{GITHUB}/releases/assets/1",
                    "browser_download_url": f"{DOWNLOADS}/{tag}/lommepenge-{version}.apk",
                    "size": 4,
                },
                {
                    "name": f"lommepenge-{version}.apk.sha256",
                    "url": f"{GITHUB}/releases/assets/2",
                    "browser_download_url": f"{DOWNLOADS}/{tag}/lommepenge-{version}.apk.sha256",
                    "size": 65,
                },
            ],
        },
    )
    aioclient_mock.get(
        f"{DOWNLOADS}/{tag}/lommepenge-{version}.apk.sha256",
        text=f"{SHA}  lommepenge-{version}.apk\n",
    )
    aioclient_mock.get(f"{DOWNLOADS}/{tag}/lommepenge-{version}.apk", content=b"APK!")


async def test_install_page_and_pairing(
    hass: HomeAssistant, config_entry: MockConfigEntry, hass_client_no_auth
) -> None:
    runtime = await setup_entry(hass, config_entry)
    client = await hass_client_no_auth()
    token, _ = runtime.async_create_pairing("dev-1", "Kitchen", ROLE_SCREEN, None)

    # Opened on the computer (from the link in HA): code, QR code and instructions.
    page = await client.get(f"/api/lommepenge/install/{token}")
    html = await page.text()
    assert page.status == 200
    assert "Add Kitchen" in html and "Family screen" in html
    assert '<html lang="en">' in html
    assert f'<p class="code">{token}</p>' in html
    assert "<svg" in html
    assert "scheme=lommepenge" not in html  # "Open the app" only on Android
    # No app release yet: an explanation instead of a download button.
    assert "has not been able to fetch the app" in html

    # Opened on Android (via the QR code): also "Open the app and connect".
    page = await client.get(
        f"/api/lommepenge/install/{token}",
        headers={"User-Agent": "Mozilla/5.0 (Linux; Android 14) Chrome/130"},
    )
    html = await page.text()
    assert f"token={token}" in html and "scheme=lommepenge" in html

    qr = await client.get(f"/api/lommepenge/qr/{token}.svg")
    assert qr.status == 200 and qr.content_type == "image/svg+xml"

    app = AppClient(client)
    paired = await app.pair(token)
    assert paired["status"] == 200
    assert paired["role"] == ROLE_SCREEN and paired["familyName"] == "The Family"

    # The code only works once.
    assert (await AppClient(client).pair(token))["status"] == 410
    page = await client.get(f"/api/lommepenge/install/{token}")
    assert "used or expired" in await page.text()

    response = await app.state()
    state = await response.json()
    assert response.status == 200
    assert state["device"]["role"] == ROLE_SCREEN
    assert state["pinHash"] == config_entry.data["pin_hash"]
    assert state["appUpdate"] is None
    assert state["currency"] == "DKK"


async def test_install_page_in_chosen_language(
    hass: HomeAssistant, hass_client_no_auth
) -> None:
    entry = family_entry("de")
    runtime = await setup_entry(hass, entry)
    client = await hass_client_no_auth()
    token, _ = runtime.async_create_pairing("dev-1", "Küche", ROLE_CHILD, None)
    html = await (await client.get(f"/api/lommepenge/install/{token}")).text()
    assert '<html lang="de">' in html
    assert "Küche hinzufügen" in html and "Tablet des Kindes" in html
    assert "Mit Code verbinden" in html


async def test_signature_is_required(
    hass: HomeAssistant, config_entry: MockConfigEntry, hass_client_no_auth
) -> None:
    await setup_entry(hass, config_entry)
    client = await hass_client_no_auth()
    app = await paired_app(hass, config_entry, client, "Mum", ROLE_PARENT)

    response = await client.get("/api/lommepenge/state")
    assert response.status == 401
    assert (await response.json())["code"] == "device_not_connected"

    headers = app.headers("GET", "/api/lommepenge/state", b"")
    headers["X-Signature"] = "0" * 64
    response = await client.get("/api/lommepenge/state", headers=headers)
    assert response.status == 401
    assert (await response.json())["code"] == "invalid_signature"

    headers = app.headers("GET", "/api/lommepenge/state", b"")
    headers["X-Timestamp"] = str(int(time.time()) - 3600)
    response = await client.get("/api/lommepenge/state", headers=headers)
    assert response.status == 401
    body = await response.json()
    assert body["error"] == "The device's clock is wrong, or the request is too old."
    # HA's own time comes along, so the app can correct its clock instead of
    # being disconnected.
    assert body["code"] == "clock_skew"
    assert abs(body["serverTime"] - time.time()) < 5

    # A request signed with the corrected time works with the same key.
    timestamp = str(body["serverTime"])
    headers = app.headers("GET", "/api/lommepenge/state", b"")
    headers["X-Timestamp"] = timestamp
    headers["X-Signature"] = sign(app.key, timestamp, "GET", "/api/lommepenge/state", b"")
    assert (await client.get("/api/lommepenge/state", headers=headers)).status == 200


async def test_parent_runs_the_family(
    hass: HomeAssistant, config_entry: MockConfigEntry, hass_client_no_auth
) -> None:
    await setup_entry(hass, config_entry)
    client = await hass_client_no_auth()
    app = await paired_app(hass, config_entry, client, "Mum", ROLE_PARENT)

    assert (await app.action("add_child", {"id": "emma", "name": "Emma"})).status == 200
    response = await app.action(
        "create_task",
        {"id": "t1", "title": "Make the bed", "amountOre": 500, "recurrence": "daily"},
    )
    state = await response.json()
    assert [t["title"] for t in state["tasks"]] == ["Make the bed"]

    response = await app.action("complete_task", {"taskId": "t1", "childId": "nobody"})
    assert response.status == 400
    assert (await response.json())["error"] == "The task is not assigned to this child."

    family = config_entry.runtime_data.family
    assert family.child("emma")["name"] == "Emma"


async def test_errors_follow_the_apps_language(
    hass: HomeAssistant, config_entry: MockConfigEntry, hass_client_no_auth
) -> None:
    """The integration is English, but each app gets errors in its own language."""
    await setup_entry(hass, config_entry)
    client = await hass_client_no_auth()
    danish = await paired_app(hass, config_entry, client, "Mor", ROLE_PARENT, language="da")
    french = await paired_app(hass, config_entry, client, "Papa", ROLE_PARENT, language="fr-FR")

    response = await danish.action("complete_task", {"taskId": "t1", "childId": "nobody"})
    assert (await response.json())["error"] == "Opgaven findes ikke længere."
    response = await french.action("complete_task", {"taskId": "t1", "childId": "nobody"})
    assert (await response.json())["error"] == "La tâche n'existe plus."
    response = await danish.action("hack", {})
    assert (await response.json())["error"] == "Ukendt handling: hack"

    # A browser's/phone's own language is never used - only the app's choice.
    result = await AppClient(client).client.post(
        "/api/lommepenge/pair", json={"token": "nope"}, headers={"Accept-Language": "da"}
    )
    assert (await result.json())["error"].startswith("The code is wrong")


async def test_child_tablet_is_limited(
    hass: HomeAssistant, config_entry: MockConfigEntry, hass_client_no_auth
) -> None:
    runtime = await setup_entry(hass, config_entry)
    await add_child(runtime, "emma", "Emma")
    await add_child(runtime, "oscar", "Oscar")
    await runtime.async_apply(
        {
            "type": "create_task",
            "payload": {"id": "t1", "title": "Make the bed", "amountOre": 500, "recurrence": "daily"},
        }
    )
    client = await hass_client_no_auth()
    tablet = await paired_app(hass, config_entry, client, "Emma's tablet", ROLE_CHILD, "emma")

    state = await (await tablet.state()).json()
    assert [c["name"] for c in state["children"]] == ["Emma"]
    assert "pinHash" not in state

    assert (await tablet.action("complete_task", {"taskId": "t1", "childId": "emma"})).status == 200
    response = await tablet.action("complete_task", {"taskId": "t1", "childId": "oscar"})
    assert response.status == 403
    assert (await response.json())["error"] == (
        "This device is not allowed to perform this action."
    )
    pending = config_entry.runtime_data.family.data["completions"][0]
    response = await tablet.action("approve_completion", {"completionId": pending["id"]})
    assert response.status == 403
    assert (await tablet.action("add_child", {"name": "Hacker"})).status == 403


async def test_removed_device_is_revoked(
    hass: HomeAssistant, config_entry: MockConfigEntry, hass_client_no_auth
) -> None:
    await setup_entry(hass, config_entry)
    client = await hass_client_no_auth()
    app = await paired_app(hass, config_entry, client, "Mum", ROLE_PARENT)
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
    token, _ = runtime.async_create_pairing("dev-x", "Forgotten", ROLE_PARENT, None)
    app = AppClient(client)
    await app.pair(token)
    # "Add device" was never finished in HA.
    freezer.tick(60 * 20)
    runtime.async_sync_subentries()
    assert "dev-x" not in runtime.devices


async def test_app_download_and_update_info(
    hass: HomeAssistant,
    config_entry: MockConfigEntry,
    hass_client_no_auth,
    aioclient_mock: AiohttpClientMocker,
) -> None:
    # The integration's own, public repository - no GitHub token.
    mock_github(aioclient_mock)
    runtime = await setup_entry(hass, config_entry)
    client = await hass_client_no_auth()

    token, _ = runtime.async_create_pairing("dev-t", "Tablet", ROLE_PARENT, None)
    page = await (await client.get(f"/api/lommepenge/install/{token}")).text()
    assert "Download the app" in page and "1.1.0" in page

    download = await client.get(f"/api/lommepenge/download/{token}/lommepenge-1.1.0.apk")
    assert download.status == 200
    assert download.content_type == "application/vnd.android.package-archive"
    assert await download.read() == b"APK!"
    assert (await client.get("/api/lommepenge/download/wrong/x.apk")).status == 404

    app = await paired_app(hass, config_entry, client, "Mum", ROLE_PARENT)
    state = await (await app.state()).json()
    assert state["appUpdate"] == {"version": "1.1.0", "versionCode": 10100, "sha256": SHA, "size": 4}

    apk = await app.get_signed("/api/lommepenge/apk")
    assert apk.status == 200 and await apk.read() == b"APK!"
    assert (await client.get("/api/lommepenge/apk")).status == 401

    # The update entity shows that the device runs 1.0.0 and 1.1.0 exists.
    update = hass.states.get("update.mum_app")
    assert update.state == "on"
    assert update.attributes["installed_version"] == "1.0.0"
    assert update.attributes["latest_version"] == "1.1.0"


async def test_code_can_be_typed(
    hass: HomeAssistant, config_entry: MockConfigEntry, hass_client_no_auth
) -> None:
    runtime = await setup_entry(hass, config_entry)
    client = await hass_client_no_auth()
    code, _ = runtime.async_create_pairing("dev-k", "Kitchen", ROLE_SCREEN, None)
    assert len(code) == 8 and code.isalnum() and code.isupper()
    assert not set(code) & set("01IO")

    # Lower case and a dash, the way a person types it.
    typed = f"{code[:4].lower()}-{code[4:].lower()}"
    assert (await AppClient(client).pair(typed))["status"] == 200


async def test_wrong_codes_are_rate_limited(
    hass: HomeAssistant, config_entry: MockConfigEntry, hass_client_no_auth
) -> None:
    runtime = await setup_entry(hass, config_entry)
    client = await hass_client_no_auth()
    code, _ = runtime.async_create_pairing("dev-k", "Kitchen", ROLE_SCREEN, None)
    for _ in range(10):
        assert (await AppClient(client).pair("WRONG234"))["status"] == 410
    # Now the right code is also refused for a while.
    result = await AppClient(client).pair(code)
    assert result["status"] == 429
    assert "Wait five minutes" in result["error"]
    result = await AppClient(client, "es").pair(code)
    assert "Espera cinco minutos" in result["error"]


async def test_app_link_without_code(
    hass: HomeAssistant,
    config_entry: MockConfigEntry,
    hass_client_no_auth,
    aioclient_mock: AiohttpClientMocker,
) -> None:
    await setup_entry(hass, config_entry)
    client = await hass_client_no_auth()
    # No release yet.
    assert (await client.get("/api/lommepenge/app.apk")).status == 404

    mock_github(aioclient_mock)
    await config_entry.runtime_data.releases.async_refresh()
    response = await client.get("/api/lommepenge/app.apk")
    assert response.status == 200 and await response.read() == b"APK!"


async def test_home_page_from_ha(
    hass: HomeAssistant,
    config_entry: MockConfigEntry,
    hass_client_no_auth,
    aioclient_mock: AiohttpClientMocker,
) -> None:
    """'Visit' on the family's device in HA leads to the app and instructions."""
    mock_github(aioclient_mock)
    await setup_entry(hass, config_entry)
    device = dr.async_get(hass).async_get_device(identifiers={(DOMAIN, config_entry.entry_id)})
    assert device.configuration_url.endswith(":8123/api/lommepenge")
    assert device.model == "Family"

    client = await hass_client_no_auth()
    html = await (await client.get("/api/lommepenge")).text()
    assert "Download the app (.apk, version 1.1.0)" in html
    assert 'href="/api/lommepenge/app.apk"' in html
    assert "Add device" in html


async def test_state_is_the_current_view(
    hass: HomeAssistant, config_entry: MockConfigEntry, hass_client_no_auth, freezer
) -> None:
    """Del H1: HA sends only the current state, calculated per child - no history."""
    freezer.move_to("2026-11-23 12:00:00+01:00")
    await hass.config.async_set_time_zone("Europe/Copenhagen")
    runtime = await setup_entry(hass, config_entry)
    await add_child(runtime, "emma", "Emma")
    await add_child(runtime, "oscar", "Oscar")
    client = await hass_client_no_auth()
    parent = await paired_app(hass, config_entry, client, "Mum", ROLE_PARENT)
    tablet = await paired_app(hass, config_entry, client, "Emma's tablet", ROLE_CHILD, "emma")
    await parent.action(
        "create_task",
        {"id": "t1", "title": "Dishes", "amountOre": 500, "recurrence": "daily", "mandatory": True},
    )

    # The child marks it as done with the app's own completion id; a retry
    # (e.g. after a timeout) is a success without a second completion.
    for _ in range(2):
        response = await tablet.action(
            "complete_task", {"taskId": "t1", "childId": "emma", "completionId": "app-c1"}
        )
        assert response.status == 200
        state = await response.json()
        assert state["children"][0]["tasks"][0]["status"] == "awaitingApproval"
    # (Adding devices reloads the entry, so look the runtime up again.)
    assert len(config_entry.runtime_data.family.data["completions"]) == 1

    assert state["today"] == "2026-11-23"
    assert state["now"].startswith("2026-11-23T12:00")
    assert [c["name"] for c in state["children"]] == ["Emma"]
    for key in ("approvals", "tasks", "settings", "pinHash", "completions", "balanceAdjustments"):
        assert key not in state
    entry = state["children"][0]["tasks"][0]
    assert entry["completionId"] == "app-c1" and entry["deadline"] == "2026-11-23T18:00:00.000"

    state = await (await parent.state()).json()
    assert [c["name"] for c in state["children"]] == ["Emma", "Oscar"]
    assert state["children"][1]["tasks"][0]["status"] == "available"
    assert [a["completionId"] for a in state["approvals"]] == ["app-c1"]
    assert state["approvals"][0]["childName"] == "Emma"
    assert [t["id"] for t in state["tasks"]] == ["t1"]
    assert state["settings"]["defaultDueTime"] == "18:00"
    assert "completions" not in state and "balanceAdjustments" not in state

    response = await parent.action("approve_completion", {"completionId": "app-c1"})
    state = await response.json()
    assert state["approvals"] == []
    emma = state["children"][0]
    assert emma["balanceOre"] == 500 and emma["earnedThisWeekOre"] == 500
    assert emma["tasks"][0]["date"] == "2026-11-24"
    # Approving again (retry, or the other parent) is fine.
    assert (await parent.action("approve_completion", {"completionId": "app-c1"})).status == 200

    response = await parent.action("reject_completion", {"completionId": "app-c1"})
    assert response.status == 400
    assert (await response.json())["code"] == "completion_already_handled"


async def test_history_on_request(
    hass: HomeAssistant, config_entry: MockConfigEntry, hass_client_no_auth, freezer
) -> None:
    freezer.move_to("2026-11-23 12:00:00+01:00")
    await hass.config.async_set_time_zone("Europe/Copenhagen")
    runtime = await setup_entry(hass, config_entry)
    await add_child(runtime, "emma", "Emma")
    await add_child(runtime, "oscar", "Oscar")
    await runtime.async_apply(
        {
            "type": "adjust_balance",
            "payload": {"id": "a1", "childId": "oscar", "amountOre": 1000, "note": "Birthday"},
        }
    )
    freezer.move_to("2026-11-23 12:01:00+01:00")
    await runtime.async_apply(
        {
            "type": "adjust_balance",
            "payload": {"id": "a2", "childId": "emma", "amountOre": -200, "note": "Sweets"},
        }
    )
    client = await hass_client_no_auth()
    parent = await paired_app(hass, config_entry, client, "Mum", ROLE_PARENT)
    tablet = await paired_app(hass, config_entry, client, "Emma's tablet", ROLE_CHILD, "emma")

    response = await parent.get_signed("/api/lommepenge/history")
    assert response.status == 200
    page = await response.json()
    assert [i["id"] for i in page["items"]] == ["a2", "a1"]
    assert page["before"] == "2026-11-24" and page["from"] == "2026-10-25"
    assert page["nextBefore"] is None
    assert page["items"][0] == {
        "id": "a2",
        "type": "adjustment",
        "at": "2026-11-23T12:01:00.000",
        "childId": "emma",
        "childName": "Emma",
        "taskId": None,
        "taskTitle": None,
        "amountOre": -200,
        "completedAt": None,
        "late": False,
        "note": "Sweets",
    }

    # The query string is part of the signature.
    page = await (
        await parent.get_signed("/api/lommepenge/history?childId=oscar&types=adjustment")
    ).json()
    assert [i["id"] for i in page["items"]] == ["a1"]
    page = await (await parent.get_signed("/api/lommepenge/history?before=2026-11-23")).json()
    assert page["items"] == [] and page["from"] == "2026-10-24"

    # A child's tablet only gets its own child's history.
    page = await (await tablet.get_signed("/api/lommepenge/history")).json()
    assert [i["id"] for i in page["items"]] == ["a2"]
    response = await tablet.get_signed("/api/lommepenge/history?childId=oscar")
    assert response.status == 403
    assert (await response.json())["code"] == "forbidden_action"

    response = await parent.get_signed("/api/lommepenge/history?before=yesterday")
    assert response.status == 400
    assert (await response.json())["code"] == "invalid_request"
    response = await parent.get_signed("/api/lommepenge/history?types=locks")
    assert response.status == 400

    # A query string that was not signed is refused.
    headers = parent.headers("GET", "/api/lommepenge/history", b"")
    response = await client.get("/api/lommepenge/history?childId=oscar", headers=headers)
    assert response.status == 401
