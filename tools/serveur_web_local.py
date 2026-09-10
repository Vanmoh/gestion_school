#!/usr/bin/env python3
"""Sert le build web: compresse, et jamais perime.

Ce serveur remplace `no_cache_static_server.py`, qui envoyait
`Cache-Control: no-store` sur tout. Le motif etait bon -- ne jamais voir un
ecran d'hier apres un rebuild -- mais le remede coutait cher: le navigateur
retelechargeait `main.dart.js` (6,5 Mo) et les polices (2,2 Mo) a **chaque**
ouverture, sans compression. D'ou les vingt secondes avant le premier ecran.

Deux corrections, qui gardent la garantie d'origine:

1. **Revalidation plutot que rejet.** `Cache-Control: no-cache` ne veut pas
   dire « ne garde rien » mais « garde, et demande-moi avant de t'en servir ».
   Le navigateur envoie alors `If-None-Match` avec l'empreinte du fichier
   qu'il detient; si rien n'a change, la reponse est un `304` de quelques
   octets. Un rebuild change l'empreinte, et le fichier repart en entier: les
   modifications restent visibles immediatement, ce que `no-store` protegeait.

2. **Compression gzip.** Le JavaScript et les polices se compriment d'un
   facteur quatre a cinq. Les images et l'archive CanvasKit sont deja
   compressees: les repasser en gzip coute du temps processeur pour rien.

Ce qui n'est pas fait, et pourquoi: aucune duree de cache n'est posee
(`max-age`). Sur un serveur de classe, ou l'on rebuild pour montrer une
correction dans la minute, un fichier garde sans question est precisement ce
qu'il ne faut pas.
"""

from __future__ import annotations

import argparse
import functools
import gzip
import hashlib
import io
import os
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

# En deca, l'en-tete et le temps processeur coutent plus que ce qu'on
# economise.
TAILLE_MINIMALE_POUR_COMPRESSER = 1024

# Types deja compresses: y repasser du gzip ne gagne rien et retarde la
# reponse.
TYPES_INCOMPRESSIBLES = (
    "image/",
    "video/",
    "audio/",
    "font/woff",
    "application/zip",
    "application/gzip",
    "application/wasm",
)


class GestionnaireWeb(SimpleHTTPRequestHandler):
    """Sert un fichier avec son empreinte, compresse quand c'est utile."""

    protocol_version = "HTTP/1.1"

    def _empreinte(self, chemin: str) -> str:
        """Identifie le contenu servi.

        Taille et date de modification suffisent: un rebuild reecrit le
        fichier, donc au moins l'une des deux bouge. Lire 6,5 Mo pour en
        calculer le hachage a chaque requete couterait plus que ce que le
        cache fait gagner.
        """
        etat = os.stat(chemin)
        graine = f"{etat.st_size}-{int(etat.st_mtime)}".encode("utf-8")
        return '"' + hashlib.md5(graine).hexdigest() + '"'

    def _compressible(self, type_mime: str, taille: int) -> bool:
        if taille < TAILLE_MINIMALE_POUR_COMPRESSER:
            return False
        if type_mime.startswith(TYPES_INCOMPRESSIBLES):
            return False
        return "gzip" in self.headers.get("Accept-Encoding", "")

    def send_head(self):
        chemin = self.translate_path(self.path)
        if os.path.isdir(chemin):
            # Les redirections et l'index restent l'affaire de la classe mere.
            return super().send_head()
        if not os.path.isfile(chemin):
            self.send_error(404, "File not found")
            return None

        empreinte = self._empreinte(chemin)

        # Le navigateur a deja ce fichier: on le lui confirme en quelques
        # octets au lieu de le renvoyer.
        if self.headers.get("If-None-Match") == empreinte:
            self.send_response(304)
            self.send_header("ETag", empreinte)
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return None

        type_mime = self.guess_type(chemin)
        try:
            contenu = open(chemin, "rb").read()
        except OSError:
            self.send_error(404, "File not found")
            return None

        if self._compressible(type_mime, len(contenu)):
            contenu = gzip.compress(contenu, compresslevel=6)
            encodage = "gzip"
        else:
            encodage = ""

        self.send_response(200)
        self.send_header("Content-Type", type_mime)
        self.send_header("Content-Length", str(len(contenu)))
        self.send_header("ETag", empreinte)
        # « no-cache » et non « no-store »: garde le fichier, mais demande
        # avant de t'en servir.
        self.send_header("Cache-Control", "no-cache")
        if encodage:
            self.send_header("Content-Encoding", encodage)
            # Sans cela, un proxy pourrait servir la version compressee a un
            # client qui ne l'accepte pas.
            self.send_header("Vary", "Accept-Encoding")
        self.end_headers()
        return io.BytesIO(contenu)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Sert le build web, compresse et toujours a jour"
    )
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--directory", default=".")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    gestionnaire = functools.partial(GestionnaireWeb, directory=args.directory)
    serveur = ThreadingHTTPServer((args.host, args.port), gestionnaire)
    print(
        f"Sert {args.directory} sur http://{args.host}:{args.port} "
        "(gzip + revalidation)"
    )
    serveur.serve_forever()


if __name__ == "__main__":
    main()
