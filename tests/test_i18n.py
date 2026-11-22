"""Every text exists in every language, with the same placeholders."""

from __future__ import annotations

import json
from pathlib import Path
from string import Formatter

from custom_components.lommepenge.const import LANGUAGES
from custom_components.lommepenge.i18n import MESSAGES, format_amount, normalize_language

COMPONENT = Path(__file__).parent.parent / "custom_components" / "lommepenge"


def _placeholders(text: str) -> set[str]:
    return {name for _, name, _, _ in Formatter().parse(text) if name}


def _keys(tree: dict, prefix: str = "") -> set[str]:
    keys: set[str] = set()
    for key, value in tree.items():
        path = f"{prefix}.{key}" if prefix else key
        keys |= _keys(value, path) if isinstance(value, dict) else {path}
    return keys


def test_messages_complete() -> None:
    for key, texts in MESSAGES.items():
        assert set(texts) == set(LANGUAGES), key
        expected = _placeholders(texts["en"])
        for language, text in texts.items():
            assert _placeholders(text) == expected, f"{key}/{language}"


def test_ha_translations_complete() -> None:
    strings = json.loads((COMPONENT / "strings.json").read_text(encoding="utf-8"))
    expected = _keys(strings)
    for language in LANGUAGES:
        path = COMPONENT / "translations" / f"{language}.json"
        translation = json.loads(path.read_text(encoding="utf-8"))
        assert _keys(translation) == expected, language
    assert json.loads((COMPONENT / "translations" / "en.json").read_text(encoding="utf-8")) == strings


def test_normalize_language() -> None:
    assert normalize_language("da") == "da"
    assert normalize_language("de-DE,de;q=0.9,en;q=0.8") == "de"
    assert normalize_language("pt-BR,es;q=0.5") == "es"
    assert normalize_language("pt-BR") is None
    assert normalize_language(None) is None


def test_format_amount() -> None:
    assert format_amount(500, "en") == "5 DKK"
    assert format_amount(1250, "en", "USD") == "12.50 USD"
    assert format_amount(1250, "da", "kr") == "12,50 kr"
    assert format_amount(-5, "fr", "€") == "-0,05 €"
