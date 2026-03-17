import re

_ALLOWED_TERMS = {"T1", "T2", "T3"}
_DIGIT_PATTERN = re.compile(r"^[123]$")


def normalize_term(value) -> str:
    """Return canonical term value (T1/T2/T3) or empty string when invalid."""
    raw = str(value or "").strip().upper()
    if not raw:
        return ""

    if raw in _ALLOWED_TERMS:
        return raw

    if _DIGIT_PATTERN.fullmatch(raw):
        return f"T{raw}"

    if raw.startswith("TRIMESTRE"):
        suffix = raw.replace("TRIMESTRE", "", 1).strip()
        if _DIGIT_PATTERN.fullmatch(suffix):
            return f"T{suffix}"

    return ""


def is_valid_term(value) -> bool:
    return bool(normalize_term(value))
