"""Une note de composition ne sort de l'ecole que lorsque l'ecole le decide.

`ExamSession` porte la regle depuis sa creation: « la saisie se fait a
couvert, puis la direction ouvre les resultats aux familles d'un seul coup ».
Elle n'etait appliquee qu'a une porte, `/api/exam-results/`. Quatre autres
laissaient passer: le dossier eleve, le bulletin PDF d'un eleve, celui d'une
classe entiere, et le lien signe envoye par WhatsApp -- qui regenere le
document a chaque ouverture.

Le chemin le plus ordinaire suffisait donc a contourner l'embargo: une
famille telechargeait son bulletin et lisait la composition avant le jury.

Ce fichier ferme ces portes et, tout aussi important, verifie qu'on ne les a
pas fermees au mauvais endroit: l'ecole, elle, calcule sur tout des la saisie.
"""

from datetime import date, timedelta
from decimal import Decimal

from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.reports.bulletin_delivery import horodatage_d_expiration, signer
from apps.school.models import (
    AcademicYear,
    BulletinPublication,
    ClassRoom,
    Etablissement,
    ExamInvigilation,
    ExamPlanning,
    ExamResult,
    ExamSession,
    Grade,
    ParentProfile,
    Student,
    Subject,
    moyenne_de_la_periode,
)


class SocleExamens(APITestCase):
    """Une ecole, une classe, un eleve, sa famille, une composition."""

    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(
            name="Lycee de l'embargo", code="LEMB"
        )
        cls.annee = AcademicYear.objects.create(
            name="2025-2026 EMB",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.etablissement,
            is_active=True,
        )
        cls.classe = ClassRoom.objects.create(
            name="6ème A", academic_year=cls.annee, etablissement=cls.etablissement
        )
        cls.maths = Subject.objects.create(
            name="Mathématiques",
            code="MATH",
            coefficient=Decimal("4"),
            classroom=cls.classe,
        )

        cls.directeur = User.objects.create_user(
            username="dir_embargo",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.etablissement,
        )
        cls.compte_parent = User.objects.create_user(
            username="parent_embargo",
            password="Pass1234!",
            role=UserRole.PARENT,
            etablissement=cls.etablissement,
        )
        cls.parent = ParentProfile.objects.create(
            user=cls.compte_parent, etablissement=cls.etablissement
        )
        cls.compte_eleve = User.objects.create_user(
            username="eleve_embargo",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=cls.etablissement,
            first_name="Awa",
            last_name="Traore",
        )
        cls.eleve = Student.objects.create(
            user=cls.compte_eleve,
            matricule="LEMB1EM125E0001F",
            classroom=cls.classe,
            parent=cls.parent,
            etablissement=cls.etablissement,
        )

        cls.session = ExamSession.objects.create(
            title="Composition du premier trimestre",
            term="T1",
            academic_year=cls.annee,
            start_date=date(2025, 12, 1),
            end_date=date(2025, 12, 6),
        )
        cls.note = ExamResult.objects.create(
            session=cls.session,
            student=cls.eleve,
            subject=cls.maths,
            score=Decimal("15.00"),
        )

    def _arreter_les_bulletins(self):
        BulletinPublication.objects.update_or_create(
            classroom=self.classe,
            academic_year=self.annee,
            term="T1",
            defaults={"is_published": True, "published_at": timezone.now()},
        )

    def _entetes(self):
        return {"HTTP_X_ETABLISSEMENT_ID": str(self.etablissement.id)}

    def _bulletin(self, compte):
        self.client.force_authenticate(compte)
        return self.client.get(
            f"/api/reports/bulletin/{self.eleve.id}/{self.annee.id}/T1/",
            **self._entetes(),
        )


class BulletinSousEmbargoTests(SocleExamens):
    def test_la_famille_n_obtient_pas_un_bulletin_non_arrete(self):
        """Le chemin par lequel l'embargo se contournait.

        Le bulletin lit les resultats d'examen sans regarder si la session
        est ouverte -- et c'est voulu, il ne doit pas etre ampute. C'est donc
        l'acces au document qui attend l'arret de la direction.
        """
        for compte in (self.compte_parent, self.compte_eleve):
            with self.subTest(compte=compte.username):
                reponse = self._bulletin(compte)

                self.assertEqual(reponse.status_code, status.HTTP_409_CONFLICT)
                self.assertIn("arrêté", str(reponse.data["detail"]))

    def test_une_fois_arrete_la_famille_l_obtient(self):
        self._arreter_les_bulletins()

        for compte in (self.compte_parent, self.compte_eleve):
            with self.subTest(compte=compte.username):
                reponse = self._bulletin(compte)

                self.assertEqual(reponse.status_code, status.HTTP_200_OK)
                self.assertEqual(reponse["Content-Type"], "application/pdf")

    def test_le_secretariat_sort_son_brouillon_quand_il_veut(self):
        """« L'impression reste libre », dit le modele BulletinPublication.

        Le conseil de classe travaille sur un document non arrete: fermer
        aussi cette porte aurait rendu la validation impossible a preparer.
        """
        reponse = self._bulletin(self.directeur)

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertEqual(reponse["Content-Type"], "application/pdf")


class LienSigneTests(SocleExamens):
    def _lien(self):
        expire = horodatage_d_expiration()
        signature = signer(self.eleve.id, self.annee.id, "T1", expire)
        return (
            f"/api/reports/bulletin-partage/{self.eleve.id}/{self.annee.id}/T1/"
            f"{expire}/{signature}/"
        )

    def test_un_bulletin_repris_cesse_de_repondre(self):
        """Le PDF est regenere a chaque ouverture, pas fige a l'envoi.

        Un arret retire entre l'envoi et la lecture -- moyenne a reprendre,
        conseil a refaire -- laissait donc le lien servir un document que
        l'ecole ne soutenait plus.
        """
        self.client.force_authenticate(None)

        reponse = self.client.get(self._lien())

        self.assertEqual(reponse.status_code, status.HTTP_409_CONFLICT)
        self.assertNotIn("application/pdf", reponse["Content-Type"])

    def test_un_bulletin_arrete_s_ouvre(self):
        self._arreter_les_bulletins()
        self.client.force_authenticate(None)

        reponse = self.client.get(self._lien())

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertEqual(reponse["Content-Type"], "application/pdf")


class DossierSousEmbargoTests(SocleExamens):
    def _dossier(self, compte):
        self.client.force_authenticate(compte)
        reponse = self.client.get(
            f"/api/students/{self.eleve.id}/dossier/", **self._entetes()
        )
        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        return next(
            section
            for section in reponse.data["sections"]
            if section["key"] == "exams"
        )

    def test_la_famille_ne_lit_pas_la_note_non_publiee(self):
        """L'autre porte du meme secret.

        `/api/exam-results/` la refusait deja; le dossier la servait, avec
        une moyenne calculee dessus.
        """
        for compte in (self.compte_parent, self.compte_eleve):
            with self.subTest(compte=compte.username):
                section = self._dossier(compte)

                self.assertEqual(section["items"], [])
                self.assertIsNone(section["summary"]["moyenne"])

    def test_elle_sait_combien_de_notes_lui_sont_dues(self):
        """Un embargo doit se voir.

        Taire la note sans le dire ferait prendre une moyenne partielle pour
        la moyenne de l'eleve.
        """
        section = self._dossier(self.compte_parent)

        self.assertEqual(section["summary"]["notes_en_attente"], 1)

    def test_apres_publication_elle_la_lit(self):
        self.session.publier_les_resultats(user=self.directeur)

        section = self._dossier(self.compte_parent)

        self.assertEqual(len(section["items"]), 1)
        self.assertEqual(section["summary"]["notes_en_attente"], 0)

    def test_le_personnel_la_lit_des_la_saisie(self):
        section = self._dossier(self.directeur)

        self.assertEqual(len(section["items"]), 1)
        self.assertEqual(section["summary"]["notes_en_attente"], 0)


class LEcoleCalculeSurToutTests(SocleExamens):
    """Le test qui empeche de fermer l'embargo au mauvais endroit.

    L'embargo porte sur le lecteur, jamais sur la donnee. Un successeur
    tente de « completer » le filtre en le posant dans le calcul: le rang
    dependrait alors de la date a laquelle on l'imprime, et un eleve
    redoublerait parce que sa composition n'etait pas encore ouverte.
    """

    def test_la_moyenne_ne_depend_pas_de_la_publication(self):
        Grade.objects.create(
            student=self.eleve,
            subject=self.maths,
            classroom=self.classe,
            academic_year=self.annee,
            term="T1",
            homework_scores=[11.0],
        )

        avant = moyenne_de_la_periode(
            self.eleve, self.classe, self.annee, "T1", avec_conduite=False
        )
        self.session.publier_les_resultats(user=self.directeur)
        apres = moyenne_de_la_periode(
            self.eleve, self.classe, self.annee, "T1", avec_conduite=False
        )

        self.assertEqual(avant, apres)
        # (11 + 15) / 2 = 13 : la composition compte des sa saisie.
        self.assertEqual(avant, Decimal("13.00"))


class CloisonnementDuModuleTests(SocleExamens):
    """Ce que la famille et l'ecole voisine n'ont pas a lire."""

    @classmethod
    def setUpTestData(cls):
        super().setUpTestData()
        cls.voisine = Etablissement.objects.create(name="Lycee Voisin", code="LVOI")
        cls.annee_voisine = AcademicYear.objects.create(
            name="2025-2026 VOI",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.voisine,
        )
        cls.session_voisine = ExamSession.objects.create(
            title="Composition du voisin",
            term="T1",
            academic_year=cls.annee_voisine,
            start_date=date(2025, 12, 1),
            end_date=date(2025, 12, 6),
        )

        cls.autre_classe = ClassRoom.objects.create(
            name="5ème B", academic_year=cls.annee, etablissement=cls.etablissement
        )
        cls.epreuve_de_l_enfant = ExamPlanning.objects.create(
            session=cls.session,
            classroom=cls.classe,
            subject=cls.maths,
            exam_date=date(2025, 12, 2),
            start_time="08:00",
            end_time="10:00",
        )
        cls.epreuve_voisine = ExamPlanning.objects.create(
            session=cls.session,
            classroom=cls.autre_classe,
            subject=cls.maths,
            exam_date=date(2025, 12, 3),
            start_time="08:00",
            end_time="10:00",
        )
        ExamInvigilation.objects.create(
            planning=cls.epreuve_de_l_enfant, supervisor=cls.directeur
        )

    def _lire(self, compte, route):
        self.client.force_authenticate(compte)
        return self.client.get(route, **self._entetes())

    def test_une_session_d_une_autre_ecole_ne_se_lit_pas(self):
        """La vue n'avait aucun cloisonnement: elle rendait le registre entier.

        Et `publier`/`depublier` passent par le meme ensemble, donc un
        directeur ouvrait les resultats d'une autre ecole.
        """
        reponse = self._lire(self.directeur, "/api/exam-sessions/")

        titres = {ligne["title"] for ligne in reponse.data["results"]}
        self.assertIn("Composition du premier trimestre", titres)
        self.assertNotIn("Composition du voisin", titres)

    def test_la_famille_ne_lit_que_les_epreuves_de_ses_enfants(self):
        """L'horaire d'une epreuve a venir n'est pas un secret.

        Celui d'une autre classe ne la regarde pas pour autant: la famille
        recevait le calendrier d'examen de toute l'ecole.
        """
        for compte in (self.compte_parent, self.compte_eleve):
            with self.subTest(compte=compte.username):
                reponse = self._lire(compte, "/api/exam-plannings/")

                classes = {ligne["classroom"] for ligne in reponse.data["results"]}
                self.assertEqual(classes, {self.classe.id})

    def test_la_famille_ne_lit_pas_le_tableau_de_surveillance(self):
        """C'est un document de service.

        La famille, qui lit le module en `L*`, y voyait le nom de chaque
        surveillant et l'epreuve qu'il tient.
        """
        for compte in (self.compte_parent, self.compte_eleve):
            with self.subTest(compte=compte.username):
                reponse = self._lire(compte, "/api/exam-invigilations/")

                self.assertEqual(reponse.data["results"], [])

    def test_le_personnel_garde_le_tableau_de_surveillance(self):
        reponse = self._lire(self.directeur, "/api/exam-invigilations/")

        self.assertEqual(len(reponse.data["results"]), 1)
