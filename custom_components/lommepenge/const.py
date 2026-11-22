"""Konstanter for Lommepenge-integrationen."""

from datetime import timedelta

DOMAIN = "lommepenge"

DEFAULT_PORT = 8087

CONF_TOKEN = "token"
CONF_WEBHOOK_ID = "webhook_id"
CONF_PIN = "pin"

# Hændelse på HA's event-bus for alt hvad køleskabsskærmen melder
# (completion_pending, completion_approved, completion_rejected,
# restriction_changed). Bruges af blueprints/automationer.
EVENT_LOMMEPENGE = "lommepenge_event"

# HA henter også selv overblikket jævnligt, så en tabt webhook-besked kun
# forsinker. 60 s er billigt på LAN og gør "utilgængelig" hurtigt synlig
# (bruges af spærre-blueprintet til at ophæve spærringer, hvis skærmen er
# nede).
SCAN_INTERVAL = timedelta(seconds=60)

SERVICE_APPROVE = "approve"
SERVICE_REJECT = "reject"
SERVICE_SUSPEND_RESTRICTION = "suspend_restriction"

ATTR_COMPLETION_ID = "completion_id"
ATTR_CHILD_ID = "child_id"
ATTR_CONFIG_ENTRY_ID = "config_entry_id"
