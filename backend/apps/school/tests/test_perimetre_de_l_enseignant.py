"""Ce qu'un enseignant peut lire de lui-meme, sans ouvrir l'annuaire.

Le module « teachers » lui est ferme, et c'est voulu: c'est de la gestion du
personnel, et son ecran n'a rien a faire dans sa barre laterale. `/teachers/` et
`/teacher-assignments/` lui repondent donc 403.

Mais cinq ecrans les reclamaient pour savoir quelles classes lui montrer --
tableau de bord, notes, discipline, emploi du temps, disponibilites. La couche
reseau avalait les refus, et chacun concluait a sa facon qu'il n'enseignait
nulle part. Une enseignante affectee a deux matieres voyait « Classes 0 » et un
selecteur vide, sans qu'un seul message n'explique pourquoi.

Deux routes reservees au compte connecte reglent le cas: `teachers/mon-profil`,
qui existait deja pour l'ecran d'emargement, et `teacher-assignments/
mes-affectations`, posee ici. Ces tests fixent ce qu'elles rendent, et surtout
**ce qu'elles ne rendent pas**: un enseignant n'y voit que lui.
"""

from datetime import date
from decimal import Decimal

from django.test import TestCase
from rest_framework import status
from rest_framework.test import APIClient

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    Subject,
    Teacher,
    TeacherAssignment,
)


class SocleDeDeuxEnseignants(TestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(
            name="Lycée du périmètre", code="LPER"
        )
        cls.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.etablissement,
            is_active=True,
        )
        cls.onzieme = ClassRoom.objects.create(
            name="11ème GM",
            academic_year=cls.annee,
            etablissement=cls.etablissement,
        )
        cls.douzieme = ClassRoom.objects.create(
            name="12ème GM",
            academic_year=cls.annee,
            etablissement=cls.etablissement,
        )
        cls.autre_classe = ClassRoom.objects.create(
            name="10ème CT",
            academic_year=cls.annee,
            etablissement=cls.etablissement,
        )

        cls.aissata = cls._enseignant("aissata")
        cls.collegue = cls._enseignant("moussa")

        # Aissata: deux matieres, deux classes -- le cas de la capture.
        cls._affecter(cls.aissata, cls.onzieme, "Atelier", "AT-11")
        cls._affecter(cls.aissata, cls.douzieme, "Atelier", "AT-12")
        # Le collegue: une matiere ailleurs, qu'elle ne doit jamais voir.
        cls._affecter(cls.collegue, cls.autre_classe, "Mathématiques", "MA-10")

    @classmethod
    def _enseignant(cls, prenom):
        compte = User.objects.create_user(
            username=f"lper.{prenom}",
            password="x",
            role=UserRole.TEACHER,
            first_name=prenom.capitalize(),
            last_name="SIDIBE",
            etablissement=cls.etablissement,
        )
        return Teacher.objects.create(
            user=compte,
            employee_code=f"LPER-{prenom[:3]}",
            hire_date=date(2024, 9, 1),
            etablissement=cls.etablissement,
        )

    @classmethod
    def _affecter(cls, enseignant, classe, nom, code):
        matiere = Subject.objects.create(
            name=nom, code=code, coefficient=Decimal(2), classroom=classe
        )
        return TeacherAssignment.objects.create(
            teacher=enseignant, subject=matiere, classroom=classe
        )

    def _client(self, enseignant):
        client = APIClient()
        client.force_authenticate(user=enseignant.user)
        return client


class LAnnuaireResteFermeTests(SocleDeDeuxEnseignants):
    """Ce qui n'a pas change, et ne doit pas changer.

    La correction ne devait pas ouvrir la gestion du personnel: l'entree
    « Enseignants » de la barre laterale s'affiche des que le module est
    lisible, et un enseignant n'a rien a y faire.
    """

    def test_la_liste_du_personnel_reste_refusee(self):
        reponse = self._client(self.aissata).get("/api/teachers/")

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)

    def test_la_liste_des_affectations_reste_refusee(self):
        reponse = self._client(self.aissata).get("/api/teacher-assignments/")

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)


class SaFicheEtSesAffectationsTests(SocleDeDeuxEnseignants):
    def test_il_obtient_sa_propre_fiche(self):
        reponse = self._client(self.aissata).get("/api/teachers/mon-profil/")

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertEqual(reponse.data["id"], self.aissata.id)

    def test_il_obtient_ses_affectations(self):
        """Le defaut corrige: « Classes 0 » pour qui en tient deux."""
        reponse = self._client(self.aissata).get(
            "/api/teacher-assignments/mes-affectations/"
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        classes = {ligne["classroom"] for ligne in reponse.data}
        self.assertEqual(classes, {self.onzieme.id, self.douzieme.id})

    def test_il_ne_voit_pas_celles_de_son_collegue(self):
        reponse = self._client(self.aissata).get(
            "/api/teacher-assignments/mes-affectations/"
        )

        enseignants = {ligne["teacher"] for ligne in reponse.data}
        self.assertEqual(enseignants, {self.aissata.id})

    def test_le_collegue_obtient_les_siennes_et_pas_les_autres(self):
        """La symetrie: chacun chez soi, et le test le dit des deux cotes."""
        reponse = self._client(self.collegue).get(
            "/api/teacher-assignments/mes-affectations/"
        )

        classes = {ligne["classroom"] for ligne in reponse.data}
        self.assertEqual(classes, {self.autre_classe.id})

    def test_la_reponse_n_est_pas_paginee(self):
        """L'ecran a besoin de **toutes** ses classes pour savoir quoi montrer.

        Une premiere page suffirait aujourd'hui, mais c'est exactement le genre
        de suffisance qui se retourne le jour ou quelqu'un enseigne dans douze
        classes.
        """
        reponse = self._client(self.aissata).get(
            "/api/teacher-assignments/mes-affectations/"
        )

        self.assertIsInstance(reponse.data, list)

    def test_un_compte_sans_fiche_enseignant_recoit_une_liste_vide(self):
        """Ni 500, ni 404: l'ecran appelle avant de savoir qui il sert."""
        compte = User.objects.create_user(
            username="lper.censeur",
            password="x",
            role=UserRole.CENSOR,
            etablissement=self.etablissement,
        )
        client = APIClient()
        client.force_authenticate(user=compte)

        reponse = client.get("/api/teacher-assignments/mes-affectations/")

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertEqual(reponse.data, [])
