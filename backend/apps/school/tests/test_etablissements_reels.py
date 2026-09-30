"""Les quatre ecoles ne doivent etre decrites qu'une fois.

Elles l'etaient trois fois -- la migration de semis, `insert_etablissements`,
`insert_classes.ESTABLISSEMENT_CLASSES` -- et les trois listes ne concordaient
pas. Un seul nom leur etait commun, « IFP-OBK »: enchainer la migration et la
commande creait donc **sept** lignes pour quatre ecoles.

Aucun test ne pouvait le voir, parce que chaque liste etait coherente avec
elle-meme. Ces tests portent sur leur **accord**, qui est la seule chose que
personne ne verifiait.
"""

import io
import re
from pathlib import Path

from django.test import SimpleTestCase

from apps.school.etablissements_reels import (
    ETABLISSEMENTS_REELS,
    NOMS_CONNUS,
    PAR_CODE,
    cle_de_nom,
    code_de,
)
from apps.school.management.commands.insert_classes import ESTABLISSEMENT_CLASSES

RACINE = Path(__file__).resolve().parents[1]


class LesTroisListesConcordentTests(SimpleTestCase):
    def test_la_migration_recopie_les_noms_canoniques(self):
        """La copie figee de la migration doit rester une copie.

        Elle n'importe pas `ETABLISSEMENTS_REELS`: une migration doit se rejouer
        a l'identique dans dix ans, alors que le module vivra. Le prix de cette
        prudence est une duplication, et ce test est ce qui la rend sure.

        L'ordre compte aussi: sur une base neuve, les identifiants suivent
        l'ordre d'insertion, donc 1, 2, 3, 4.
        """
        source = io.open(
            RACINE / "migrations" / "9999_insert_etablissements.py", encoding="utf-8"
        ).read()
        bloc = source[source.index("ETABLISSEMENTS = [") :]
        bloc = bloc[: bloc.index("]")]
        noms = re.findall(r'^\s+"([^"]+)",', bloc, re.M)

        self.assertEqual(noms, [ecole["nom"] for ecole in ETABLISSEMENTS_REELS])

    def test_les_noms_donnent_les_codes_canoniques(self):
        """Le semis ne pose pas les codes: c'est `0047` qui les derive.

        `Etablissement.code` n'existe pas encore au point du graphe ou le semis
        tourne -- `0011` et `0017` en dependent, et dependre de `0047` ferait un
        cycle. Les codes viennent donc des initiales des deux premiers mots du
        nom.

        Ce test est le maillon qui rend ce detour sur: retoucher un nom canonique
        changerait le code de l'ecole, et le code compose les matricules deja
        imprimes sur les cartes des eleves.
        """
        import re as expressions
        import unicodedata

        def initiales(nom):
            decompose = unicodedata.normalize("NFD", nom or "")
            sans = "".join(
                c for c in decompose if unicodedata.category(c) != "Mn"
            )
            mots = expressions.findall(r"[A-Z0-9]+", sans.upper())
            if len(mots) >= 2:
                return "".join(mot[0] for mot in mots[:2])
            return mots[0][:2] if mots else "GS"

        for ecole in ETABLISSEMENTS_REELS:
            self.assertEqual(
                initiales(ecole["nom"]),
                ecole["code"],
                f"« {ecole['nom'] } » donnerait le code {initiales(ecole['nom'])} "
                f"et non {ecole['code']}",
            )

    def test_chaque_ecole_a_sa_liste_de_classes(self):
        """Le `sigle` est la cle de `ESTABLISSEMENT_CLASSES`: il doit y exister.

        Sans quoi la dotation ne trouve aucune classe pour cette ecole et la
        passe en silence -- c'est ce qui est arrive au LOBK.
        """
        for ecole in ETABLISSEMENTS_REELS:
            self.assertIn(
                ecole["sigle"],
                ESTABLISSEMENT_CLASSES,
                f"{ecole['code']} designe le sigle « {ecole['sigle']} », absent "
                "de ESTABLISSEMENT_CLASSES",
            )

    def test_le_code_est_un_alias_de_sa_liste_de_classes(self):
        """Le code est le seul identifiant stable: le rapprochement doit y tenir.

        Les noms derivent -- quelqu'un a saisi « LYCCE OBK » a la main. Le code,
        lui, compose les matricules deja distribues et ne bouge pas.
        """
        for ecole in ETABLISSEMENTS_REELS:
            alias = {
                a.strip().lower()
                for a in ESTABLISSEMENT_CLASSES[ecole["sigle"]]["aliases"]
            }
            self.assertIn(ecole["code"].lower(), alias)

    def test_le_nom_canonique_porte_son_sigle_ou_l_est(self):
        """`_classes_de` cherche d'abord un sigle entre parentheses.

        C'est ce qui distingue « Lycee Technique Oumar Bah (LTOB) » de
        « ... (LOBK) », deux ecoles dont les noms ne different que par la.
        """
        for ecole in ETABLISSEMENTS_REELS:
            sigles = {s.lower() for s in re.findall(r"\(([^)]+)\)", ecole["nom"])}
            self.assertTrue(
                ecole["sigle"].lower() in sigles
                or ecole["nom"].lower() == ecole["sigle"].lower(),
                f"« {ecole['nom']} » ne porte pas le sigle {ecole['sigle']}",
            )


class LaReconnaissanceDUneEcoleTests(SimpleTestCase):
    class Ligne:
        def __init__(self, name="", code=""):
            self.name = name
            self.code = code

    def test_le_code_prime_sur_le_nom(self):
        """Un nom peut mentir, un code non.

        Une ecole dont quelqu'un a saisi le nom d'une autre reste reconnue par
        son code -- et c'est heureux, puisque c'est son code qui est imprime
        sur les matricules de ses eleves.
        """
        self.assertEqual(
            code_de(self.Ligne(name="Complexe Scolaire Oumar Bah", code="LO")), "LO"
        )

    def test_chaque_nom_canonique_se_reconnait(self):
        for ecole in ETABLISSEMENTS_REELS:
            self.assertEqual(code_de(self.Ligne(name=ecole["nom"])), ecole["code"])

    def test_les_noms_historiques_se_reconnaissent(self):
        """Les deux listes d'origine, et la saisie a la main constatee.

        « LYCCE OBK » est celle qui a coute le plus cher: elle a rendu une ecole
        invisible au controle sans que rien ne le signale.
        """
        for nom, code in (
            ("Lycée Technique Oumar Bah (LTOB)", "LT"),
            ("Lycée Technique Oumar Bah (LOBK)", "LO"),
            ("Complexe Scolaire Omar Bah (CSOB)", "CS"),
            ("LYCCE OBK", "LO"),
            ("LYCEE TECHNIQUE OUMAR BAH", "LT"),
            ("Lycée Oumar Bah de Kaloum", "LO"),
        ):
            self.assertEqual(code_de(self.Ligne(name=nom)), code, nom)

    def test_une_ecole_etrangere_n_est_pas_reconnue(self):
        """Le rattachement ne doit rien inventer.

        Une cinquieme ecole doit rester elle-meme: `normaliser_les_etablissements`
        la laisse tranquille parce que `code_de` rend `None`.
        """
        self.assertIsNone(code_de(self.Ligne(name="École privée du Centre", code="PC")))

    def test_l_accent_ne_change_rien(self):
        self.assertEqual(
            cle_de_nom("Lycée Oumar Bah de Kaloum"), "lycee oumar bah de kaloum"
        )

    def test_aucun_nom_connu_ne_designe_deux_ecoles(self):
        """Deux codes pour un meme nom rendraient la reconnaissance arbitraire."""
        self.assertEqual(len(NOMS_CONNUS), len(set(NOMS_CONNUS)))
        for nom, code in NOMS_CONNUS.items():
            self.assertIn(code, PAR_CODE, nom)
