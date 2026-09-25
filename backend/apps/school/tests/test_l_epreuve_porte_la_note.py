"""L'epreuve est l'unite de travail du module, et elle ne l'etait pas.

Une note portait `(session, eleve, matiere)` et ignorait le planning. Trois
consequences, toutes visibles au secretariat: une note pouvait exister pour
une epreuve jamais planifiee, une epreuve corrigee ne se distinguait pas
d'une epreuve en attente, et la publication ne se decidait que pour la
campagne entiere -- alors que les copies reviennent classe par classe.
"""

import importlib
from datetime import date, time
from decimal import Decimal

from django.apps import apps as registre
from django.db.models import RestrictedError
from django.test import SimpleTestCase
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    ExamInvigilation,
    ExamPlanning,
    ExamResult,
    ExamSession,
    ParentProfile,
    Student,
    StudentAcademicHistory,
    Subject,
)


class SocleEpreuves(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(
            name="Lycee des epreuves", code="LEPR"
        )
        cls.annee = AcademicYear.objects.create(
            name="2025-2026 EPR",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.etablissement,
            is_active=True,
        )
        cls.sixieme = ClassRoom.objects.create(
            name="6ème A", academic_year=cls.annee, etablissement=cls.etablissement
        )
        cls.cinquieme = ClassRoom.objects.create(
            name="5ème B", academic_year=cls.annee, etablissement=cls.etablissement
        )
        cls.maths = Subject.objects.create(
            name="Mathématiques", code="MATH", coefficient=Decimal("4")
        )

        cls.directeur = User.objects.create_user(
            username="dir_epreuve",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.etablissement,
        )
        cls.compte_parent = User.objects.create_user(
            username="parent_epreuve",
            password="Pass1234!",
            role=UserRole.PARENT,
            etablissement=cls.etablissement,
        )
        cls.parent = ParentProfile.objects.create(
            user=cls.compte_parent, etablissement=cls.etablissement
        )

        cls.session = ExamSession.objects.create(
            title="Composition du premier trimestre",
            term="T1",
            academic_year=cls.annee,
            start_date=date(2025, 12, 1),
            end_date=date(2025, 12, 6),
        )

    @classmethod
    def _eleve(cls, username, matricule, classe):
        compte = User.objects.create_user(
            username=username,
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=cls.etablissement,
        )
        return Student.objects.create(
            user=compte,
            matricule=matricule,
            classroom=classe,
            parent=cls.parent,
            etablissement=cls.etablissement,
        )

    @classmethod
    def _epreuve(cls, classe, jour=2, debut=time(8, 0), fin=time(10, 0)):
        return ExamPlanning.objects.create(
            session=cls.session,
            classroom=classe,
            subject=cls.maths,
            exam_date=date(2025, 12, jour),
            start_time=debut,
            end_time=fin,
        )

    def _entetes(self):
        return {"HTTP_X_ETABLISSEMENT_ID": str(self.etablissement.id)}


class PublicationParEpreuveTests(SocleEpreuves):
    """Les copies reviennent classe par classe: la publication aussi."""

    @classmethod
    def setUpTestData(cls):
        super().setUpTestData()
        cls.eleve_6a = cls._eleve("eleve_6a", "LEPR6A0001M", cls.sixieme)
        cls.eleve_5b = cls._eleve("eleve_5b", "LEPR5B0001F", cls.cinquieme)
        cls.epreuve_6a = cls._epreuve(cls.sixieme, jour=2)
        cls.epreuve_5b = cls._epreuve(cls.cinquieme, jour=3)
        cls.note_6a = ExamResult.objects.create(
            session=cls.session,
            student=cls.eleve_6a,
            subject=cls.maths,
            score=Decimal("15.00"),
            planning=cls.epreuve_6a,
        )
        cls.note_5b = ExamResult.objects.create(
            session=cls.session,
            student=cls.eleve_5b,
            subject=cls.maths,
            score=Decimal("12.00"),
            planning=cls.epreuve_5b,
        )

    def _publier(self, epreuve):
        self.client.force_authenticate(self.directeur)
        return self.client.post(
            f"/api/exam-plannings/{epreuve.id}/publier/", **self._entetes()
        )

    def _notes_vues_par_la_famille(self):
        self.client.force_authenticate(self.compte_parent)
        reponse = self.client.get("/api/exam-results/", **self._entetes())
        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        return {ligne["id"] for ligne in reponse.data["results"]}

    def test_publier_une_classe_n_ouvre_pas_l_autre(self):
        """Le geste que la session ne savait pas faire.

        Il fallait ouvrir toute la campagne -- y compris les classes non
        corrigees -- ou ne rien ouvrir.
        """
        reponse = self._publier(self.epreuve_6a)

        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        self.assertEqual(self._notes_vues_par_la_famille(), {self.note_6a.id})

    def test_publier_la_session_ouvre_toutes_ses_epreuves(self):
        """L'API de la session reste ce qu'elle etait pour qui l'appelle.

        Le client en production continue de s'en servir; elle emmene
        desormais les epreuves avec elle.
        """
        self.client.force_authenticate(self.directeur)
        reponse = self.client.post(
            f"/api/exam-sessions/{self.session.id}/publier/", **self._entetes()
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        self.assertEqual(
            self._notes_vues_par_la_famille(), {self.note_6a.id, self.note_5b.id}
        )

    def test_retirer_une_epreuve_la_referme_seule(self):
        self.session.publier_les_resultats(user=self.directeur)
        self.client.force_authenticate(self.directeur)

        self.client.post(
            f"/api/exam-plannings/{self.epreuve_6a.id}/depublier/", **self._entetes()
        )

        self.assertEqual(self._notes_vues_par_la_famille(), {self.note_5b.id})

    def test_une_epreuve_sans_note_ne_se_publie_pas(self):
        """Publier le vide ferait chercher des resultats qui n'existent pas."""
        vide = self._epreuve(self.sixieme, jour=4, debut=time(14, 0), fin=time(16, 0))

        reponse = self._publier(vide)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_la_trace_de_la_publication_survit_au_retrait(self):
        """Elle explique pourquoi une famille a vu passer un chiffre."""
        self._publier(self.epreuve_6a)
        self.epreuve_6a.refresh_from_db()
        publie_le = self.epreuve_6a.results_published_at

        self.epreuve_6a.depublier_les_resultats()
        self.epreuve_6a.refresh_from_db()

        self.assertFalse(self.epreuve_6a.results_published)
        self.assertEqual(self.epreuve_6a.results_published_at, publie_le)
        self.assertEqual(self.epreuve_6a.results_published_by, self.directeur)

    def test_la_session_compte_ses_epreuves_ouvertes(self):
        """Un booleen mentirait: « publiée » devant une classe sur deux."""
        self._publier(self.epreuve_6a)
        self.client.force_authenticate(self.directeur)

        reponse = self.client.get(
            f"/api/exam-sessions/{self.session.id}/", **self._entetes()
        )

        self.assertEqual(reponse.data["epreuves_total"], 2)
        self.assertEqual(reponse.data["epreuves_publiees"], 1)

    def test_un_eleve_ne_publie_pas_une_epreuve(self):
        self.client.force_authenticate(self.eleve_6a.user)

        reponse = self.client.post(
            f"/api/exam-plannings/{self.epreuve_6a.id}/publier/", **self._entetes()
        )

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)


class RattachementALEpreuveTests(SocleEpreuves):
    """Le serializer derive l'epreuve quand on ne la nomme pas."""

    @classmethod
    def setUpTestData(cls):
        super().setUpTestData()
        cls.eleve = cls._eleve("eleve_rattache", "LEPR6A0002M", cls.sixieme)

    def _saisir(self, **charge):
        self.client.force_authenticate(self.directeur)
        donnees = {
            "session": self.session.id,
            "student": self.eleve.id,
            "subject": self.maths.id,
            "score": "14.00",
        }
        donnees.update(charge)
        return self.client.post(
            "/api/exam-results/", donnees, format="json", **self._entetes()
        )

    def test_une_note_trouve_son_epreuve_sans_qu_on_la_nomme(self):
        """Trois producteurs de notes ne la connaissent pas: l'import de
        fichier, les donnees de demonstration, l'ecran d'administration."""
        epreuve = self._epreuve(self.sixieme)

        reponse = self._saisir()

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)
        self.assertEqual(
            ExamResult.objects.get(id=reponse.data["id"]).planning_id, epreuve.id
        )

    def test_sans_epreuve_planifiee_la_note_reste_rattachable_plus_tard(self):
        """Elle suit alors le drapeau de sa session, et rien n'est perdu."""
        reponse = self._saisir()

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)
        self.assertIsNone(ExamResult.objects.get(id=reponse.data["id"]).planning_id)

    def test_deux_epreuves_possibles_ne_se_tranchent_pas_en_silence(self):
        """Une composition et son rattrapage se distinguent par une date.

        Choisir pour celui qui saisit poserait la note sur la mauvaise, et
        rien ne le signalerait.
        """
        self._epreuve(self.sixieme, jour=2)
        self._epreuve(self.sixieme, jour=5, debut=time(14, 0), fin=time(16, 0))

        reponse = self._saisir()

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("planning", reponse.data)

    def test_l_epreuve_nommee_prime_sur_la_derivation(self):
        self._epreuve(self.sixieme, jour=2)
        choisie = self._epreuve(
            self.sixieme, jour=5, debut=time(14, 0), fin=time(16, 0)
        )

        reponse = self._saisir(planning=choisie.id)

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)
        self.assertEqual(
            ExamResult.objects.get(id=reponse.data["id"]).planning_id, choisie.id
        )

    def test_le_rattrapage_cesse_d_etre_interdit(self):
        """La regle portait sur (eleve, matiere, annee, periode).

        Elle interdisait donc ce qui est par definition une seconde epreuve
        de la meme matiere dans le meme trimestre.
        """
        composition = self._epreuve(self.sixieme, jour=2)
        rattrapage = self._epreuve(
            self.sixieme, jour=5, debut=time(14, 0), fin=time(16, 0)
        )

        premiere = self._saisir(planning=composition.id)
        seconde = self._saisir(planning=rattrapage.id, score="17.00")

        self.assertEqual(premiere.status_code, status.HTTP_201_CREATED)
        self.assertEqual(seconde.status_code, status.HTTP_201_CREATED, seconde.data)

    def test_deux_notes_sur_la_meme_epreuve_restent_refusees(self):
        epreuve = self._epreuve(self.sixieme)

        self._saisir(planning=epreuve.id)
        doublon = self._saisir(planning=epreuve.id, score="9.00")

        self.assertEqual(doublon.status_code, status.HTTP_400_BAD_REQUEST)


class CoherenceDUneEpreuveTests(SocleEpreuves):
    """Trois regles qui tenaient de l'evidence et n'etaient ecrites nulle part."""

    def _planifier(self, **charge):
        self.client.force_authenticate(self.directeur)
        donnees = {
            "session": self.session.id,
            "classroom": self.sixieme.id,
            "subject": self.maths.id,
            "exam_date": "2025-12-02",
            "start_time": "08:00",
            "end_time": "10:00",
        }
        donnees.update(charge)
        return self.client.post(
            "/api/exam-plannings/", donnees, format="json", **self._entetes()
        )

    def test_une_epreuve_ne_finit_pas_avant_de_commencer(self):
        reponse = self._planifier(start_time="10:00", end_time="08:00")

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_une_epreuve_tombe_dans_sa_session(self):
        """Hors de la fenetre, elle produit un planning imprime faux."""
        reponse = self._planifier(exam_date="2026-01-15")

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("exam_date", reponse.data)

    def test_une_matiere_d_une_autre_classe_est_refusee(self):
        physique = Subject.objects.create(
            name="Physique", code="PHY", coefficient=Decimal("2"),
            classroom=self.cinquieme,
        )

        reponse = self._planifier(subject=physique.id)

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("subject", reponse.data)

    def test_une_matiere_partagee_reste_planifiable(self):
        """`Subject.classroom` est nullable: une matiere commune a plusieurs
        classes n'est rattachee a aucune, et c'est licite."""
        reponse = self._planifier()

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)


class CeQueLEcranPeutDemanderTests(SocleEpreuves):
    """Les deux questions que le calendrier pose au serveur.

    Sans ces filtres, l'ecran ramenait tout et triait en memoire -- ce qui
    marche sur une classe et ne marche plus sur quinze.
    """

    @classmethod
    def setUpTestData(cls):
        super().setUpTestData()
        cls.eleve = cls._eleve("eleve_filtre", "LEPR6A0009M", cls.sixieme)
        cls.epreuve_ouverte = cls._epreuve(cls.sixieme, jour=2)
        cls.epreuve_fermee = cls._epreuve(cls.cinquieme, jour=3)
        cls.note = ExamResult.objects.create(
            session=cls.session,
            student=cls.eleve,
            subject=cls.maths,
            score=Decimal("13.00"),
            planning=cls.epreuve_ouverte,
        )
        cls.epreuve_ouverte.publier_les_resultats()

    def _lire(self, route):
        self.client.force_authenticate(self.directeur)
        reponse = self.client.get(route, **self._entetes())
        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        return reponse.data["results"]

    def test_les_epreuves_qu_il_reste_a_ouvrir(self):
        """La seule question qu'on se pose devant un calendrier en fin de
        trimestre."""
        restantes = self._lire("/api/exam-plannings/?results_published=false")

        self.assertEqual(
            {ligne["id"] for ligne in restantes}, {self.epreuve_fermee.id}
        )

    def test_les_notes_d_une_epreuve(self):
        """Le grain de la correction: on corrige une epreuve, pas une session."""
        notes = self._lire(
            f"/api/exam-results/?planning={self.epreuve_ouverte.id}"
        )

        self.assertEqual({ligne["id"] for ligne in notes}, {self.note.id})


class InventaireAvantSuppressionTests(SocleEpreuves):
    """Supprimer une campagne emporte ses epreuves et toutes ses notes."""

    @classmethod
    def setUpTestData(cls):
        super().setUpTestData()
        cls.eleve = cls._eleve("eleve_inventaire", "LEPR6A0010M", cls.sixieme)
        cls.epreuve = cls._epreuve(cls.sixieme)
        ExamResult.objects.create(
            session=cls.session,
            student=cls.eleve,
            subject=cls.maths,
            score=Decimal("10.00"),
            planning=cls.epreuve,
        )
        ExamInvigilation.objects.create(
            planning=cls.epreuve, supervisor=cls.directeur
        )

    def _inventaire(self):
        self.client.force_authenticate(self.directeur)
        reponse = self.client.get(
            f"/api/exam-sessions/{self.session.id}/delete-check/",
            **self._entetes(),
        )
        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        return reponse.data

    def test_il_nomme_ce_qui_partirait(self):
        inventaire = self._inventaire()

        self.assertEqual(inventaire["dependencies"]["exam_plannings"], 1)
        self.assertEqual(inventaire["dependencies"]["exam_results"], 1)
        self.assertEqual(inventaire["dependencies"]["exam_invigilations"], 1)
        self.assertFalse(inventaire["can_delete"])

    def test_une_campagne_vide_se_supprime_sans_ceremonie(self):
        vide = ExamSession.objects.create(
            title="Campagne creee en double",
            term="T1",
            academic_year=self.annee,
            start_date=date(2025, 12, 1),
            end_date=date(2025, 12, 6),
        )
        self.client.force_authenticate(self.directeur)

        reponse = self.client.get(
            f"/api/exam-sessions/{vide.id}/delete-check/", **self._entetes()
        )

        self.assertTrue(reponse.data["can_delete"])

    def test_il_informe_sans_empecher(self):
        """Une ecole qui a cree une campagne en double doit pouvoir la defaire.

        L'inventaire est la pour qu'elle sache ce qu'elle fait, pas pour
        l'immobiliser.
        """
        self.client.force_authenticate(self.directeur)

        reponse = self.client.delete(
            f"/api/exam-sessions/{self.session.id}/", **self._entetes()
        )

        self.assertEqual(reponse.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(ExamSession.objects.filter(id=self.session.id).exists())


class SuppressionDUneEpreuveTests(SocleEpreuves):
    @classmethod
    def setUpTestData(cls):
        super().setUpTestData()
        cls.eleve = cls._eleve("eleve_suppr", "LEPR6A0003M", cls.sixieme)
        cls.epreuve = cls._epreuve(cls.sixieme)
        ExamResult.objects.create(
            session=cls.session,
            student=cls.eleve,
            subject=cls.maths,
            score=Decimal("11.00"),
            planning=cls.epreuve,
        )

    def test_une_epreuve_qui_porte_des_notes_ne_s_efface_pas(self):
        with self.assertRaises(RestrictedError):
            self.epreuve.delete()

    def test_la_session_entiere_s_efface_encore(self):
        """RESTRICT et non PROTECT: les notes partent dans la meme cascade,
        et PROTECT aurait refuse au motif qu'elles existent."""
        self.session.delete()

        self.assertFalse(ExamSession.objects.filter(id=self.session.id).exists())
        self.assertFalse(ExamResult.objects.filter(planning=self.epreuve.id).exists())


class RepriseDesNotesExistantesTests(APITestCase):
    """La migration rattache ce qui est certain, et ne fabrique rien.

    Rejouee sur le registre reel, comme la reprise de la migration 0059.
    """

    def setUp(self):
        self.etablissement = Etablissement.objects.create(name="Lycee Repris EPR")
        self.annee = AcademicYear.objects.create(
            name="2024-2025 REP",
            start_date=date(2024, 9, 1),
            end_date=date(2025, 7, 31),
            etablissement=self.etablissement,
        )
        self.sixieme = ClassRoom.objects.create(
            name="6ème A", academic_year=self.annee, etablissement=self.etablissement
        )
        self.cinquieme = ClassRoom.objects.create(
            name="5ème B", academic_year=self.annee, etablissement=self.etablissement
        )
        self.maths = Subject.objects.create(
            name="Mathématiques", code="MATH", coefficient=Decimal("4")
        )
        self.session = ExamSession.objects.create(
            title="Composition T1",
            term="T1",
            academic_year=self.annee,
            start_date=date(2024, 12, 1),
            end_date=date(2024, 12, 6),
        )

    def _eleve(self, username, matricule, classe):
        compte = User.objects.create_user(
            username=username,
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=self.etablissement,
        )
        return Student.objects.create(
            user=compte,
            matricule=matricule,
            classroom=classe,
            etablissement=self.etablissement,
        )

    def _epreuve(self, classe, jour=2, debut=time(8, 0), fin=time(10, 0)):
        return ExamPlanning.objects.create(
            session=self.session,
            classroom=classe,
            subject=self.maths,
            exam_date=date(2024, 12, jour),
            start_time=debut,
            end_time=fin,
        )

    def _note(self, eleve):
        return ExamResult.objects.create(
            session=self.session,
            student=eleve,
            subject=self.maths,
            score=Decimal("13.00"),
        )

    def _rejouer_la_reprise(self):
        module = importlib.import_module(
            "apps.school.migrations.0067_l_epreuve_porte_la_note"
        )
        module.rattacher_les_notes_a_leur_epreuve(registre, None)

    def test_une_note_appariable_est_rattachee(self):
        eleve = self._eleve("rep_appariable", "REP0001M", self.sixieme)
        epreuve = self._epreuve(self.sixieme)
        note = self._note(eleve)

        self._rejouer_la_reprise()

        note.refresh_from_db()
        self.assertEqual(note.planning_id, epreuve.id)

    def test_la_classe_retenue_est_celle_de_l_epoque(self):
        """`Student.classroom` est la classe d'aujourd'hui.

        La passation de fin d'annee la reecrit: pour une note de l'an
        dernier, elle ne designe pas l'epreuve que l'eleve a passee.
        """
        eleve = self._eleve("rep_passe", "REP0002M", self.cinquieme)
        epreuve_de_l_epoque = self._epreuve(self.sixieme)
        self._epreuve(self.cinquieme, jour=3)
        StudentAcademicHistory.objects.create(
            student=eleve,
            academic_year=self.annee,
            classroom=self.sixieme,
            term="T1",
        )
        note = self._note(eleve)

        self._rejouer_la_reprise()

        note.refresh_from_db()
        self.assertEqual(note.planning_id, epreuve_de_l_epoque.id)

    def test_une_note_ambigue_n_est_pas_tranchee(self):
        """Deux epreuves pour la meme classe et la meme matiere: la commande
        de dedoublonnage les conserve deliberement quand les dates different.
        """
        eleve = self._eleve("rep_ambigu", "REP0003M", self.sixieme)
        self._epreuve(self.sixieme, jour=2)
        self._epreuve(self.sixieme, jour=5, debut=time(14, 0), fin=time(16, 0))
        note = self._note(eleve)

        self._rejouer_la_reprise()

        note.refresh_from_db()
        self.assertIsNone(note.planning_id)

    def test_une_note_sans_epreuve_reste_sans_epreuve(self):
        """Celles de l'ecran Notes, qui n'a jamais cree de planning.

        Leur fabriquer une date poserait un fait que l'ecran des familles
        afficherait comme vrai.
        """
        eleve = self._eleve("rep_orphelin", "REP0004M", self.sixieme)
        note = self._note(eleve)

        self._rejouer_la_reprise()

        note.refresh_from_db()
        self.assertIsNone(note.planning_id)

    def test_une_note_orpheline_suit_encore_le_drapeau_de_sa_session(self):
        """Sans ce repli, la reprise refermerait ce que les familles
        lisaient la veille."""
        eleve = self._eleve("rep_lisible", "REP0005M", self.sixieme)
        note = self._note(eleve)
        self.session.publier_les_resultats()

        self._rejouer_la_reprise()

        compte_parent = User.objects.create_user(
            username="parent_repris",
            password="Pass1234!",
            role=UserRole.PARENT,
            etablissement=self.etablissement,
        )
        parent = ParentProfile.objects.create(
            user=compte_parent, etablissement=self.etablissement
        )
        eleve.parent = parent
        eleve.save(update_fields=["parent"])

        self.client.force_authenticate(compte_parent)
        reponse = self.client.get(
            "/api/exam-results/",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(
            {ligne["id"] for ligne in reponse.data["results"]}, {note.id}
        )


class RedressementDesHorairesTests(SimpleTestCase):
    """La contrainte refuserait les epreuves saisies a l'envers, qui existent.

    Le modele n'en portait aucune et l'ecran ne validait rien: une migration
    qui poserait la contrainte sans redresser echouerait sur des donnees
    reelles. C'est la decision qu'on verifie ici, et non son ecriture en
    base -- la contrainte interdit desormais d'y placer ces lignes.
    """

    @staticmethod
    def _redresser(debut, fin):
        module = importlib.import_module(
            "apps.school.migrations.0067_l_epreuve_porte_la_note"
        )
        return module.horaire_redresse(debut, fin)

    def test_des_horaires_inverses_sont_echanges(self):
        """10h->8h est une transposition: personne n'a voulu dire autre chose."""
        self.assertEqual(
            self._redresser(time(10, 0), time(8, 0)), (time(8, 0), time(10, 0))
        )

    def test_des_horaires_identiques_recoivent_une_duree(self):
        debut, fin = self._redresser(time(8, 0), time(8, 0))

        self.assertEqual(debut, time(8, 0))
        self.assertEqual(fin, time(10, 0))

    def test_une_epreuve_juste_n_est_pas_touchee(self):
        self.assertIsNone(self._redresser(time(8, 0), time(10, 0)))

    def test_une_epreuve_de_fin_de_journee_ne_repart_pas_a_minuit(self):
        """23h30 + 2h deborde le jour, et repartir a zero recreerait
        l'inversion que la fonction est la pour supprimer."""
        debut, fin = self._redresser(time(23, 30), time(23, 30))

        self.assertEqual(debut, time(23, 30))
        self.assertGreater(fin, debut)
