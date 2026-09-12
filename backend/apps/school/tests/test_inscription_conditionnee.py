"""L'inscription conditionnee au paiement, sans bloquer la creation.

Beaucoup d'ecoles n'ouvrent le dossier qu'apres encaissement de
l'inscription. La regle ne peut pas bloquer la creation de la fiche: un
paiement s'accroche a un frais, et un frais a un eleve. Sans fiche, il
n'existe aucun endroit ou enregistrer le versement.

C'est donc la delivrance des documents officiels qui attend le reglement.
L'appel, les notes et la discipline restent ouverts: un eleve assis en
classe doit etre pointe et note.
"""

from datetime import date
from decimal import Decimal

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.inscription import (
    documents_bloques,
    montant_regle,
    recalculer,
    seuil_a_atteindre,
)
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    FeeType,
    Payment,
    Student,
    StudentFee,
)


class _Decor:
    @classmethod
    def _monter(cls, nom, *, exige=True, minimum="10000.00"):
        cls.etablissement = Etablissement.objects.create(
            name=nom,
            code=nom[:4].upper().replace(" ", ""),
            inscription_exige_paiement=exige,
            inscription_montant_minimum=Decimal(minimum),
        )
        cls.annee = AcademicYear.objects.create(
            name=f"2025-2026 {nom[-3:]}",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
            etablissement=cls.etablissement,
        )
        cls.classe = ClassRoom.objects.create(
            name="6ème A", academic_year=cls.annee, etablissement=cls.etablissement
        )

    @classmethod
    def _eleve(cls, username):
        user = User.objects.create_user(
            username=username,
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=cls.etablissement,
        )
        return Student.objects.create(
            user=user,
            classroom=cls.classe,
            etablissement=cls.etablissement,
            gender="F",
        )

    @classmethod
    def _frais_inscription(cls, eleve, montant="25000.00"):
        return StudentFee.objects.create(
            student=eleve,
            academic_year=cls.annee,
            fee_type=FeeType.REGISTRATION,
            amount_due=Decimal(montant),
            due_date=date(2025, 10, 5),
        )

    @staticmethod
    def _verser(frais, montant):
        return Payment.objects.create(
            fee=frais,
            amount=Decimal(montant),
            method="Especes",
            etablissement=frais.student.etablissement,
        )


class StatutDInscriptionTests(_Decor, APITestCase):
    """Le statut suit la caisse, tout seul."""

    @classmethod
    def setUpTestData(cls):
        cls._monter("Etab Inscription")

    def test_un_eleve_sans_frais_est_en_regle(self):
        # Sans frais pose, il n'y a rien a payer: bloquer serait absurde,
        # et empecherait de reprendre une base existante.
        eleve = self._eleve("eleve_sans_frais")

        self.assertEqual(eleve.inscription_status, Student.Inscription.VALIDEE)
        self.assertFalse(documents_bloques(eleve))

    def test_poser_le_frais_met_l_eleve_en_attente(self):
        eleve = self._eleve("eleve_avec_frais")
        self._frais_inscription(eleve)

        eleve.refresh_from_db()
        self.assertEqual(eleve.inscription_status, Student.Inscription.EN_ATTENTE)
        self.assertTrue(documents_bloques(eleve))

    def test_un_acompte_insuffisant_ne_libere_rien(self):
        eleve = self._eleve("eleve_acompte_court")
        frais = self._frais_inscription(eleve)
        self._verser(frais, "4000.00")

        eleve.refresh_from_db()
        self.assertEqual(eleve.inscription_status, Student.Inscription.EN_ATTENTE)

    def test_atteindre_le_plancher_valide_l_inscription(self):
        # 10 000 F suffisent sur un frais de 25 000 F: c'est tout l'interet
        # d'un plancher, accepter le paiement en deux fois.
        eleve = self._eleve("eleve_acompte_suffisant")
        frais = self._frais_inscription(eleve)
        self._verser(frais, "10000.00")

        eleve.refresh_from_db()
        self.assertEqual(eleve.inscription_status, Student.Inscription.VALIDEE)
        self.assertFalse(documents_bloques(eleve))

    def test_annuler_le_versement_remet_en_attente(self):
        eleve = self._eleve("eleve_annulation")
        frais = self._frais_inscription(eleve)
        versement = self._verser(frais, "10000.00")
        versement.cancel(reason="Cheque sans provision")

        eleve.refresh_from_db()
        self.assertEqual(eleve.inscription_status, Student.Inscription.EN_ATTENTE)

    def test_le_plancher_ne_depasse_jamais_ce_qui_est_du(self):
        # Un plancher de 10 000 F sur un frais de 5 000 F rendrait
        # l'inscription impossible a solder.
        eleve = self._eleve("eleve_petit_frais")
        frais = self._frais_inscription(eleve, "5000.00")

        self.assertEqual(seuil_a_atteindre(eleve), Decimal("5000.00"))
        self._verser(frais, "5000.00")
        eleve.refresh_from_db()
        self.assertEqual(eleve.inscription_status, Student.Inscription.VALIDEE)

    def test_les_frais_mensuels_ne_comptent_pas(self):
        # Seule l'inscription conditionne l'inscription. Payer la scolarite
        # de novembre ne dit rien du droit d'entree.
        eleve = self._eleve("eleve_mensualite")
        self._frais_inscription(eleve)
        mensuel = StudentFee.objects.create(
            student=eleve,
            academic_year=self.annee,
            fee_type=FeeType.MONTHLY,
            amount_due=Decimal("30000.00"),
            due_date=date(2025, 11, 5),
        )
        self._verser(mensuel, "30000.00")

        eleve.refresh_from_db()
        self.assertEqual(eleve.inscription_status, Student.Inscription.EN_ATTENTE)
        self.assertEqual(montant_regle(eleve), Decimal("0"))


class RegleDesactiveeTests(_Decor, APITestCase):
    """Une ecole qui ne demande rien ne doit rien voir changer."""

    @classmethod
    def setUpTestData(cls):
        cls._monter("Etab Sans Regle", exige=False)

    def test_le_frais_impaye_ne_bloque_rien(self):
        eleve = self._eleve("eleve_ecole_libre")
        self._frais_inscription(eleve)

        eleve.refresh_from_db()
        self.assertEqual(eleve.inscription_status, Student.Inscription.VALIDEE)
        self.assertFalse(documents_bloques(eleve))


class DispenseTests(_Decor, APITestCase):
    """La remise se decide, elle ne se constate pas."""

    @classmethod
    def setUpTestData(cls):
        cls._monter("Etab Dispense")
        cls.directeur = User.objects.create_user(
            username="dir_dispense",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.etablissement,
        )
        cls.comptable = User.objects.create_user(
            username="cpt_dispense",
            password="Pass1234!",
            role=UserRole.ACCOUNTANT,
            etablissement=cls.etablissement,
        )

    def setUp(self):
        super().setUp()
        self.eleve = self._eleve("eleve_boursier")
        self._frais_inscription(self.eleve)
        self.eleve.refresh_from_db()

    def _dispenser(self, **charge):
        return self.client.post(
            f"/api/students/{self.eleve.id}/dispense-inscription/",
            charge,
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

    def test_la_direction_dispense_et_laisse_sa_trace(self):
        self.client.force_authenticate(self.directeur)

        reponse = self._dispenser(motif="Boursière de l'État")

        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        self.eleve.refresh_from_db()
        self.assertEqual(self.eleve.inscription_status, Student.Inscription.EXEMPTEE)
        self.assertEqual(self.eleve.inscription_exempted_by, self.directeur)
        self.assertIn("Boursière", self.eleve.inscription_exempted_reason)
        self.assertIsNotNone(self.eleve.inscription_exempted_at)
        self.assertFalse(documents_bloques(self.eleve))

    def test_un_motif_vide_est_refuse(self):
        # « Dispense » sans plus ne se relit pas six mois plus tard.
        self.client.force_authenticate(self.directeur)

        self.assertEqual(
            self._dispenser(motif="").status_code, status.HTTP_400_BAD_REQUEST
        )

    def test_la_comptabilite_ne_dispense_pas(self):
        # Elle enregistre les versements, elle ne decide pas des remises.
        self.client.force_authenticate(self.comptable)

        reponse = self._dispenser(motif="Arrangement")

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)
        self.eleve.refresh_from_db()
        self.assertEqual(self.eleve.inscription_status, Student.Inscription.EN_ATTENTE)

    def test_la_dispense_resiste_au_recalcul(self):
        # Un versement partiel ne doit pas ramener un boursier en attente.
        self.client.force_authenticate(self.directeur)
        self._dispenser(motif="Orphelin")
        self.eleve.refresh_from_db()

        recalculer(self.eleve)

        self.eleve.refresh_from_db()
        self.assertEqual(self.eleve.inscription_status, Student.Inscription.EXEMPTEE)

    def test_lever_la_dispense_remet_la_caisse_au_travail(self):
        self.client.force_authenticate(self.directeur)
        self._dispenser(motif="Erreur de saisie")

        reponse = self._dispenser(lever=True)

        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        self.eleve.refresh_from_db()
        self.assertEqual(self.eleve.inscription_status, Student.Inscription.EN_ATTENTE)
        self.assertEqual(self.eleve.inscription_exempted_reason, "")
        self.assertIsNone(self.eleve.inscription_exempted_by)

    def test_le_statut_ne_se_change_pas_par_un_patch(self):
        # Sans cette garde, un PATCH sur la fiche suffisait a se declarer en
        # regle et a rouvrir les bulletins.
        self.client.force_authenticate(self.directeur)

        self.client.patch(
            f"/api/students/{self.eleve.id}/",
            {"inscription_status": Student.Inscription.VALIDEE},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.eleve.refresh_from_db()
        self.assertEqual(self.eleve.inscription_status, Student.Inscription.EN_ATTENTE)


class DocumentsRetenusTests(_Decor, APITestCase):
    """Ce qui se ferme, et ce qui reste ouvert."""

    @classmethod
    def setUpTestData(cls):
        cls._monter("Etab Documents")
        cls.directeur = User.objects.create_user(
            username="dir_documents",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.etablissement,
        )

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.directeur)
        self.a_jour = self._eleve("eleve_a_jour")
        self.en_attente = self._eleve("eleve_en_attente")
        frais = self._frais_inscription(self.a_jour)
        self._verser(frais, "25000.00")
        self._frais_inscription(self.en_attente)
        self.a_jour.refresh_from_db()
        self.en_attente.refresh_from_db()

    def _entetes(self):
        return {"HTTP_X_ETABLISSEMENT_ID": str(self.etablissement.id)}

    def test_le_bulletin_est_retenu_et_dit_le_montant(self):
        reponse = self.client.get(
            f"/api/reports/bulletin/{self.en_attente.id}/{self.annee.id}/T1/",
            **self._entetes(),
        )

        self.assertEqual(reponse.status_code, 402)
        self.assertIn("25", str(reponse.data["detail"]))

    def test_la_carte_scolaire_est_retenue(self):
        reponse = self.client.get(
            f"/api/reports/student-card/{self.en_attente.id}/", **self._entetes()
        )

        self.assertEqual(reponse.status_code, 402)

    def test_l_eleve_a_jour_recoit_ses_documents(self):
        bulletin = self.client.get(
            f"/api/reports/bulletin/{self.a_jour.id}/{self.annee.id}/T1/",
            **self._entetes(),
        )
        carte = self.client.get(
            f"/api/reports/student-card/{self.a_jour.id}/", **self._entetes()
        )

        self.assertEqual(bulletin.status_code, status.HTTP_200_OK)
        self.assertEqual(carte.status_code, status.HTTP_200_OK)

    def test_une_impression_de_classe_saute_l_eleve_en_attente(self):
        # Retenir trente cartes parce qu'un seul n'a pas paye punirait ceux
        # qui sont en regle.
        reponse = self.client.get(
            f"/api/reports/student-cards/class/{self.classe.id}/", **self._entetes()
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)

    def test_l_envoi_whatsapp_annonce_le_montant_manquant(self):
        reponse = self.client.get(
            f"/api/reports/bulletin/{self.en_attente.id}/{self.annee.id}/T1/whatsapp/",
            **self._entetes(),
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertFalse(reponse.data["can_send"])
        self.assertIn("Inscription", reponse.data["blocked_reason"])

    def test_une_dispense_rouvre_les_documents(self):
        self.client.post(
            f"/api/students/{self.en_attente.id}/dispense-inscription/",
            {"motif": "Enfant du personnel"},
            format="json",
            **self._entetes(),
        )

        reponse = self.client.get(
            f"/api/reports/student-card/{self.en_attente.id}/", **self._entetes()
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
