"""Le barème de frais: poser une année de scolarité en un geste.

Sans lui, ouvrir une année voulait dire créer les frais un par un. Une école
de cinq cents élèves avec une inscription et neuf mensualités, cela fait cinq
mille saisies: la comptable ne pouvait pas démarrer l'année dans
l'application, et c'était le blocage le plus concret avant une rentrée.

Ce qui suit fixe les propriétés dont dépend cet usage: l'application produit
les bons frais, elle se rejoue sans doublonner (un élève inscrit en janvier
doit pouvoir être rattrapé), et elle refuse un barème dont les échéances
sortent de l'année scolaire.
"""

from datetime import date
from decimal import Decimal

from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    FeeSchedule,
    FeeType,
    Payment,
    Student,
    StudentFee,
    _ajouter_des_mois,
)


class DecorDeBareme:
    def setUp(self):
        self.etablissement = Etablissement.objects.create(name="Lycee des Frais")
        self.autre = Etablissement.objects.create(name="Lycee Voisin")
        self.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 10, 1),
            end_date=date(2026, 6, 30),
            is_active=True,
            etablissement=self.etablissement,
        )
        self.sixieme = ClassRoom.objects.create(
            name="6A", academic_year=self.annee, etablissement=self.etablissement
        )
        self.cinquieme = ClassRoom.objects.create(
            name="5A", academic_year=self.annee, etablissement=self.etablissement
        )
        self.comptable = User.objects.create_user(
            username="comptable_frais",
            password="Pass1234!",
            role=UserRole.ACCOUNTANT,
            etablissement=self.etablissement,
        )
        self.enseignant = User.objects.create_user(
            username="enseignant_frais",
            password="Pass1234!",
            role=UserRole.TEACHER,
            etablissement=self.etablissement,
        )

    def _eleve(self, matricule, classe=None, archive=False):
        user = User.objects.create_user(
            username=f"eleve_{matricule}",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=self.etablissement,
        )
        return Student.objects.create(
            user=user,
            matricule=matricule,
            classroom=classe or self.sixieme,
            etablissement=self.etablissement,
            is_archived=archive,
        )

    def _bareme(self, **extra):
        donnees = {
            "etablissement": self.etablissement,
            "academic_year": self.annee,
            "classroom": self.sixieme,
            "fee_type": FeeType.MONTHLY,
            "amount": Decimal("10000"),
            "first_due_date": date(2025, 10, 5),
            "occurrences": 9,
        }
        donnees.update(extra)
        return FeeSchedule.objects.create(**donnees)


class DecalageDesMoisTests(APITestCase):
    def test_le_pas_est_d_un_mois(self):
        self.assertEqual(_ajouter_des_mois(date(2025, 10, 5), 3), date(2026, 1, 5))

    def test_un_31_ne_devient_pas_une_date_impossible(self):
        """31 janvier + 1 mois n'est pas le 31 février."""
        self.assertEqual(_ajouter_des_mois(date(2026, 1, 31), 1), date(2026, 2, 28))

    def test_le_passage_a_l_annee_suivante_ne_decale_pas(self):
        """Le piège classique de l'arithmétique modulo sur des mois 1-12."""
        self.assertEqual(_ajouter_des_mois(date(2025, 12, 10), 1), date(2026, 1, 10))
        self.assertEqual(_ajouter_des_mois(date(2025, 11, 10), 2), date(2026, 1, 10))


class ApplicationDuBaremeTests(DecorDeBareme, APITestCase):
    def test_elle_cree_une_echeance_par_mois_et_par_eleve(self):
        self._eleve("F001")
        self._eleve("F002")
        bareme = self._bareme(occurrences=9)

        resultat = bareme.appliquer()

        self.assertEqual(resultat["crees"], 18)
        self.assertEqual(StudentFee.objects.count(), 18)
        self.assertEqual(
            sorted(StudentFee.objects.filter(student__matricule="F001").values_list("due_date", flat=True)),
            [_ajouter_des_mois(date(2025, 10, 5), rang) for rang in range(9)],
        )

    def test_un_frais_unique_ne_produit_qu_une_echeance(self):
        self._eleve("F001")
        bareme = self._bareme(
            fee_type=FeeType.REGISTRATION,
            amount=Decimal("25000"),
            occurrences=1,
        )

        bareme.appliquer()

        self.assertEqual(StudentFee.objects.count(), 1)
        self.assertEqual(StudentFee.objects.get().amount_due, Decimal("25000"))

    def test_la_rejouer_ne_double_pas_les_frais(self):
        """C'est ce qui permet de rattraper un élève inscrit en janvier."""
        self._eleve("F001")
        bareme = self._bareme(occurrences=3)
        bareme.appliquer()

        nouveau = self._eleve("F002")
        resultat = bareme.appliquer()

        self.assertEqual(resultat["crees"], 3)
        self.assertEqual(resultat["deja_en_place"], 3)
        self.assertEqual(StudentFee.objects.filter(student=nouveau).count(), 3)
        self.assertEqual(StudentFee.objects.count(), 6)

    def test_un_eleve_archive_ne_recoit_pas_de_frais(self):
        self._eleve("F001", archive=True)
        bareme = self._bareme(occurrences=2)

        resultat = bareme.appliquer()

        self.assertEqual(resultat["crees"], 0)

    def test_un_bareme_sans_classe_vise_toute_l_annee(self):
        self._eleve("F001", classe=self.sixieme)
        self._eleve("F002", classe=self.cinquieme)
        bareme = self._bareme(classroom=None, occurrences=1)

        resultat = bareme.appliquer()

        self.assertEqual(resultat["eleves"], 2)
        self.assertEqual(StudentFee.objects.count(), 2)

    def test_il_ne_deborde_pas_sur_une_autre_classe(self):
        self._eleve("F001", classe=self.sixieme)
        self._eleve("F002", classe=self.cinquieme)
        bareme = self._bareme(classroom=self.sixieme, occurrences=1)

        bareme.appliquer()

        self.assertEqual(StudentFee.objects.count(), 1)
        self.assertEqual(StudentFee.objects.get().student.matricule, "F001")


class ApiDuBaremeTests(DecorDeBareme, APITestCase):
    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.comptable)

    def _charge(self, **extra):
        donnees = {
            "academic_year": self.annee.id,
            "classroom": self.sixieme.id,
            "fee_type": FeeType.MONTHLY,
            "amount": "10000",
            "first_due_date": "2025-10-05",
            "occurrences": 9,
        }
        donnees.update(extra)
        return donnees

    def test_le_comptable_peut_creer_un_bareme(self):
        reponse = self.client.post("/api/fee-schedules/", self._charge(), format="json")

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED)
        self.assertEqual(reponse.data["etablissement"], self.etablissement.id)

    def test_l_enseignant_ne_peut_pas(self):
        self.client.force_authenticate(self.enseignant)

        reponse = self.client.post("/api/fee-schedules/", self._charge(), format="json")

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)

    def test_une_echeance_hors_de_l_annee_est_refusee(self):
        """Un frais daté hors de l'année sort des journaux et des relances."""
        reponse = self.client.post(
            "/api/fee-schedules/", self._charge(occurrences=12), format="json"
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("occurrences", reponse.data)

    def test_une_premiere_echeance_avant_la_rentree_est_refusee(self):
        reponse = self.client.post(
            "/api/fee-schedules/",
            self._charge(first_due_date="2025-08-01", occurrences=1),
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("first_due_date", reponse.data)

    def test_une_classe_d_une_autre_annee_est_refusee(self):
        autre_annee = AcademicYear.objects.create(
            name="2024-2025",
            start_date=date(2024, 10, 1),
            end_date=date(2025, 6, 30),
            etablissement=self.etablissement,
        )
        classe_ancienne = ClassRoom.objects.create(
            name="6A ancienne",
            academic_year=autre_annee,
            etablissement=self.etablissement,
        )

        reponse = self.client.post(
            "/api/fee-schedules/",
            self._charge(classroom=classe_ancienne.id),
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("classroom", reponse.data)

    def test_un_montant_nul_est_refuse(self):
        reponse = self.client.post(
            "/api/fee-schedules/", self._charge(amount="0"), format="json"
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_l_apercu_annonce_ce_qui_sera_cree_sans_rien_ecrire(self):
        self._eleve("F001")
        self._eleve("F002")
        bareme = self._bareme(occurrences=9)

        reponse = self.client.get(f"/api/fee-schedules/{bareme.id}/apercu/")

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertEqual(reponse.data["eleves_concernes"], 2)
        self.assertEqual(len(reponse.data["echeances"]), 9)
        self.assertEqual(reponse.data["montant_par_eleve"], Decimal("90000"))
        self.assertEqual(reponse.data["montant_total"], Decimal("180000"))
        self.assertEqual(reponse.data["frais_a_creer"], 18)
        self.assertEqual(StudentFee.objects.count(), 0)

    def test_appliquer_cree_les_frais(self):
        self._eleve("F001")
        bareme = self._bareme(occurrences=3)

        reponse = self.client.post(f"/api/fee-schedules/{bareme.id}/appliquer/")

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertEqual(reponse.data["crees"], 3)
        self.assertEqual(StudentFee.objects.count(), 3)

    def test_appliquer_tout_traite_les_baremes_de_l_annee(self):
        self._eleve("F001", classe=self.sixieme)
        self._eleve("F002", classe=self.cinquieme)
        self._bareme(classroom=self.sixieme, occurrences=2)
        self._bareme(
            classroom=self.cinquieme,
            fee_type=FeeType.REGISTRATION,
            occurrences=1,
        )

        reponse = self.client.post(
            "/api/fee-schedules/appliquer-tout/",
            {"academic_year": self.annee.id},
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertEqual(reponse.data["baremes"], 2)
        self.assertEqual(reponse.data["crees"], 3)

    def test_l_enseignant_ne_peut_pas_appliquer(self):
        bareme = self._bareme()
        self.client.force_authenticate(self.enseignant)

        reponse = self.client.post(f"/api/fee-schedules/{bareme.id}/appliquer/")

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)

    def test_supprimer_un_bareme_conserve_les_frais_deja_encaisses(self):
        eleve = self._eleve("F001")
        bareme = self._bareme(occurrences=1)
        bareme.appliquer()
        frais = StudentFee.objects.get(student=eleve)
        Payment.objects.create(
            fee=frais,
            amount=Decimal("10000"),
            method="Especes",
            etablissement=self.etablissement,
        )

        reponse = self.client.delete(f"/api/fee-schedules/{bareme.id}/")

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertIn("paiements", str(reponse.data.get("detail", "")))
        frais.refresh_from_db()
        self.assertIsNone(frais.schedule_id)
        self.assertEqual(frais.payments.count(), 1)

    def test_un_bareme_d_un_autre_etablissement_reste_invisible(self):
        annee_voisine = AcademicYear.objects.create(
            name="2025-2026 voisin",
            start_date=date(2025, 10, 1),
            end_date=date(2026, 6, 30),
            etablissement=self.autre,
        )
        FeeSchedule.objects.create(
            etablissement=self.autre,
            academic_year=annee_voisine,
            fee_type=FeeType.MONTHLY,
            amount=Decimal("5000"),
            first_due_date=date(2025, 10, 5),
        )
        self._bareme()

        reponse = self.client.get("/api/fee-schedules/")

        self.assertEqual(reponse.data["count"], 1)


class ImportDeFraisTests(DecorDeBareme, APITestCase):
    """L'autre moitié du besoin: les cas particuliers.

    Le barème couvre le cas général -- toute une classe, même montant. Une
    école a toujours le reste: un tarif négocié, une bourse partielle, un
    élève arrivé en cours d'année avec son propre échéancier.
    """

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.comptable)
        self.eleve = self._eleve("F001")

    def _fichier(self, lignes, nom="frais.csv"):
        entete = "student_matricule,fee_type,amount_due,due_date\n"
        contenu = entete + "".join(f"{ligne}\n" for ligne in lignes)
        return SimpleUploadedFile(nom, contenu.encode("utf-8"), content_type="text/csv")

    def _importer(self, lignes, **extra):
        charge = {
            "academic_year": self.annee.id,
            "file": self._fichier(lignes),
        }
        charge.update(extra)
        return self.client.post(
            "/api/fees/import-fees/", charge, format="multipart"
        )

    def test_il_cree_les_frais_du_fichier(self):
        reponse = self._importer(["F001,registration,25000,2025-10-15"])

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertEqual(reponse.data["created"], 1)
        frais = StudentFee.objects.get()
        self.assertEqual(frais.amount_due, Decimal("25000"))
        self.assertEqual(frais.fee_type, FeeType.REGISTRATION)
        self.assertEqual(frais.due_date, date(2025, 10, 15))

    def test_le_type_se_lit_en_francais(self):
        """Le fichier vient d'un tableur rempli à la main."""
        reponse = self._importer(["F001,Inscription,25000,15/10/2025"])

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertEqual(StudentFee.objects.get().fee_type, FeeType.REGISTRATION)

    def test_une_ligne_fausse_annule_tout_l_import(self):
        """Un import à moitié passé laisse une comptabilité indéchiffrable."""
        reponse = self._importer(
            [
                "F001,registration,25000,2025-10-15",
                "INCONNU,registration,25000,2025-10-15",
            ]
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(StudentFee.objects.count(), 0)

    def test_une_echeance_hors_de_l_annee_est_signalee(self):
        reponse = self._importer(["F001,registration,25000,2027-01-15"])

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("hors de l'année", str(reponse.data))

    def test_un_montant_negatif_est_signale(self):
        reponse = self._importer(["F001,registration,-500,2025-10-15"])

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("Montant invalide", str(reponse.data))

    def test_un_type_inconnu_est_signale(self):
        reponse = self._importer(["F001,cantine,5000,2025-10-15"])

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("Type de frais invalide", str(reponse.data))

    def test_une_ligne_en_double_dans_le_fichier_est_signalee(self):
        reponse = self._importer(
            [
                "F001,registration,25000,2025-10-15",
                "F001,registration,25000,2025-10-15",
            ]
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("double", str(reponse.data))

    def test_reimporter_le_meme_fichier_ne_double_pas_les_frais(self):
        self._importer(["F001,registration,25000,2025-10-15"])

        reponse = self._importer(["F001,registration,25000,2025-10-15"])

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertEqual(reponse.data["created"], 0)
        self.assertEqual(reponse.data["ignored"], 1)
        self.assertEqual(StudentFee.objects.count(), 1)

    def test_un_eleve_d_un_autre_etablissement_n_est_pas_atteignable(self):
        user = User.objects.create_user(
            username="eleve_voisin",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=self.autre,
        )
        Student.objects.create(
            user=user, matricule="V001", etablissement=self.autre
        )

        reponse = self._importer(["V001,registration,25000,2025-10-15"])

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("Aucun élève", str(reponse.data))

    def test_l_enseignant_ne_peut_pas_importer(self):
        self.client.force_authenticate(self.enseignant)

        reponse = self._importer(["F001,registration,25000,2025-10-15"])

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)

    def test_le_modele_de_fichier_se_telecharge(self):
        reponse = self.client.get("/api/fees/import-template/?format=csv")

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertIn("student_matricule", reponse.content.decode("utf-8"))


class FraisSaisiAlaMainTests(DecorDeBareme, APITestCase):
    """Créer un frais à la main doit rester possible.

    Régression rencontrée en ajoutant le barème: la contrainte d'unicité
    (élève, barème, échéance) est traduite par DRF en validateur de
    serializer, et un validateur d'unicité exige *tous* les champs qu'il
    couvre — même ceux que le modèle accepte à vide. Toute création de frais
    répondait alors « schedule: ce champ est obligatoire », y compris depuis
    l'écran de saisie, qui ne connaît aucun barème.
    """

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.comptable)
        self.eleve = self._eleve("F001")

    def test_un_frais_se_cree_sans_bareme(self):
        reponse = self.client.post(
            "/api/fees/",
            {
                "student": self.eleve.id,
                "academic_year": self.annee.id,
                "fee_type": FeeType.REGISTRATION,
                "amount_due": "25000",
                "due_date": "2025-10-15",
            },
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED)
        self.assertIsNone(StudentFee.objects.get().schedule_id)

    def test_le_rattachement_au_bareme_ne_se_saisit_pas(self):
        """C'est `appliquer()` qui l'écrit, jamais une saisie."""
        bareme = self._bareme(occurrences=1)

        reponse = self.client.post(
            "/api/fees/",
            {
                "student": self.eleve.id,
                "academic_year": self.annee.id,
                "fee_type": FeeType.REGISTRATION,
                "amount_due": "25000",
                "due_date": "2025-10-15",
                "schedule": bareme.id,
            },
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED)
        self.assertIsNone(StudentFee.objects.get().schedule_id)

    def test_la_contrainte_protege_toujours_en_base(self):
        """Le validateur retiré ne doit pas emporter la garantie de la base."""
        from django.db import IntegrityError, transaction

        bareme = self._bareme(occurrences=1)
        bareme.appliquer()
        existant = StudentFee.objects.get(schedule=bareme)

        with self.assertRaises(IntegrityError):
            with transaction.atomic():
                StudentFee.objects.create(
                    student=self.eleve,
                    academic_year=self.annee,
                    fee_type=existant.fee_type,
                    amount_due=existant.amount_due,
                    due_date=existant.due_date,
                    schedule=bareme,
                )


class EcartsApresChangementDeClasseTests(DecorDeBareme, APITestCase):
    """Un élève change de classe, ses frais restent ceux de l'ancienne.

    Réorientation, classe dédoublée, erreur d'affectation corrigée: l'élève
    passe en 5A et continue de payer le tarif de la 6A. Si les tarifs
    diffèrent, sa facture est fausse — et rien ne le signalait.

    Le contrôle ne corrige rien: ces frais portent souvent des paiements déjà
    encaissés, et réécrire un montant sous un règlement se rattrape mal.
    """

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.comptable)
        self.eleve = self._eleve("F001", classe=self.sixieme)
        self.bareme_sixieme = self._bareme(
            classroom=self.sixieme, amount=Decimal("10000"), occurrences=1
        )
        self.bareme_sixieme.appliquer()

    def _ecarts(self):
        reponse = self.client.get("/api/fee-schedules/ecarts/")
        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        return reponse.data

    def test_sans_changement_de_classe_aucun_ecart(self):
        self.assertEqual(self._ecarts()["count"], 0)

    def test_un_changement_de_classe_fait_apparaitre_l_ecart(self):
        self.eleve.classroom = self.cinquieme
        self.eleve.save(update_fields=["classroom", "updated_at"])

        donnees = self._ecarts()

        self.assertEqual(donnees["count"], 1)
        ligne = donnees["resultats"][0]
        self.assertEqual(ligne["classe_actuelle"], "5A")
        self.assertEqual(ligne["classe_du_bareme"], "6A")
        self.assertEqual(Decimal(str(ligne["montant_facture"])), Decimal("10000"))

    def test_il_annonce_le_tarif_de_la_classe_actuelle(self):
        """C'est le chiffre qui permet de trancher."""
        self._bareme(
            classroom=self.cinquieme, amount=Decimal("15000"), occurrences=1
        )
        self.eleve.classroom = self.cinquieme
        self.eleve.save(update_fields=["classroom", "updated_at"])

        ligne = self._ecarts()["resultats"][0]

        self.assertEqual(Decimal(str(ligne["montant_de_sa_classe"])), Decimal("15000"))
        self.assertEqual(Decimal(str(ligne["ecart"])), Decimal("5000"))

    def test_sans_bareme_dans_la_nouvelle_classe_l_ecart_reste_inconnu(self):
        self.eleve.classroom = self.cinquieme
        self.eleve.save(update_fields=["classroom", "updated_at"])

        ligne = self._ecarts()["resultats"][0]

        self.assertIsNone(ligne["montant_de_sa_classe"])
        self.assertIsNone(ligne["ecart"])

    def test_un_frais_deja_regle_est_signale_comme_tel(self):
        """Ce qui distingue une erreur de saisie d'un remboursement."""
        frais = StudentFee.objects.get(student=self.eleve)
        Payment.objects.create(
            fee=frais,
            amount=Decimal("10000"),
            method="Especes",
            etablissement=self.etablissement,
        )
        self.eleve.classroom = self.cinquieme
        self.eleve.save(update_fields=["classroom", "updated_at"])

        donnees = self._ecarts()

        self.assertEqual(donnees["avec_paiement"], 1)
        self.assertTrue(donnees["resultats"][0]["porte_un_paiement"])

    def test_un_bareme_sans_classe_ne_produit_aucun_ecart(self):
        """Il vise toute l'année: changer de classe n'y change rien."""
        StudentFee.objects.all().delete()
        commun = self._bareme(classroom=None, occurrences=1)
        commun.appliquer()
        self.eleve.classroom = self.cinquieme
        self.eleve.save(update_fields=["classroom", "updated_at"])

        self.assertEqual(self._ecarts()["count"], 0)

    def test_le_controle_ne_modifie_rien(self):
        self.eleve.classroom = self.cinquieme
        self.eleve.save(update_fields=["classroom", "updated_at"])
        avant = StudentFee.objects.get(student=self.eleve).amount_due

        self._ecarts()

        self.assertEqual(StudentFee.objects.get(student=self.eleve).amount_due, avant)

    def test_l_enseignant_n_y_a_pas_acces(self):
        self.client.force_authenticate(self.enseignant)

        reponse = self.client.get("/api/fee-schedules/ecarts/")

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)
