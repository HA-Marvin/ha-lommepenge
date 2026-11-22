"""Texts in the integration's languages.

The language is chosen when the integration is set up (`CONF_LANGUAGE`) and
never taken from HA's language. Entity names come from
`translations/<language>.json` (see `async_entity_names`); this module also
covers what the integration writes on its own: error messages shown in the
app, restriction reasons, notification texts for the blueprints and the
install page. The app sends its own chosen language with every request, so
its messages follow the app.
"""

from __future__ import annotations

from typing import Any

from homeassistant.core import HomeAssistant
from homeassistant.helpers import translation

from .const import DEFAULT_CURRENCY, DEFAULT_LANGUAGE, DOMAIN, LANGUAGES

MESSAGES: dict[str, dict[str, str]] = {
    # ---- Errors shown in the app ---------------------------------------------
    "not_set_up": {
        "en": "Lommepenge is not set up in Home Assistant.",
        "da": "Lommepenge er ikke sat op i Home Assistant.",
        "de": "Lommepenge ist in Home Assistant nicht eingerichtet.",
        "es": "Lommepenge no está configurado en Home Assistant.",
        "fr": "Lommepenge n'est pas configuré dans Home Assistant.",
    },
    "local_only": {
        "en": "Only available on the home network.",
        "da": "Kun tilgængelig på hjemmenettet.",
        "de": "Nur im Heimnetz verfügbar.",
        "es": "Solo disponible en la red de casa.",
        "fr": "Disponible uniquement sur le réseau domestique.",
    },
    "invalid_request": {
        "en": "Invalid request.",
        "da": "Ugyldig forespørgsel.",
        "de": "Ungültige Anfrage.",
        "es": "Solicitud no válida.",
        "fr": "Requête non valide.",
    },
    "invalid_action": {
        "en": "Invalid action.",
        "da": "Ugyldig handling.",
        "de": "Ungültige Aktion.",
        "es": "Acción no válida.",
        "fr": "Action non valide.",
    },
    "request_too_large": {
        "en": "Request too large.",
        "da": "For stor forespørgsel.",
        "de": "Anfrage zu groß.",
        "es": "Solicitud demasiado grande.",
        "fr": "Requête trop volumineuse.",
    },
    "link_expired": {
        "en": "The link has expired.",
        "da": "Linket er udløbet.",
        "de": "Der Link ist abgelaufen.",
        "es": "El enlace ha caducado.",
        "fr": "Le lien a expiré.",
    },
    "app_not_fetched": {
        "en": "Home Assistant has not fetched the app yet.",
        "da": "Home Assistant har ikke hentet appen endnu.",
        "de": "Home Assistant hat die App noch nicht abgerufen.",
        "es": "Home Assistant todavía no ha descargado la app.",
        "fr": "Home Assistant n'a pas encore récupéré l'application.",
    },
    "app_fetch_failed": {
        "en": "Could not fetch the app from GitHub.",
        "da": "Kunne ikke hente appen fra GitHub.",
        "de": "Die App konnte nicht von GitHub abgerufen werden.",
        "es": "No se pudo descargar la app de GitHub.",
        "fr": "Impossible de récupérer l'application sur GitHub.",
    },
    "forbidden_action": {
        "en": "This device is not allowed to perform this action.",
        "da": "Denne enhed må ikke udføre handlingen.",
        "de": "Dieses Gerät darf diese Aktion nicht ausführen.",
        "es": "Este dispositivo no puede realizar esta acción.",
        "fr": "Cet appareil n'est pas autorisé à effectuer cette action.",
    },
    "device_not_connected": {
        "en": "The device is not connected to Home Assistant.",
        "da": "Enheden er ikke forbundet til Home Assistant.",
        "de": "Das Gerät ist nicht mit Home Assistant verbunden.",
        "es": "El dispositivo no está conectado a Home Assistant.",
        "fr": "L'appareil n'est pas connecté à Home Assistant.",
    },
    "missing_timestamp": {
        "en": "Missing timestamp.",
        "da": "Mangler tidsstempel.",
        "de": "Zeitstempel fehlt.",
        "es": "Falta la marca de tiempo.",
        "fr": "Horodatage manquant.",
    },
    "clock_skew": {
        "en": "The device's clock is wrong, or the request is too old.",
        "da": "Enhedens ur går forkert, eller forespørgslen er for gammel.",
        "de": "Die Uhr des Geräts geht falsch, oder die Anfrage ist zu alt.",
        "es": "El reloj del dispositivo no es correcto o la solicitud es demasiado antigua.",
        "fr": "L'horloge de l'appareil est incorrecte, ou la requête est trop ancienne.",
    },
    "invalid_signature": {
        "en": "Invalid signature.",
        "da": "Ugyldig signatur.",
        "de": "Ungültige Signatur.",
        "es": "Firma no válida.",
        "fr": "Signature non valide.",
    },
    "too_many_pairings": {
        "en": "Too many wrong codes. Wait five minutes and try again.",
        "da": "For mange forkerte koder. Vent fem minutter, og prøv igen.",
        "de": "Zu viele falsche Codes. Warte fünf Minuten und versuche es erneut.",
        "es": "Demasiados códigos incorrectos. Espera cinco minutos e inténtalo de nuevo.",
        "fr": "Trop de codes erronés. Attends cinq minutes et réessaie.",
    },
    "pairing_invalid": {
        "en": (
            "The code is wrong, expired or already used. Create a new one under "
            "Lommepenge → Add device in Home Assistant."
        ),
        "da": (
            "Koden er forkert, udløbet eller allerede brugt. Lav en ny under "
            "Lommepenge → Tilføj enhed i Home Assistant."
        ),
        "de": (
            "Der Code ist falsch, abgelaufen oder bereits verwendet. Erstelle einen "
            "neuen unter Lommepenge → Gerät hinzufügen in Home Assistant."
        ),
        "es": (
            "El código es incorrecto, ha caducado o ya se ha usado. Crea uno nuevo en "
            "Lommepenge → Añadir dispositivo en Home Assistant."
        ),
        "fr": (
            "Le code est erroné, expiré ou déjà utilisé. Crée-en un nouveau sous "
            "Lommepenge → Ajouter un appareil dans Home Assistant."
        ),
    },
    # ---- Family actions --------------------------------------------------------
    "missing_field": {
        "en": "The action is missing a valid {field}.",
        "da": "Handlingen mangler et gyldigt {field}.",
        "de": "Der Aktion fehlt ein gültiges {field}.",
        "es": "A la acción le falta un {field} válido.",
        "fr": "Il manque un {field} valide à l'action.",
    },
    "unknown_action": {
        "en": "Unknown action: {action}",
        "da": "Ukendt handling: {action}",
        "de": "Unbekannte Aktion: {action}",
        "es": "Acción desconocida: {action}",
        "fr": "Action inconnue : {action}",
    },
    "task_title_required": {
        "en": "The task must have a title.",
        "da": "Opgaven skal have en titel.",
        "de": "Die Aufgabe braucht einen Titel.",
        "es": "La tarea debe tener un título.",
        "fr": "La tâche doit avoir un titre.",
    },
    "negative_amount": {
        "en": "The amount cannot be negative.",
        "da": "Beløbet kan ikke være negativt.",
        "de": "Der Betrag darf nicht negativ sein.",
        "es": "El importe no puede ser negativo.",
        "fr": "Le montant ne peut pas être négatif.",
    },
    "missing_id": {
        "en": "The action is missing an id.",
        "da": "Handlingen mangler et id.",
        "de": "Der Aktion fehlt eine ID.",
        "es": "A la acción le falta un id.",
        "fr": "Il manque un identifiant à l'action.",
    },
    "task_not_found": {
        "en": "The task no longer exists.",
        "da": "Opgaven findes ikke længere.",
        "de": "Die Aufgabe existiert nicht mehr.",
        "es": "La tarea ya no existe.",
        "fr": "La tâche n'existe plus.",
    },
    "missing_child_id": {
        "en": "The action does not say which child it is for (childId).",
        "da": "Handlingen mangler oplysning om hvilket barn (childId).",
        "de": "Der Aktion fehlt die Angabe, für welches Kind sie gilt (childId).",
        "es": "La acción no indica a qué niño corresponde (childId).",
        "fr": "L'action n'indique pas pour quel enfant elle est (childId).",
    },
    "missing_task": {
        "en": "The action is missing a task.",
        "da": "Handlingen mangler en opgave.",
        "de": "Der Aktion fehlt eine Aufgabe.",
        "es": "A la acción le falta una tarea.",
        "fr": "Il manque une tâche à l'action.",
    },
    "task_not_assigned": {
        "en": "The task is not assigned to this child.",
        "da": "Opgaven er ikke tildelt dette barn.",
        "de": "Die Aufgabe ist diesem Kind nicht zugewiesen.",
        "es": "La tarea no está asignada a este niño.",
        "fr": "La tâche n'est pas attribuée à cet enfant.",
    },
    "task_not_available": {
        "en": "The task cannot be marked as done right now.",
        "da": "Opgaven kan ikke markeres udført lige nu.",
        "de": "Die Aufgabe kann gerade nicht als erledigt markiert werden.",
        "es": "La tarea no se puede marcar como hecha ahora mismo.",
        "fr": "La tâche ne peut pas être marquée comme faite pour le moment.",
    },
    "missing_completion": {
        "en": "The action is missing a completion.",
        "da": "Handlingen mangler en udførelse.",
        "de": "Der Aktion fehlt eine Erledigung.",
        "es": "A la acción le falta una realización.",
        "fr": "Il manque une réalisation à l'action.",
    },
    "completion_not_found": {
        "en": "The completion does not exist.",
        "da": "Udførelsen findes ikke.",
        "de": "Die Erledigung existiert nicht.",
        "es": "La realización no existe.",
        "fr": "La réalisation n'existe pas.",
    },
    "completion_already_handled": {
        "en": "The completion has already been handled.",
        "da": "Udførelsen er allerede behandlet.",
        "de": "Die Erledigung wurde bereits bearbeitet.",
        "es": "La realización ya se ha gestionado.",
        "fr": "La réalisation a déjà été traitée.",
    },
    "child_not_found": {
        "en": "The child no longer exists.",
        "da": "Barnet findes ikke længere.",
        "de": "Das Kind existiert nicht mehr.",
        "es": "El niño ya no existe.",
        "fr": "L'enfant n'existe plus.",
    },
    "adjustment_note_required": {
        "en": "A balance adjustment must have a note.",
        "da": "En saldo-justering skal have en note.",
        "de": "Eine Guthabenkorrektur braucht eine Notiz.",
        "es": "Un ajuste de saldo debe tener una nota.",
        "fr": "Un ajustement de solde doit avoir une note.",
    },
    "child_name_required": {
        "en": "The child's name cannot be empty.",
        "da": "Barnets navn må ikke være tomt.",
        "de": "Der Name des Kindes darf nicht leer sein.",
        "es": "El nombre del niño no puede estar vacío.",
        "fr": "Le nom de l'enfant ne peut pas être vide.",
    },
    "missing_setting": {
        "en": "The action is missing a setting.",
        "da": "Handlingen mangler en indstilling.",
        "de": "Der Aktion fehlt eine Einstellung.",
        "es": "A la acción le falta un ajuste.",
        "fr": "Il manque un paramètre à l'action.",
    },
    "invalid_time": {
        "en": "Invalid time for {key}: {value}",
        "da": "Ugyldigt klokkeslæt for {key}: {value}",
        "de": "Ungültige Uhrzeit für {key}: {value}",
        "es": "Hora no válida para {key}: {value}",
        "fr": "Heure non valide pour {key} : {value}",
    },
    "setting_out_of_range": {
        "en": "{key} must be between {minimum} and {maximum}: {value}",
        "da": "{key} skal være mellem {minimum} og {maximum}: {value}",
        "de": "{key} muss zwischen {minimum} und {maximum} liegen: {value}",
        "es": "{key} debe estar entre {minimum} y {maximum}: {value}",
        "fr": "{key} doit être compris entre {minimum} et {maximum} : {value}",
    },
    "unknown_setting": {
        "en": "Unknown setting: {key}",
        "da": "Ukendt indstilling: {key}",
        "de": "Unbekannte Einstellung: {key}",
        "es": "Ajuste desconocido: {key}",
        "fr": "Paramètre inconnu : {key}",
    },
    # ---- Restriction reason (sensor attribute and event) -----------------------
    "reason_overdue": {
        "en": "Missing: {tasks}",
        "da": "Mangler: {tasks}",
        "de": "Fehlt: {tasks}",
        "es": "Falta: {tasks}",
        "fr": "Manquant : {tasks}",
    },
    "reason_overdue_task": {
        "en": "{title} (due {due})",
        "da": "{title} (frist {due})",
        "de": "{title} (fällig {due})",
        "es": "{title} (límite {due})",
        "fr": "{title} (échéance {due})",
    },
    "reason_late": {
        "en": "The task was done late - unlocks at {until}",
        "da": "Opgaven er udført for sent - låses op kl. {until}",
        "de": "Die Aufgabe wurde zu spät erledigt - wird um {until} entsperrt",
        "es": "La tarea se hizo tarde - se desbloquea a las {until}",
        "fr": "La tâche a été faite en retard - déblocage à {until}",
    },
    # ---- Notification texts (event data for the blueprints) ---------------------
    "notify_completion": {
        "en": '{child} did "{task}" – {amount}',
        "da": '{child} har lavet "{task}" – {amount}',
        "de": '{child} hat "{task}" erledigt – {amount}',
        "es": '{child} ha hecho "{task}" – {amount}',
        "fr": '{child} a fait « {task} » – {amount}',
    },
    "notify_late": {
        "en": " (late)",
        "da": " (for sent)",
        "de": " (zu spät)",
        "es": " (tarde)",
        "fr": " (en retard)",
    },
    # ---- Roles and device models --------------------------------------------------
    "role_screen": {
        "en": "Family screen",
        "da": "Fælles skærm",
        "de": "Familienbildschirm",
        "es": "Pantalla familiar",
        "fr": "Écran familial",
    },
    "role_parent": {
        "en": "Parent",
        "da": "Forælder",
        "de": "Elternteil",
        "es": "Padre/madre",
        "fr": "Parent",
    },
    "role_child": {
        "en": "Child's tablet",
        "da": "Barnets tablet",
        "de": "Tablet des Kindes",
        "es": "Tableta del niño",
        "fr": "Tablette de l'enfant",
    },
    "model_family": {
        "en": "Family",
        "da": "Familie",
        "de": "Familie",
        "es": "Familia",
        "fr": "Famille",
    },
    "model_child": {
        "en": "Child",
        "da": "Barn",
        "de": "Kind",
        "es": "Niño",
        "fr": "Enfant",
    },
    # ---- Install page ----------------------------------------------------------
    "page_no_app": {
        "en": "Home Assistant has not been able to fetch the app from GitHub yet. Try again shortly.",
        "da": "Home Assistant har ikke kunnet hente appen fra GitHub endnu. Prøv igen om lidt.",
        "de": "Home Assistant konnte die App noch nicht von GitHub abrufen. Versuche es gleich noch einmal.",
        "es": "Home Assistant todavía no ha podido descargar la app de GitHub. Inténtalo de nuevo en un momento.",
        "fr": "Home Assistant n'a pas encore pu récupérer l'application sur GitHub. Réessaie dans un instant.",
    },
    "page_download": {
        "en": "Download the app (.apk, version {version})",
        "da": "Hent appen (.apk, version {version})",
        "de": "App herunterladen (.apk, Version {version})",
        "es": "Descargar la app (.apk, versión {version})",
        "fr": "Télécharger l'application (.apk, version {version})",
    },
    "page_download_hint": {
        "en": (
            "If the device has no browser, download the file on this computer and "
            "move it over, e.g. with a USB cable. Android asks once whether the app "
            "may be installed."
        ),
        "da": (
            "Har enheden ingen browser, så hent filen her på computeren og flyt den "
            "over, fx med et USB-kabel. Android spørger én gang, om appen må "
            "installeres."
        ),
        "de": (
            "Hat das Gerät keinen Browser, lade die Datei auf diesem Computer herunter "
            "und übertrage sie, z. B. mit einem USB-Kabel. Android fragt einmal, ob "
            "die App installiert werden darf."
        ),
        "es": (
            "Si el dispositivo no tiene navegador, descarga el archivo en este "
            "ordenador y pásalo, por ejemplo con un cable USB. Android pregunta una "
            "vez si se puede instalar la app."
        ),
        "fr": (
            "Si l'appareil n'a pas de navigateur, télécharge le fichier sur cet "
            "ordinateur et transfère-le, par exemple avec un câble USB. Android "
            "demande une fois si l'application peut être installée."
        ),
    },
    "page_add_device": {
        "en": "Add a device",
        "da": "Tilføj en enhed",
        "de": "Ein Gerät hinzufügen",
        "es": "Añadir un dispositivo",
        "fr": "Ajouter un appareil",
    },
    "page_home_step_install": {
        "en": "Install the app on the device.",
        "da": "Installér appen på enheden.",
        "de": "Installiere die App auf dem Gerät.",
        "es": "Instala la app en el dispositivo.",
        "fr": "Installe l'application sur l'appareil.",
    },
    "page_home_step_add": {
        "en": (
            "In Home Assistant: <b>Settings → Devices &amp; services → Lommepenge → "
            "Add device</b>. Choose a name and role."
        ),
        "da": (
            "I Home Assistant: <b>Indstillinger → Enheder og tjenester → Lommepenge "
            "→ Tilføj enhed</b>. Vælg navn og rolle."
        ),
        "de": (
            "In Home Assistant: <b>Einstellungen → Geräte &amp; Dienste → Lommepenge "
            "→ Gerät hinzufügen</b>. Wähle Name und Rolle."
        ),
        "es": (
            "En Home Assistant: <b>Ajustes → Dispositivos y servicios → Lommepenge → "
            "Añadir dispositivo</b>. Elige un nombre y un rol."
        ),
        "fr": (
            "Dans Home Assistant : <b>Paramètres → Appareils et services → Lommepenge "
            "→ Ajouter un appareil</b>. Choisis un nom et un rôle."
        ),
    },
    "page_home_step_code": {
        "en": (
            "Open the app on the device and enter the code Home Assistant shows - or "
            "scan the QR code if the device has a camera."
        ),
        "da": (
            "Åbn appen på enheden, og tast koden, som Home Assistant viser - eller "
            "scan QR-koden, hvis enheden har kamera."
        ),
        "de": (
            "Öffne die App auf dem Gerät und gib den Code ein, den Home Assistant "
            "anzeigt - oder scanne den QR-Code, wenn das Gerät eine Kamera hat."
        ),
        "es": (
            "Abre la app en el dispositivo e introduce el código que muestra Home "
            "Assistant, o escanea el código QR si el dispositivo tiene cámara."
        ),
        "fr": (
            "Ouvre l'application sur l'appareil et saisis le code affiché par Home "
            "Assistant - ou scanne le code QR si l'appareil a une caméra."
        ),
    },
    "page_code_used_title": {
        "en": "The code is used or expired",
        "da": "Koden er brugt eller udløbet",
        "de": "Der Code ist verwendet oder abgelaufen",
        "es": "El código ya se ha usado o ha caducado",
        "fr": "Le code est utilisé ou expiré",
    },
    "page_code_used_body": {
        "en": (
            "Create a new one in Home Assistant: <b>Lommepenge → Add device</b> - or "
            "<b>Reconfigure</b> on a device that already exists."
        ),
        "da": (
            "Lav en ny i Home Assistant: <b>Lommepenge → Tilføj enhed</b> - eller "
            "<b>Omkonfigurer</b> på en enhed, der allerede findes."
        ),
        "de": (
            "Erstelle einen neuen in Home Assistant: <b>Lommepenge → Gerät "
            "hinzufügen</b> - oder <b>Neu konfigurieren</b> bei einem bestehenden "
            "Gerät."
        ),
        "es": (
            "Crea uno nuevo en Home Assistant: <b>Lommepenge → Añadir "
            "dispositivo</b>, o <b>Reconfigurar</b> en un dispositivo que ya existe."
        ),
        "fr": (
            "Crée-en un nouveau dans Home Assistant : <b>Lommepenge → Ajouter un "
            "appareil</b> - ou <b>Reconfigurer</b> sur un appareil existant."
        ),
    },
    "page_open_app": {
        "en": "Open the app and connect",
        "da": "Åbn appen og forbind",
        "de": "App öffnen und verbinden",
        "es": "Abrir la app y conectar",
        "fr": "Ouvrir l'application et se connecter",
    },
    "page_open_app_hint": {
        "en": "Once the app is installed on this device.",
        "da": "Når appen er installeret på denne enhed.",
        "de": "Sobald die App auf diesem Gerät installiert ist.",
        "es": "Cuando la app esté instalada en este dispositivo.",
        "fr": "Une fois l'application installée sur cet appareil.",
    },
    "page_code_label": {
        "en": "Code",
        "da": "Kode",
        "de": "Code",
        "es": "Código",
        "fr": "Code",
    },
    "page_code_valid": {
        "en": "Valid once, until {expires}.",
        "da": "Gælder én gang, indtil kl. {expires}.",
        "de": "Einmal gültig, bis {expires} Uhr.",
        "es": "Válido una vez, hasta las {expires}.",
        "fr": "Valable une fois, jusqu'à {expires}.",
    },
    "page_how_to": {
        "en": "How to",
        "da": "Sådan gør du",
        "de": "So geht's",
        "es": "Cómo hacerlo",
        "fr": "Comment faire",
    },
    "page_step_install": {
        "en": "Install the app on the device (the button below).",
        "da": "Installér appen på enheden (knappen herunder).",
        "de": "Installiere die App auf dem Gerät (Schaltfläche unten).",
        "es": "Instala la app en el dispositivo (el botón de abajo).",
        "fr": "Installe l'application sur l'appareil (le bouton ci-dessous).",
    },
    "page_step_code": {
        "en": (
            "Open the app, choose <b>Connect with code</b> and enter the code. The "
            "app finds Home Assistant by itself."
        ),
        "da": (
            "Åbn appen, vælg <b>Forbind med kode</b>, og tast koden. Appen finder "
            "selv Home Assistant."
        ),
        "de": (
            "Öffne die App, wähle <b>Mit Code verbinden</b> und gib den Code ein. Die "
            "App findet Home Assistant von selbst."
        ),
        "es": (
            "Abre la app, elige <b>Conectar con código</b> e introduce el código. La "
            "app encuentra Home Assistant por sí sola."
        ),
        "fr": (
            "Ouvre l'application, choisis <b>Se connecter avec un code</b> et saisis "
            "le code. L'application trouve Home Assistant toute seule."
        ),
    },
    "page_step_qr": {
        "en": "If the device has a camera, it can scan the QR code instead.",
        "da": "Har enheden kamera, kan den i stedet scanne QR-koden.",
        "de": "Hat das Gerät eine Kamera, kann es stattdessen den QR-Code scannen.",
        "es": "Si el dispositivo tiene cámara, puede escanear el código QR en su lugar.",
        "fr": "Si l'appareil a une caméra, il peut scanner le code QR à la place.",
    },
    "page_step_confirm": {
        "en": "Confirm in Home Assistant once the device is connected.",
        "da": "Bekræft i Home Assistant, når enheden er forbundet.",
        "de": "Bestätige in Home Assistant, sobald das Gerät verbunden ist.",
        "es": "Confirma en Home Assistant cuando el dispositivo esté conectado.",
        "fr": "Confirme dans Home Assistant une fois l'appareil connecté.",
    },
    "page_add_title": {
        "en": "Add {name}",
        "da": "Tilføj {name}",
        "de": "{name} hinzufügen",
        "es": "Añadir {name}",
        "fr": "Ajouter {name}",
    },
}

# Languages that write amounts with a decimal comma.
_DECIMAL_COMMA = {"da", "de", "es", "fr"}


def normalize_language(value: Any) -> str | None:
    """A supported language from e.g. `da`, `da-DK` or a list like
    `de-DE,de;q=0.9,en;q=0.8`, or `None`."""
    if not isinstance(value, str):
        return None
    for part in value.split(","):
        code = part.split(";")[0].strip().lower().replace("_", "-").split("-")[0]
        if code in LANGUAGES:
            return code
    return None


def translate(key: str, language: str | None = None, /, **params: Any) -> str:
    """The text `key` in `language` (English if missing), with `params`."""
    texts = MESSAGES[key]
    text = texts.get(language or DEFAULT_LANGUAGE) or texts[DEFAULT_LANGUAGE]
    return text.format(**params) if params else text


def format_amount(
    amount_ore: int, language: str | None = None, currency: str = DEFAULT_CURRENCY
) -> str:
    """An amount in 1/100 of the currency as e.g. `12.50 DKK` / `12,50 €`
    (no decimals when whole)."""
    sign = "-" if amount_ore < 0 else ""
    whole, rest = divmod(abs(amount_ore), 100)
    if rest == 0:
        return f"{sign}{whole} {currency}"
    separator = "," if language in _DECIMAL_COMMA else "."
    return f"{sign}{whole}{separator}{rest:02d} {currency}"


async def async_entity_names(hass: HomeAssistant, language: str) -> dict[str, str]:
    """Entity names (translation key -> name) in the integration's language.

    The names come from the same `translations/<language>.json` that HA uses,
    but in the language chosen for the integration instead of HA's own,
    which is often English in a family that wants e.g. Danish.
    """
    translations = await translation.async_get_translations(
        hass, language, "entity", {DOMAIN}
    )
    names: dict[str, str] = {}
    for path, name in translations.items():
        # component.lommepenge.entity.<platform>.<key>.name
        parts = path.split(".")
        if len(parts) == 6 and parts[2] == "entity" and parts[5] == "name":
            names[parts[4]] = name
    return names


class LocalizedError(Exception):
    """An error whose message is translated where it is shown.

    `str(err)` is the English text (for logs); `err.translate(language)` is
    the text for the user.
    """

    def __init__(self, key: str, /, **params: Any) -> None:
        super().__init__(translate(key, DEFAULT_LANGUAGE, **params))
        self.key = key
        self.params = params

    def translate(self, language: str | None) -> str:
        return translate(self.key, language, **self.params)
