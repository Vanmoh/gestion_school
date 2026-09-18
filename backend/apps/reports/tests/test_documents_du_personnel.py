"""Les deux pieces du personnel: bulletin de salaire et certificat de travail.

La paie se calculait, se validait a deux niveaux et se payait, sans qu'aucune
piece n'en sorte: l'enseignant n'avait rien a presenter a une banque, a un
bailleur ou a une administration, et rien pour verifier le compte de ses
heures.
"""

from datetime import date
from decimal import Decimal

from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.reports.views import (
    _build_bulletin_de_paie_payload,
    _build_certificat_travail_payload,
    _mois_en_toutes_lettres,
)
from apps.school.models import (
    AcademicYear,
    Etablissement,
    Teacher,
    TeacherPayroll,
)


class _Decor:
    @classmethod
    def _monter(cls, nom="Lycée Kalaban"):
        cls.etablissement = Etablissement.objects.create(
            name=nom, code="LKB", address="Bamako, Kalaban", phone="76000000"
        )
        cls.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
            etablissement=cls.etablissement,
        )

    @classmethod
    def _enseignant(cls, username, *, embauche=date(2023, 10, 2), prenom="Modibo", nom="Keïta"):
        user = User.objects.create_user(
            username=username,
            password="Pass1234!",
            role=UserRole.TEACHER,
            etablissement=cls.etablissement,
            first_name=prenom,
            last_name=nom,
        )
        return Teacher.objects.create(
            user=user,
            hire_date=embauche,
            hourly_rate=Decimal("2500.00"),
            etablissement=cls.etablissement,
        )

    @classmethod
    def _paie(cls, enseignant, *, mois=date(2025, 10, 1), montant="175000.00", valide=False):
        paie = TeacherPayroll.objects.create(
            teacher=enseignant,
            month=mois,
            academic_year=cls.annee,
            hours_attributed=Decimal("80.00"),
            hours_worked=Decimal("70.00"),
            hours_missed=Decimal("10.00"),
            hourly_rate=Decimal("2500.00"),
            amount=Decimal(montant),
        )
        if valide:
            paie.level_one_validated_at = timezone.now()
            paie.level_two_validated_at = timezone.now()
            paie.save(update_fields=["level_one_validated_at", "level_two_validated_at"])
        return paie


class MoisEnLettresTests(APITestCase):
    def test_le_mois_s_ecrit_en_francais(self):
        self.assertEqual(_mois_en_toutes_lettres(date(2025, 10, 1)), "octobre 2025")
        self.assertEqual(_mois_en_toutes_lettres(date(2026, 8, 1)), "août 2026")

    def test_un_mois_absent_ne_fait_pas_tomber_la_piece(self):
        self.assertEqual(_mois_en_toutes_lettres(None), "-")


class BulletinDeSalaireTests(_Decor, APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls._monter()
        cls.directeur = User.objects.create_user(
            username="dir_paie",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.etablissement,
        )

    def setUp(self):
        super().setUp()
        self.enseignant = self._enseignant("ens_paie")
        self.paie = self._paie(self.enseignant)
        self.client.force_authenticate(self.directeur)

    def _demander(self, paie=None):
        return self.client.get(
            f"/api/reports/bulletin-salaire/{(paie or self.paie).id}/",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

    def test_la_piece_sort_en_pdf(self):
        reponse = self._demander()

        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.content[:200])
        self.assertEqual(reponse["Content-Type"], "application/pdf")
        self.assertGreater(len(reponse.content), 800)

    def test_le_detail_des_heures_figure_au_bulletin(self):
        # C'est lui qui explique le montant: un enseignant qui conteste sa
        # paie conteste un nombre d'heures, pas une multiplication.
        charge = _build_bulletin_de_paie_payload(self.paie)

        libelles = [libelle for libelle, _ in charge["lignes"]]
        self.assertIn("Heures attribuées", libelles)
        self.assertIn("Heures assurées", libelles)
        self.assertIn("Heures non assurées", libelles)
        self.assertIn("Taux horaire", libelles)

    def test_le_bulletin_porte_le_matricule_et_l_embauche(self):
        charge = _build_bulletin_de_paie_payload(self.paie)

        self.assertEqual(charge["matricule"], self.enseignant.employee_code)
        self.assertEqual(charge["embauche"], "02/10/2023")
        self.assertIn("Modibo", charge["nom"])

    def test_un_brouillon_le_dit(self):
        # Un bulletin non valide ne vaut pas engagement: celui qui le recoit
        # doit le savoir.
        charge = _build_bulletin_de_paie_payload(self.paie)

        self.assertIn("Brouillon", charge["mention"])

    def test_une_paie_validee_est_annoncee_comme_arretee(self):
        paie = self._paie(
            self._enseignant("ens_valide"), mois=date(2025, 11, 1), valide=True
        )

        charge = _build_bulletin_de_paie_payload(paie)

        self.assertIn("arrêté", charge["mention"])

    def test_un_enseignant_ne_lit_pas_la_paie_d_un_collegue(self):
        collegue = self._enseignant("ens_collegue")
        paie_du_collegue = self._paie(collegue, mois=date(2025, 12, 1))
        self.client.force_authenticate(self.enseignant.user)

        reponse = self._demander(paie_du_collegue)

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)

    def test_un_enseignant_obtient_la_sienne(self):
        self.client.force_authenticate(self.enseignant.user)

        self.assertEqual(self._demander().status_code, status.HTTP_200_OK)


class CertificatDeTravailTests(_Decor, APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls._monter("Lycée Ségou")
        cls.directeur = User.objects.create_user(
            username="dir_travail",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.etablissement,
        )

    def setUp(self):
        super().setUp()
        self.enseignant = self._enseignant("ens_travail")
        self.client.force_authenticate(self.directeur)

    def _demander(self, enseignant=None):
        return self.client.get(
            f"/api/reports/certificat-travail/{(enseignant or self.enseignant).id}/",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

    def test_la_piece_sort_en_pdf(self):
        reponse = self._demander()

        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.content[:200])
        self.assertEqual(reponse["Content-Type"], "application/pdf")

    def test_le_corps_nomme_l_enseignant_et_son_matricule(self):
        charge = _build_certificat_travail_payload(self.enseignant)

        self.assertIn("Modibo Keïta", charge["corps"])
        self.assertIn(self.enseignant.employee_code, charge["corps"])
        self.assertIn("depuis le 02/10/2023", charge["corps"])
        self.assertEqual(charge["titre"], "CERTIFICAT DE TRAVAIL")

    def test_une_fiche_sans_embauche_n_existe_pas(self):
        # Le modele l'interdit, et c'est ce qui rend la mention « depuis le »
        # toujours vraie sur la piece. La garde du code reste, pour le jour
        # ou le champ deviendrait facultatif.
        from django.db import IntegrityError, transaction

        user = User.objects.create_user(
            username="ens_sans_date",
            password="Pass1234!",
            role=UserRole.TEACHER,
            etablissement=self.etablissement,
        )
        with self.assertRaises(IntegrityError), transaction.atomic():
            Teacher.objects.create(
                user=user, hire_date=None, etablissement=self.etablissement
            )

    def test_un_enseignant_ne_lit_pas_le_certificat_d_un_collegue(self):
        collegue = self._enseignant("ens_autre")
        self.client.force_authenticate(self.enseignant.user)

        self.assertEqual(
            self._demander(collegue).status_code, status.HTTP_403_FORBIDDEN
        )
