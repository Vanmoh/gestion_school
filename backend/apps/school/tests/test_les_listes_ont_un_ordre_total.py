"""Toute liste paginee doit avoir un ordre **total**.

La pagination est globale (`StandardResultsSetPagination`, cent lignes par
page). Une liste dont l'ordre laisse des ex aequo n'est pas stable d'une page a
l'autre: la base est libre de departager comme elle veut, et elle ne le fait pas
deux fois pareil. Une ligne peut donc apparaitre deux fois, ou disparaitre entre
la page 1 et la page 2 -- sans aucune erreur, sans rien dans les journaux.

Ce n'est pas theorique ici. `doter_les_etablissements_reels` cree des milliers de
lignes dans la meme transaction: un tri sur `-created_at` seul les laisse toutes
a egalite.

Le meme genre de defaut a deja vide un ecran. « Notes & Bulletins » retenait « la
premiere annee scolaire » sans qu'aucun ordre ne soit defini, et le jour ou
PostgreSQL a reecrit une ligne -- ce qu'il fait a chaque mise a jour -- « la
premiere » est devenue l'annee suivante. L'ecran a repondu « Aucune note
enregistree » sur une base qui en comptait soixante-huit mille.

Ce test parcourt **toutes** les vues de liste du projet. Il echoue pour celle
qu'on ajoutera demain sans y penser, et c'est la sa raison d'etre: corriger les
quinze d'aujourd'hui ne protege que d'aujourd'hui.
"""

import importlib
import inspect

from django.test import SimpleTestCase
from rest_framework.generics import GenericAPIView

APPLICATIONS = ("school", "accounts", "common", "chat", "reports")

# Une vue peut legitimement n'avoir aucun depart si elle ne rend qu'une ligne,
# ou si sa liste est bornee par construction. Aucune n'est dans ce cas
# aujourd'hui; l'exemption existe pour qu'on puisse la motiver plutot que de
# desactiver le test.
EXEMPTEES: dict[str, str] = {}


def _vues_de_liste():
    vues = {}
    for application in APPLICATIONS:
        try:
            module = importlib.import_module(f"apps.{application}.views")
        except ModuleNotFoundError:
            continue
        for nom, objet in inspect.getmembers(module, inspect.isclass):
            if (
                issubclass(objet, GenericAPIView)
                and objet.__module__.startswith("apps.")
                and getattr(objet, "queryset", None) is not None
            ):
                vues[nom] = objet
    return vues


def _ordre_effectif(vue):
    """Le queryset d'abord, la vue ensuite, le modele en dernier.

    C'est l'ordre de priorite de DRF: `OrderingFilter` ne remplace l'ordre du
    queryset que si la vue declare `ordering` ou si la requete le demande.
    """
    queryset = vue.queryset
    ordre = list(getattr(queryset.query, "order_by", ()) or [])
    if ordre:
        return ordre, "queryset"
    ordre = list(getattr(vue, "ordering", None) or [])
    if ordre:
        return ordre, "vue"
    return list(queryset.model._meta.ordering or []), "modele"


def _departage(ordre):
    """Vrai si l'ordre se termine sur une colonne unique.

    `id` et `pk` sont les seules dont on sait qu'elles ne laissent jamais deux
    lignes a egalite.
    """
    return any(colonne.lstrip("-") in ("id", "pk") for colonne in ordre)


class ToutesLesListesSeDepartagentTests(SimpleTestCase):
    def test_aucune_liste_n_est_servie_sans_ordre(self):
        """Sans `ORDER BY`, la base rend les lignes dans l'ordre physique."""
        sans_ordre = [
            nom
            for nom, vue in _vues_de_liste().items()
            if nom not in EXEMPTEES and not _ordre_effectif(vue)[0]
        ]

        self.assertEqual(
            sans_ordre,
            [],
            "Ces listes n'ont aucun ordre; « la premiere ligne » n'y veut rien "
            "dire et la pagination est fausse: " + ", ".join(sorted(sans_ordre)),
        )

    def test_chaque_ordre_se_termine_par_un_depart_unique(self):
        """Un ordre qui laisse des ex aequo ne survit pas a la pagination."""
        boiteuses = []
        for nom, vue in sorted(_vues_de_liste().items()):
            if nom in EXEMPTEES:
                continue
            ordre, source = _ordre_effectif(vue)
            if ordre and not _departage(ordre):
                boiteuses.append(f"{nom} ({source}: {ordre})")

        self.assertEqual(
            boiteuses,
            [],
            "Ces listes ont un ordre sans depart final sur `id`: deux lignes a "
            "egalite peuvent permuter d'une page a l'autre, et donc se repeter "
            "ou disparaitre.\n  " + "\n  ".join(boiteuses),
        )

    def test_aucun_get_queryset_ne_perd_le_tri_declare(self):
        """Une requete reconstruite de zero ne herite pas de l'ordre.

        `TeacherAssignmentViewSet` declarait `.order_by("id")` sur son
        `queryset`, puis son `get_queryset` repartait de
        `TeacherAssignment.objects.select_related(...)`. Le tri ne suivait pas:
        la liste partait sans `ORDER BY`, et DRF le disait dans un
        `UnorderedObjectListWarning` que personne ne lisait.

        Les deux tests precedents ne pouvaient pas le voir: ils inspectent
        l'attribut `queryset`, qui restait trie. Celui-ci lit la methode.

        La regle est simple: un `get_queryset` part de `super()` -- et herite --
        ou trie lui-meme.
        """
        import inspect as introspection

        boiteuses = []
        for nom, vue in sorted(_vues_de_liste().items()):
            if nom in EXEMPTEES:
                continue
            methode = vue.__dict__.get("get_queryset")
            if methode is None:
                continue  # herite: l'ordre de `queryset` s'applique
            source = introspection.getsource(methode)
            if "super()" in source or "order_by" in source:
                continue
            boiteuses.append(nom)

        self.assertEqual(
            boiteuses,
            [],
            "Ces `get_queryset` reconstruisent la requete sans trier, et "
            "perdent l'ordre declare sur `queryset`:\n  "
            + "\n  ".join(boiteuses),
        )

    def test_le_recensement_trouve_bien_des_vues(self):
        """Garde-fou du test lui-meme.

        Si un jour l'introspection ne trouve plus rien -- module renomme, vues
        deplacees --, les deux tests ci-dessus passeraient en ne verifiant rien.
        """
        self.assertGreater(len(_vues_de_liste()), 30)
