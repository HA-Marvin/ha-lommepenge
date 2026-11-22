"""Integrationens kørende tilstand: familiens data, enheder og parring.

Alt gemmes i HA's storage (`.storage/lommepenge.<entry_id>`), så det kommer
med i HA's backups. Enhedernes nøgler ligger kun her - HA's egne
brugere/tokens bruges aldrig af appen.
"""

from __future__ import annotations

import asyncio
from collections.abc import Callable
from datetime import datetime
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
    CONF_DEVICE_ID,
    CONF_FAMILY_NAME,
    CONF_PIN_HASH,
    CONF_PIN_SALT,
    CONF_ROLE,
    DOMAIN,
    PAIRING_TTL,
    ROLE_CHILD,
    SIGNATURE_MAX_AGE,
    SUBENTRY_DEVICE,
)
from .family import Family, FamilyError

STORAGE_VERSION = 1
SAVE_DELAY = 2

# Parringskoden kan tastes på en enhed uden kamera: 8 tegn uden forvekslelige
# tegn (0/O, 1/I). Den virker én gang i 15 minutter, og efter mange forkerte
# forsøg afvises parring et stykke tid.
CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
CODE_LENGTH = 8
MAX_FAILED_PAIRINGS = 10
FAILED_PAIRING_WINDOW = 300  # sekunder


def normalize_code(code: str) -> str:
    """Store bogstaver, uden mellemrum og bindestreger."""
    return re.sub(r"[^A-Z0-9]", "", code.upper())


class AuthError(Exception):
    """Enheden er ukendt, tilbagekaldt, eller signaturen passer ikke."""


class PairingError(Exception):
    """Parringslinket er ugyldigt, udløbet eller allerede brugt."""


class TooManyPairingAttempts(PairingError):
    """For mange forkerte koder - prøv igen om lidt."""


class ForbiddenError(Exception):
    """Enhedens rolle må ikke udføre handlingen."""


def local_now() -> datetime:
    """HA's lokale tid som naiv `datetime` (samme form som appens tider)."""
    return dt_util.now().replace(tzinfo=None)


def sign(key: str, timestamp: str, method: str, path: str, body: bytes) -> str:
    """HMAC-SHA256 over tidspunkt, metode, sti og krop (som appen)."""
    message = f"{timestamp}\n{method.upper()}\n{path}\n".encode() + body
    return hmac.new(key.encode(), message, hashlib.sha256).hexdigest()


class LommepengeRuntime:
    """Én familie (config entry) med dens data, enheder og parringer."""

    def __init__(self, hass: HomeAssistant, entry: ConfigEntry) -> None:
        self.hass = hass
        self.entry = entry
        self._store: Store[dict[str, Any]] = Store(
            hass, STORAGE_VERSION, f"{DOMAIN}.{entry.entry_id}", private=True
        )
        self.family = Family()
        self.devices: dict[str, dict[str, Any]] = {}
        self.pairings: dict[str, dict[str, Any]] = {}
        self._lock = asyncio.Lock()
        self._failed_pairings: list[float] = []
        self._listeners: list[Callable[[], None]] = []
        # Sættes af __init__.py, når koordinatorerne er oprettet.
        self.coordinator = None
        self.releases = None

    # ---- Indlæsning og gemning ----------------------------------------------

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

    # ---- Lyttere (fx enheds-entiteter) ---------------------------------------

    @callback
    def async_add_listener(self, listener: Callable[[], None]) -> Callable[[], None]:
        self._listeners.append(listener)
        return lambda: self._listeners.remove(listener)

    @callback
    def _notify(self) -> None:
        for listener in list(self._listeners):
            listener()

    # ---- Handlinger ------------------------------------------------------------

    async def async_apply(
        self,
        action: dict[str, Any],
        *,
        device: dict[str, Any] | None = None,
    ) -> dict[str, Any] | None:
        """Udfører en handling fra en enhed (eller fra HA selv, `device=None`).

        En barne-tablet må kun markere sit eget barns opgaver udført - det
        håndhæves her og ikke kun ved at skjule knapper i appen.
        """
        if device is not None and device["role"] == ROLE_CHILD:
            if not logic.is_action_allowed_for_child(action, device.get("childId") or ""):
                raise ForbiddenError("Denne enhed må ikke udføre handlingen.")
        async with self._lock:
            result = self.family.apply_action(action, local_now())
        self.async_schedule_save()
        if self.coordinator is not None:
            self.coordinator.async_refresh_now()
        return result

    # ---- Appens data ---------------------------------------------------------

    def state_for(self, device: dict[str, Any]) -> dict[str, Any]:
        """Det en enhed får at se: hele familien, eller kun ét barn."""
        state = self.family.state_json(self.family_name, local_now())
        if device["role"] == ROLE_CHILD:
            state = logic.filter_state_for_child(state, device.get("childId") or "")
        else:
            # Forælder-delen på skærm og telefon er låst med familiens PIN.
            state["pinHash"] = self.entry.data.get(CONF_PIN_HASH)
            state["pinSalt"] = self.entry.data.get(CONF_PIN_SALT)
        state["device"] = {
            "id": device["id"],
            "name": device["name"],
            "role": device["role"],
            "childId": device.get("childId"),
        }
        release = self.releases.data if self.releases is not None else None
        state["appUpdate"] = release.as_json() if release is not None else None
        return state

    # ---- Enheder og parring ----------------------------------------------------

    @callback
    def async_create_pairing(
        self, device_id: str, name: str, role: str, child_id: str | None
    ) -> tuple[str, datetime]:
        """Ny engangskode til en enhed. Returnerer koden og udløb (UTC)."""
        token = "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))
        expires = dt_util.utcnow() + PAIRING_TTL
        # Kun ét gyldigt link pr. enhed ad gangen.
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
        """Et gyldigt (ikke udløbet) parringslink, også hvis det er brugt."""
        pairing = self.pairings.get(normalize_code(token))
        if pairing is None:
            return None
        if dt_util.parse_datetime(pairing["expires"]) < dt_util.utcnow():
            return None
        return pairing

    async def async_redeem_pairing(self, token: str, app_info: dict[str, Any]) -> dict[str, Any]:
        """Bytter en parringskode til enhedens egen nøgle (kun én gang)."""
        now = time.monotonic()
        self._failed_pairings = [
            t for t in self._failed_pairings if now - t < FAILED_PAIRING_WINDOW
        ]
        if len(self._failed_pairings) >= MAX_FAILED_PAIRINGS:
            raise TooManyPairingAttempts(
                "For mange forkerte koder. Vent fem minutter, og prøv igen."
            )
        pairing = self.pairing(token)
        if pairing is None or pairing.get("used"):
            self._failed_pairings.append(now)
            raise PairingError(
                "Koden er forkert, udløbet eller allerede brugt. Lav en ny under "
                "Lommepenge → Tilføj enhed i Home Assistant."
            )
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
            # Ny parring af en eksisterende enhed (ny QR-kode) beholder den.
            "registered": self.devices.get(pairing["deviceId"], {}).get("registered", False),
        }
        self.devices[device["id"]] = device
        await self.async_save_now()
        self._notify()
        return device

    def verify(self, headers: dict[str, str], method: str, path: str, body: bytes) -> dict[str, Any]:
        """Finder enheden bag en signeret forespørgsel, ellers `AuthError`."""
        device = self.devices.get(headers.get("X-Device-Id", ""))
        timestamp = headers.get("X-Timestamp", "")
        signature = headers.get("X-Signature", "")
        if device is None:
            raise AuthError("Enheden er ikke forbundet til Home Assistant.")
        try:
            age = abs(time.time() - int(timestamp))
        except ValueError as err:
            raise AuthError("Mangler tidsstempel.") from err
        if age > SIGNATURE_MAX_AGE.total_seconds():
            raise AuthError("Enhedens ur går forkert, eller forespørgslen er for gammel.")
        expected = sign(device["key"], timestamp, method, path, body)
        if not hmac.compare_digest(expected, signature):
            raise AuthError("Ugyldig signatur.")
        return device

    @callback
    def async_device_seen(self, device: dict[str, Any], headers: dict[str, str]) -> None:
        """Husker hvornår enheden sidst var i kontakt, og dens app-version."""
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
        """Holder enhederne i takt med integrationens "Enheder" (subentries).

        En slettet subentry tilbagekalder enhedens nøgle med det samme.
        Navn, rolle og barn følger subentry'en.
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
        # En enhed kan være parret, før "Tilføj enhed" er gjort færdig i HA.
        pending = {p["deviceId"] for p in self.pairings.values()}
        for device_id in list(self.devices):
            subentry = subentries.get(device_id)
            device = self.devices[device_id]
            if subentry is None:
                # Enheden er fjernet i HA - eller parringen blev aldrig gjort
                # færdig og linket er udløbet.
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
