"""L'ordre dans lequel l'API sert les années scolaires.

Aucun ordre n'était défini -- ni sur `AcademicYear`, ni sur sa vue -- et la
liste sortait donc dans l'ordre physique des lignes, qui change dès qu'on en met
une à jour. Cinq écrans retenaient « la première » comme année par défaut: le
jour où ce hasard a désigné l'année suivante, « Notes & Bulletins » a répondu
« Aucune note enregistrée » sur une base qui en comptait soixante-huit mille, et
les bulletins imprimés portaient des tirets partout.

Les écrans choisissent désormais l'année active explicitement, mais une liste
servie dans un ordre indéfini reste un piège pour le prochain qui en prendra le
premier élément. D'où cet ordre, et ces tests.
"""

from datetime import date

from django.test import TestCase
from rest_framework import status
from rest_framework.test import APIClient

from apps.accounts.models import User, UserRole
from apps.school.models import AcademicYear, Etablissement


class LAnneeActiveArriveEnTeteTests(TestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(
            name="Lycée des années", code="LANN"
        )
        # Creees dans le desordre exprès: l'ordre d'insertion ne doit rien dire.
        cls.suivante = AcademicYear.objects.create(
            name="2026-2027",
            start_date=date(2026, 9, 1),
            end_date=date(2027, 7, 31),
            etablissement=cls.etablissement,
            is_active=False,
        )
        cls.active = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.etablissement,
            is_active=True,
        )
        cls.ancienne = AcademicYear.objects.create(
            name="2024-2025",
            start_date=date(2024, 9, 1),
            end_date=date(2025, 7, 31),
            etablissement=cls.etablissement,
            is_active=False,
        )

    def setUp(self):
        self.client = APIClient()
        direction = User.objects.create_user(
            username="directeur.lann",
            password="x",
            role=UserRole.DIRECTOR,
            etablissement=self.etablissement,
        )
        self.client.force_authenticate(user=direction)

    def _lister(self):
        reponse = self.client.get(
            "/api/academic-years/",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        lignes = reponse.data
        if isinstance(lignes, dict):
            lignes = lignes.get("results", [])
        return list(lignes)

    def test_l_annee_active_est_la_premiere(self):
        """Ce que cinq écrans prenaient pour acquis sans que rien ne le garantisse."""
        lignes = self._lister()

        self.assertTrue(lignes)
        self.assertEqual(lignes[0]["name"], "2025-2026")
        self.assertIs(lignes[0]["is_active"], True)

    def test_les_autres_suivent_de_la_plus_recente_a_la_plus_ancienne(self):
        noms = [ligne["name"] for ligne in self._lister()]

        self.assertEqual(noms, ["2025-2026", "2026-2027", "2024-2025"])

    def test_l_ordre_ne_depend_pas_d_une_mise_a_jour(self):
        """La cause exacte du défaut: toucher une ligne changeait sa place.

        En PostgreSQL, une mise à jour réécrit la ligne et la déplace en fin de
        table. Sans `ORDER BY`, la liste changeait donc d'ordre au gré des
        modifications, et « la première » désignait tantôt une année, tantôt une
        autre.
        """
        avant = [ligne["name"] for ligne in self._lister()]

        self.ancienne.end_date = date(2025, 8, 15)
        self.ancienne.save(update_fields=["end_date"])

        self.assertEqual([ligne["name"] for ligne in self._lister()], avant)

    def test_sans_annee_active_la_plus_recente_vient_en_tete(self):
        AcademicYear.objects.filter(etablissement=self.etablissement).update(
            is_active=False
        )

        noms = [ligne["name"] for ligne in self._lister()]

        self.assertEqual(noms[0], "2026-2027")
