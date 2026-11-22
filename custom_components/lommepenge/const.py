"""Konstanter for Lommepenge-integrationen."""

from datetime import timedelta

DOMAIN = "lommepenge"

# Config entry: familiens navn og forælder-PIN (kun salt + hash gemmes).
CONF_FAMILY_NAME = "family_name"
CONF_PIN = "pin"
CONF_PIN_HASH = "pin_hash"
CONF_PIN_SALT = "pin_salt"

# Options: hvor appens versioner hentes fra. Som standard integrationens
# eget (offentlige) repo, hvor hver release også har appens APK. En nøgle
# kræves kun, hvis man bygger sin egen app i et privat repo.
CONF_GITHUB_TOKEN = "github_token"
CONF_GITHUB_REPO = "github_repo"
DEFAULT_GITHUB_REPO = "HA-Marvin/ha-lommepenge"

# Hver tablet/telefon/skærm er en config subentry af denne type.
SUBENTRY_DEVICE = "device"
CONF_DEVICE_ID = "device_id"
CONF_ROLE = "role"
CONF_CHILD_ID = "child_id"
CONF_NAME = "name"

# Roller. En barne-tablet ser kun ét barn og kan kun markere dets opgaver
# udført; skærm og forælder har fuld adgang (forælder-delen er PIN-låst i
# appen).
ROLE_SCREEN = "screen"
ROLE_PARENT = "parent"
ROLE_CHILD = "child"
ROLES = (ROLE_SCREEN, ROLE_PARENT, ROLE_CHILD)

API_PREFIX = "/api/lommepenge"

# Et parringslink (QR-kode) virker så længe og kun til én enhed.
PAIRING_TTL = timedelta(minutes=15)
# En signeret forespørgsel må højst være så gammel (mod genafspilning).
SIGNATURE_MAX_AGE = timedelta(minutes=5)

# Opfølgningen genberegnes jævnligt, fordi frister passerer uden at data
# ændrer sig.
FOLLOW_UP_INTERVAL = timedelta(seconds=30)
RELEASE_CHECK_INTERVAL = timedelta(hours=6)

# Hændelse på HA's event-bus (completion_pending, completion_approved,
# completion_rejected, restriction_changed). Bruges af blueprints.
EVENT_LOMMEPENGE = "lommepenge_event"

SERVICE_APPROVE = "approve"
SERVICE_REJECT = "reject"
SERVICE_SUSPEND_RESTRICTION = "suspend_restriction"

ATTR_COMPLETION_ID = "completion_id"
ATTR_CHILD_ID = "child_id"
