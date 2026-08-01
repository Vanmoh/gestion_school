"""Correspondance chemin d'API -> module, deduite du routage reel.

Le client doit savoir quel module protege quelle URL pour refuser une
ecriture avant de l'envoyer. Recopier cette table dans le frontend aurait
recree la divergence qu'on vient de supprimer: elle est donc calculee ici, a
partir des vues effectivement routees, et servie avec la matrice.
"""

from __future__ import annotations

import re

from django.urls import get_resolver

from .access import MODULES

# Debut de motif purement statique: on s'arrete au premier parametre.
_DYNAMIC = re.compile(r"[<(\[?*+^$\\]")


def _static_prefix(pattern: str) -> str:
    match = _DYNAMIC.search(pattern)
    head = pattern if match is None else pattern[: match.start()]
    head = head.strip("^")
    # Les chemins sont servis relativement a la racine d'API cote client
    # (baseUrl se termine par /api), d'ou le retrait du prefixe.
    if head.startswith("api/"):
        head = head[len("api/") :]
    return "/" + head.lstrip("/")


def module_paths() -> dict[str, list[str]]:
    """{module: [prefixes d'URL]} pour toutes les vues routees."""
    found: dict[str, set[str]] = {key: set() for key in MODULES}

    def walk(patterns, prefix=""):
        for pattern in patterns:
            # Les routeurs DRF produisent des motifs regex ancres ("^grades/$"):
            # sans retirer l'ancre a chaque niveau, la partie statique serait
            # coupee des le premier caractere et tout remonterait a "/".
            current = prefix + str(pattern.pattern).lstrip("^")
            if hasattr(pattern, "url_patterns"):
                walk(pattern.url_patterns, current)
                continue
            view = getattr(pattern.callback, "cls", None) or getattr(
                pattern.callback, "view_class", None
            )
            module = getattr(view, "access_module", None)
            if module in found:
                found[module].add(_static_prefix(current))

    walk(get_resolver().url_patterns)

    # Un prefixe couvert par un prefixe plus court du meme module est
    # redondant: le client fait un match par prefixe.
    result = {}
    for module, prefixes in found.items():
        kept = sorted(
            path
            for path in prefixes
            if path != "/"
            and not any(path != other and path.startswith(other) for other in prefixes)
        )
        if kept:
            result[module] = kept
    return result
