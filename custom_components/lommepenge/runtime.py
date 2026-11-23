"""The integration's running state: the family's data, devices and pairing.

Everything is stored in HA's storage (`.storage/lommepenge.<entry_id>`), so it
is included in HA's backups. The devices' keys only live here - the app never
uses HA's own users/tokens.
"""

from __future__ import annotations

import asyncio
from collections.abc import Callable
from datetime import date, datetime, timedelta
import hashlib
import hmac
import re
import secrets
import time
from typing import Any

from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from . import logic
from .const import (
    CONF_CHILD_ID,
    CONF_CURRENCY,
    CONF_DEVICE_ID,
    CONF_FAMILY_NAME,
    CONF_LANGUAGE,
    CONF_PIN_HASH,
    CONF_PIN_SALT,
    CONF_ROLE,
    DEFAULT_CURRENCY,
    DEFAULT_LANGUAGE,
    DOMAIN,
    PAIRING_TTL,
    ROLE_CHILD,
    SIGNATURE_MAX_AGE,
    SUBENTRY_DEVICE,
)
from .family import Family, migrate_family
from .i18n import LocalizedError, normalize_language

STORAGE_VERSION = 1
# 1.2 (Del H): completions have `occurrenceDate`, the family has `missed` and
# `cleanedThrough`. A minor version, so an older integration can still read it.
STORAGE_MINOR_VERSION = 2
SAVE_DELAY = 2

# The pairing code can be typed on a device without a camera: 8 characters
# without easily confused characters (0/O, 1/I). It works once for 15 minutes,
# and after many wrong attempts pairing is refused for a while.
CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
CODE_LENGTH = 8
MAX_FAILED_PAIRINGS = 10
FAILED_PAIRING_WINDOW = 300  # seconds


def normalize_code(code: str) -> str:
    """Upper case, without spaces and dashes."""
    return re.sub(r"[^A-Z0-9]", "", code.upper())


def pairing_code(token: str) -> str:
    """The code as it is shown and typed."""
    return normalize_code(token)


class AuthError(LocalizedError):
    """The device is unknown or revoked, or the signature does not match."""


class PairingError(LocalizedError):
    """The pairing code is invalid, expired or already used."""


class TooManyPairingAttempts(PairingError):
    """Too many wrong codes - try again shortly."""


class ForbiddenError(LocalizedError):
    """The device's role may not perform the action."""


class _FamilyStore(Store[dict[str, Any]]):
    """The family's storage, with migration of older stored data."""

    async def _async_migrate_func(
        self, old_major_version: int, old_minor_version: int, old_data: dict[str, Any]
    ) -> dict[str, Any]:
        if old_major_version > STORAGE_VERSION:
            raise NotImplementedError
        if old_major_version == 1 and old_minor_version < 2 and old_data.get("family"):
            migrate_family(old_data["family"], local_now())
        return old_data


def local_now() -> datetime:
    """HA's local time as a naive `datetime` (same form as the app's times)."""
    return dt_util.now().replace(tzinfo=None)


def sign(key: str, timestamp: str, method: str, path: str, body: bytes) -> str:
    """HMAC-SHA256 over timestamp, method, path and body (like the app)."""
    message = f"{timestamp}\n{method.upper()}\n{path}\n".encode() + body
    return hmac.new(key.encode(), message, hashlib.sha256).hexdigest()


class LommepengeRuntime:
    """One family (config entry) with its data, devices and pairings."""

    def __init__(self, hass: HomeAssistant, entry: ConfigEntry) -> None:
        self.hass = hass
        self.entry = entry
        self._store: Store[dict[str, Any]] = _FamilyStore(
            hass,
            STORAGE_VERSION,
            f"{DOMAIN}.{entry.entry_id}",
            private=True,
            minor_version=STORAGE_MINOR_VERSION,
        )
        self.family = Family()
        self.devices: dict[str, dict[str, Any]] = {}
        self.pairings: dict[str, dict[str, Any]] = {}
        self._lock = asyncio.Lock()
        self._failed_pairings: list[float] = []
        self._listeners: list[Callable[[], None]] = []
        # Set by __init__.py once the coordinators are created.
        self.coordinator = None
        self.releases = None
        # Entity names in the integration's language (translation key -> name).
        self.entity_names: dict[str, str] = {}

    # ---- Loading and saving -----------------------------------------------------

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        self.family = Family(stored.get("family"))
        self.devices = stored.get("devices", {})
        self.pairings = stored.get("pairings", {})

    def _data_to_save(self) -> dict[str, Any]:
        return {"family": self.family.data, "devices": self.devices, "pairings": self.pairings}

    @callback
    def async_schedule_save(self) -> None:
        self._store.async_delay_save(self._data_to_save, SAVE_DELAY)

    async def async_save_now(self) -> None:
        await self._store.async_save(self._data_to_save())

    async def async_remove_storage(self) -> None:
        await self._store.async_remove()

    @property
    def family_name(self) -> str:
        return self.entry.data.get(CONF_FAMILY_NAME) or self.entry.title

    @property
    def language(self) -> str:
        """The integration's language (chosen at setup, never HA's)."""
        return normalize_language(self.entry.data.get(CONF_LANGUAGE)) or DEFAULT_LANGUAGE

    @property
    def currency(self) -> str:
        """The currency the family's amounts are shown in."""
        return self.entry.data.get(CONF_CURRENCY) or DEFAULT_CURRENCY

    # ---- Listeners (e.g. device entities) ------------------------------------------

    @callback
    def async_add_listener(self, listener: Callable[[], None]) -> Callable[[], None]:
        self._listeners.append(listener)
        return lambda: self._listeners.remove(listener)

    @callback
    def _notify(self) -> None:
        for listener in list(self._listeners):
            listener()

    # ---- Actions ---------------------------------------------------------------------

    async def async_apply(
        self,
        action: dict[str, Any],
        *,
        device: dict[str, Any] | None = None,
    ) -> dict[str, Any] | None:
        """Performs an action from a device (or from HA itself, `device=None`).

        A child's tablet may only mark its own child's tasks as done - that is
        enforced here and not just by hiding buttons in the app.
        """
        if device is not None and device["role"] == ROLE_CHILD:
            if not logic.is_action_allowed_for_child(action, device.get("childId") or ""):
                raise ForbiddenError("forbidden_action")
        async with self._lock:
            result = self.family.apply_action(action, local_now())
        self.async_schedule_save()
        if self.coordinator is not None:
            self.coordinator.async_refresh_now()
        return result

    async def async_cleanup(self) -> list[dict[str, Any]]:
        """The midnight cleanup (Del H2). Called by the coordinator every 30
        seconds; it only does something once a day has ended."""
        async with self._lock:
            before = self.family.data.get("cleanedThrough")
            records = self.family.cleanup(local_now())
        if records or self.family.data.get("cleanedThrough") != before:
            self.async_schedule_save()
        return records

    # ---- The app's data ------------------------------------------------------------

    def state_for(self, device: dict[str, Any]) -> dict[str, Any]:
        """What a device gets to see: the whole family, or only one child."""
        if device["role"] == ROLE_CHILD:
            # A tablet without a child (should not happen) sees no child.
            state = self.family.state_json(
                self.family_name, local_now(), device.get("childId") or ""
            )
        else:
            state = self.family.state_json(self.family_name, local_now())
            # The parent part on the screen and phones is locked with the family's PIN.
            state["pinHash"] = self.entry.data.get(CONF_PIN_HASH)
            state["pinSalt"] = self.entry.data.get(CONF_PIN_SALT)
        state["currency"] = self.currency
        state["device"] = {
            "id": device["id"],
            "name": device["name"],
            "role": device["role"],
            "childId": device.get("childId"),
        }
        release = self.releases.data if self.releases is not None else None
        state["appUpdate"] = release.as_json() if release is not None else None
        return state

    def history_for(
        self,
        device: dict[str, Any],
        before: date | None,
        child_id: str | None,
        types: set[str] | None,
    ) -> dict[str, Any]:
        """A page of history. A child's tablet only gets its own child's."""
        if device["role"] == ROLE_CHILD:
            own = device.get("childId") or ""
            if child_id is not None and child_id != own:
                raise ForbiddenError("forbidden_action")
            child_id = own
        if before is None:
            before = local_now().date() + timedelta(days=1)
        return self.family.history(before, child_id, types)

    # ---- Devices and pairing ---------------------------------------------------------

    @callback
    def async_create_pairing(
        self, device_id: str, name: str, role: str, child_id: str | None
    ) -> tuple[str, datetime]:
        """A new one-time code for a device. Returns the code and expiry (UTC)."""
        token = "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))
        expires = dt_util.utcnow() + PAIRING_TTL
        # Only one valid code per device at a time.
        self.pairings = {
            t: p for t, p in self.pairings.items() if p["deviceId"] != device_id
        }
        self.pairings[token] = {
            "deviceId": device_id,
            "name": name,
            "role": role,
            "childId": child_id,
            "expires": expires.isoformat(),
        }
        self.async_schedule_save()
        return token, expires

    def pairing(self, token: str) -> dict[str, Any] | None:
        """A valid (not expired) pairing, also if it has been used."""
        pairing = self.pairings.get(normalize_code(token))
        if pairing is None:
            return None
        if dt_util.parse_datetime(pairing["expires"]) < dt_util.utcnow():
            return None
        return pairing

    async def async_redeem_pairing(self, token: str, app_info: dict[str, Any]) -> dict[str, Any]:
        """Exchanges a pairing code for the device's own key (only once)."""
        now = time.monotonic()
        self._failed_pairings = [
            t for t in self._failed_pairings if now - t < FAILED_PAIRING_WINDOW
        ]
        if len(self._failed_pairings) >= MAX_FAILED_PAIRINGS:
            raise TooManyPairingAttempts("too_many_pairings")
        pairing = self.pairing(token)
        if pairing is None or pairing.get("used"):
            self._failed_pairings.append(now)
            raise PairingError("pairing_invalid")
        pairing["used"] = True
        device = {
            "id": pairing["deviceId"],
            "name": pairing["name"],
            "role": pairing["role"],
            "childId": pairing["childId"],
            "key": secrets.token_hex(32),
            "pairedAt": dt_util.utcnow().isoformat(),
            "lastSeen": dt_util.utcnow().isoformat(),
            "appVersion": app_info.get("appVersion"),
            "appVersionCode": app_info.get("appVersionCode"),
            # A new pairing of an existing device (new code) keeps it.
            "registered": self.devices.get(pairing["deviceId"], {}).get("registered", False),
        }
        self.devices[device["id"]] = device
        await self.async_save_now()
        self._notify()
        return device

    def verify(self, headers: dict[str, str], method: str, path: str, body: bytes) -> dict[str, Any]:
        """Finds the device behind a signed request, otherwise `AuthError`."""
        device = self.devices.get(headers.get("X-Device-Id", ""))
        timestamp = headers.get("X-Timestamp", "")
        signature = headers.get("X-Signature", "")
        if device is None:
            raise AuthError("device_not_connected")
        try:
            age = abs(time.time() - int(timestamp))
        except ValueError as err:
            raise AuthError("missing_timestamp") from err
        if age > SIGNATURE_MAX_AGE.total_seconds():
            raise AuthError("clock_skew")
        expected = sign(device["key"], timestamp, method, path, body)
        if not hmac.compare_digest(expected, signature):
            raise AuthError("invalid_signature")
        return device

    @callback
    def async_device_seen(self, device: dict[str, Any], headers: dict[str, str]) -> None:
        """Remembers when the device was last in contact, and its app version."""
        device["lastSeen"] = dt_util.utcnow().isoformat()
        version = headers.get("X-App-Version")
        code = headers.get("X-App-Version-Code", "")
        changed = False
        if version and version != device.get("appVersion"):
            device["appVersion"] = version
            changed = True
        if code.isdigit() and int(code) != device.get("appVersionCode"):
            device["appVersionCode"] = int(code)
            changed = True
        self.async_schedule_save()
        if changed:
            self._notify()

    @callback
    def async_sync_subentries(self) -> None:
        """Keeps the devices in step with the integration's "Devices" (subentries).

        A deleted subentry revokes the device's key immediately. Name, role and
        child follow the subentry.
        """
        subentries = {
            s.data[CONF_DEVICE_ID]: s
            for s in self.entry.subentries.values()
            if s.subentry_type == SUBENTRY_DEVICE
        }
        now = dt_util.utcnow()
        self.pairings = {
            token: p
            for token, p in self.pairings.items()
            if dt_util.parse_datetime(p["expires"]) > now
        }
        # A device can be paired before "Add device" is finished in HA.
        pending = {p["deviceId"] for p in self.pairings.values()}
        for device_id in list(self.devices):
            subentry = subentries.get(device_id)
            device = self.devices[device_id]
            if subentry is None:
                # The device was removed in HA - or the pairing was never
                # finished and the code has expired.
                if device.get("registered") or device_id not in pending:
                    del self.devices[device_id]
                    self.pairings = {
                        t: p for t, p in self.pairings.items() if p["deviceId"] != device_id
                    }
                continue
            device["registered"] = True
            device["name"] = subentry.title
            device["role"] = subentry.data[CONF_ROLE]
            device["childId"] = subentry.data.get(CONF_CHILD_ID)
        self.async_schedule_save()
        self._notify()
