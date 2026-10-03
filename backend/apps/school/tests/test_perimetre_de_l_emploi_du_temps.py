"""Ses classes, et elles seules.

La matrice annonce `L*` pour l'enseignant, le parent et l'eleve -- une portee
restreinte « deja appliquee par le get_queryset de la vue ». Elle ne l'etait pas:
`TeacherScheduleSlotViewSet` ne filtrait que par etablissement. Un parent
recevait les cent cinquante creneaux des cinq classes de l'ecole quand ses
enfants n'en occupent qu'une, et un eleve les recevait tous.

Cela ne se voyait pas -- l'ecran n'affiche que les classes auxquelles il a droit
par ailleurs -- et c'est precisement ce qui rendait l'ecart durable: la donnee
partait quand meme, et rien ne l'aurait signale.

Un detail de la correction merite d'etre garde en memoire: la classe portait
**deux** `get_queryset`. Le premier, ecrit de bonne foi, etait du code mort --
Python garde la derniere definition. Ces tests interrogent l'API et non la
methode, donc ils auraient echoue dans les deux cas; c'est la raison de les
ecrire ainsi.
"""

from datetime import date, time
from decimal import Decimal

from django.test import TestCase
from rest_framework import status
from rest_framework.test import APIClient

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    ParentProfile,
    Student,
    Subject,
    Teacher,
    TeacherAssignment,
    TeacherScheduleSlot,
)


class SocleDeTroisClasses(TestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(
            name="Lycée des créneaux", code="LCRE"
        )
        cls.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.etablissement,
            is_active=True,
        )
        cls.sienne = cls._classe("10ème CT")
        cls.voisine = cls._classe("11ème CG")
        cls.lointaine = cls._classe("12ème GM")

        cls.prof = cls._enseignant("moussa")
        cls.autre_prof = cls._enseignant("fatou")

        # Le professeur enseigne dans « sienne » et « lointaine », jamais dans
        # « voisine »: c'est ce trou qui rend le test lisible.
        cls._creneau(cls.prof, cls.sienne, "Mathématiques", "MA-10", "MON")
        cls._creneau(cls.prof, cls.lointaine, "Mathématiques", "MA-12", "TUE")
        cls._creneau(cls.autre_prof, cls.voisine, "Français", "FR-11", "WED")

        # La famille: un eleve en « sienne », sa soeur en « voisine ».
        cls.parent = cls._parent("diallo")
        cls.eleve = cls._eleve("ali", cls.sienne, cls.parent)
        cls.soeur = cls._eleve("awa", cls.voisine, cls.parent)

    @classmethod
    def _classe(cls, nom):
        return ClassRoom.objects.create(
            name=nom, academic_year=cls.annee, etablissement=cls.etablissement
        )

    @classmethod
    def _enseignant(cls, prenom):
        compte = User.objects.create_user(
            username=f"lcre.{prenom}",
            password="x",
            role=UserRole.TEACHER,
            first_name=prenom.capitalize(),
            last_name="KEITA",
            etablissement=cls.etablissement,
        )
        return Teacher.objects.create(
            user=compte,
            employee_code=f"LCRE-{prenom[:3]}",
            hire_date=date(2024, 9, 1),
            etablissement=cls.etablissement,
        )

    @classmethod
    def _creneau(cls, enseignant, classe, nom, code, jour):
        matiere = Subject.objects.create(
            name=nom, code=code, coefficient=Decimal(3), classroom=classe
        )
        affectation = TeacherAssignment.objects.create(
            teacher=enseignant, subject=matiere, classroom=classe
        )
        return TeacherScheduleSlot.objects.create(
            assignment=affectation,
            day_of_week=jour,
            start_time=time(8, 0),
            end_time=time(9, 0),
        )

    @classmethod
    def _parent(cls, nom):
        compte = User.objects.create_user(
            username=f"lcre.parent.{nom}",
            password="x",
            role=UserRole.PARENT,
            first_name="Papa",
            last_name=nom.upper(),
            etablissement=cls.etablissement,
        )
        return ParentProfile.objects.create(
            user=compte, etablissement=cls.etablissement
        )

    @classmethod
    def _eleve(cls, prenom, classe, parent):
        compte = User.objects.create_user(
            username=f"lcre.{prenom}",
            password="x",
            role=UserRole.STUDENT,
            first_name=prenom.capitalize(),
            last_name="DIALLO",
            etablissement=cls.etablissement,
        )
        return Student.objects.create(
            user=compte,
            matricule=f"LCRE{prenom[:3].upper()}",
            classroom=classe,
            parent=parent,
            etablissement=cls.etablissement,
        )

    def _classes_vues(self, compte):
        client = APIClient()
        client.force_authenticate(user=compte)
        reponse = client.get(
            "/api/teacher-schedule-slots/",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )
        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        donnees = reponse.data
        lignes = donnees.get("results", donnees) if isinstance(donnees, dict) else donnees
        return {ligne["classroom"] for ligne in lignes}


class ChacunNeVoitQueSesClassesTests(SocleDeTroisClasses):
    def test_l_eleve_ne_voit_que_la_sienne(self):
        self.assertEqual(self._classes_vues(self.eleve.user), {self.sienne.id})

    def test_le_parent_voit_celles_de_ses_deux_enfants(self):
        self.assertEqual(
            self._classes_vues(self.parent.user),
            {self.sienne.id, self.voisine.id},
        )

    def test_le_parent_ne_voit_pas_la_classe_ou_il_n_a_personne(self):
        """Le defaut corrige, dit a l'envers: cent cinquante creneaux pour trois."""
        self.assertNotIn(self.lointaine.id, self._classes_vues(self.parent.user))

    def test_l_enseignant_voit_les_classes_ou_il_enseigne(self):
        """Ses classes entieres, et non ses seules heures.

        Savoir quand sa classe est prise fait partie de son metier: c'est le
        sens documente de l'etoile, « ses classes », pas « ses seances ».
        """
        self.assertEqual(
            self._classes_vues(self.prof.user),
            {self.sienne.id, self.lointaine.id},
        )

    def test_l_enseignant_ne_voit_pas_la_classe_d_un_collegue(self):
        self.assertNotIn(self.voisine.id, self._classes_vues(self.prof.user))

    def test_un_enseignant_sans_affectation_ne_voit_rien(self):
        """Et ce n'est pas une anomalie: il n'enseigne nulle part."""
        orphelin = self._enseignant("sans")

        self.assertEqual(self._classes_vues(orphelin.user), set())


class LaDirectionVoitToutTests(SocleDeTroisClasses):
    """La restriction ne doit pas deborder sur ceux qui pilotent l'ecole."""

    def test_le_directeur_voit_les_trois_classes(self):
        directeur = User.objects.create_user(
            username="lcre.dir",
            password="x",
            role=UserRole.DIRECTOR,
            etablissement=self.etablissement,
        )

        self.assertEqual(
            self._classes_vues(directeur),
            {self.sienne.id, self.voisine.id, self.lointaine.id},
        )

    def test_le_censeur_voit_les_trois_classes(self):
        censeur = User.objects.create_user(
            username="lcre.cen",
            password="x",
            role=UserRole.CENSOR,
            etablissement=self.etablissement,
        )

        self.assertEqual(
            self._classes_vues(censeur),
            {self.sienne.id, self.voisine.id, self.lointaine.id},
        )
