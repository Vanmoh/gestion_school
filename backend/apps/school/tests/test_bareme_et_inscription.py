"""Le bareme de frais et l'inscription d'un eleve: qui attend qui.

La question se pose a chaque rentree, et elle n'avait pas de reponse ecrite:
faut-il poser le bareme avant d'inscrire, ou peut-on inscrire d'abord ?

Le depot a deja tranche, dans `apps/school/inscription.py`: la fiche de l'eleve
ne peut pas attendre le paiement, parce qu'un paiement s'accroche a un frais et
un frais a un eleve. Exiger le reglement avant la fiche s'interdirait
soi-meme -- il n'existerait aucun endroit ou enregistrer le versement.

Ces tests fixent ce que cela implique, dans les deux ordres de travail, et
nomment le seul endroit ou l'ordre compte encore.
"""

from datetime import date, timedelta
from decimal import Decimal

from django.test import TestCase

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
)


class SocleDesFrais(TestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(
            name="Lycée des barèmes", code="LBAR"
        )
        cls.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.etablissement,
            is_active=True,
        )
        cls.classe = ClassRoom.objects.create(
            name="10ème CT",
            academic_year=cls.annee,
            etablissement=cls.etablissement,
        )

    def _inscrire(self, suffixe):
        compte = User.objects.create_user(
            username=f"eleve.{suffixe}",
            password="x",
            role=UserRole.STUDENT,
            first_name="Awa",
            last_name="TRAORE",
            etablissement=self.etablissement,
        )
        return Student.objects.create(
            user=compte,
            matricule=f"LBAR{suffixe}",
            classroom=self.classe,
            etablissement=self.etablissement,
        )

    def _poser_le_bareme(self, montant=25000, occurrences=1, type_de_frais=None):
        return FeeSchedule.objects.create(
            etablissement=self.etablissement,
            academic_year=self.annee,
            classroom=self.classe,
            fee_type=type_de_frais or FeeType.REGISTRATION,
            label="Inscription",
            amount=Decimal(montant),
            first_due_date=self.annee.start_date + timedelta(days=15),
            occurrences=occurrences,
        )


class LesDeuxOrdresDeTravailTests(SocleDesFrais):
    """Poser le bareme avant ou apres: les deux doivent marcher."""

    def test_bareme_d_abord_puis_inscription(self):
        """L'ecole fixe ses tarifs en aout, inscrit en septembre."""
        bareme = self._poser_le_bareme()
        eleve = self._inscrire("001")

        bareme.appliquer()

        self.assertEqual(StudentFee.objects.filter(student=eleve).count(), 1)

    def test_inscription_d_abord_puis_bareme(self):
        """L'ecole inscrit d'abord, arrete ses tarifs ensuite.

        C'est le cas le plus frequent d'une petite ecole: on accueille, puis on
        decide. Le bareme rattrape les eleves deja inscrits.
        """
        eleve = self._inscrire("002")
        bareme = self._poser_le_bareme()

        bareme.appliquer()

        self.assertEqual(StudentFee.objects.filter(student=eleve).count(), 1)

    def test_une_fiche_s_ouvre_sans_aucun_bareme(self):
        """Le point que `inscription.py` explique: la fiche ne peut pas attendre.

        Un paiement s'accroche a un frais, et un frais a un eleve. Exiger le
        reglement avant la fiche s'interdirait soi-meme.
        """
        eleve = self._inscrire("003")

        self.assertIsNotNone(eleve.pk)
        self.assertEqual(StudentFee.objects.filter(student=eleve).count(), 0)


class CeQueLAppliquationNeFaitPasDeuxFoisTests(SocleDesFrais):
    def test_appliquer_deux_fois_ne_double_pas_les_frais(self):
        """Le bouton reste sans effet quand tout est deja facture.

        Depuis que l'inscription declenche la facturation, il ne cree plus rien
        pour un eleve arrive apres le bareme -- et c'est le but. Il garde son
        utilite pour les eleves inscrits **avant** que le tarif soit fixe.
        """
        bareme = self._poser_le_bareme()
        eleve = self._inscrire("010")

        premier = bareme.appliquer()
        second = bareme.appliquer()

        self.assertEqual(premier["crees"], 0)
        self.assertEqual(second["crees"], 0)
        self.assertEqual(StudentFee.objects.filter(student=eleve).count(), 1)

    def test_il_rattrape_les_eleves_inscrits_avant_le_bareme(self):
        """Le cas qui justifie encore le bouton."""
        eleve = self._inscrire("012")
        bareme = self._poser_le_bareme()

        resultat = bareme.appliquer()

        self.assertEqual(resultat["crees"], 1)
        self.assertEqual(StudentFee.objects.filter(student=eleve).count(), 1)

    def test_un_bareme_mensuel_pose_une_echeance_par_versement(self):
        bareme = self._poser_le_bareme(
            montant=15000, occurrences=9, type_de_frais=FeeType.MONTHLY
        )
        eleve = self._inscrire("011")

        bareme.appliquer()

        self.assertEqual(
            StudentFee.objects.filter(
                student=eleve, fee_type=FeeType.MONTHLY
            ).count(),
            9,
        )

    def test_les_echeances_s_espacent_d_un_mois(self):
        bareme = self._poser_le_bareme(
            montant=15000, occurrences=3, type_de_frais=FeeType.MONTHLY
        )

        echeances = bareme.echeances()

        self.assertEqual(len(echeances), 3)
        self.assertGreater(echeances[1], echeances[0])
        self.assertGreater(echeances[2], echeances[1])


class LeSeulEndroitOuLOrdreCompteTests(SocleDesFrais):
    """Un eleve inscrit apres coup n'a pas ses frais tant qu'on ne reapplique pas.

    C'est la seule dependance d'ordre qui subsiste, et elle est reelle: le
    bareme ne s'applique pas tout seul aux arrivees ulterieures. Une ecole qui
    inscrit en novembre doit repasser par le bouton, faute de quoi l'eleve
    n'apparait dans aucune relance -- il ne doit rien, officiellement.
    """

    def test_un_eleve_arrive_apres_l_application_est_facture_seul(self):
        """Le defaut corrige: le bareme suit desormais les arrivees.

        Auparavant, cet eleve n'avait aucun frais tant que personne ne
        recliquait sur « Appliquer » -- et l'oubli ne se voyait nulle part,
        puisqu'une facture jamais etablie ne produit aucun impaye.
        """
        bareme = self._poser_le_bareme()
        self._inscrire("020")
        bareme.appliquer()

        tardif = self._inscrire("021")

        self.assertEqual(StudentFee.objects.filter(student=tardif).count(), 1)

    def test_reappliquer_rattrape_l_eleve_tardif(self):
        bareme = self._poser_le_bareme()
        bareme.appliquer()
        tardif = self._inscrire("022")

        bareme.appliquer()

        self.assertEqual(StudentFee.objects.filter(student=tardif).count(), 1)

    def test_l_inscription_n_echoue_pas_si_un_bareme_est_incoherent(self):
        """Une inscription ne se refuse pas pour un tarif mal renseigne."""
        self._poser_le_bareme(occurrences=0)
        self._poser_le_bareme(montant=25000)

        eleve = self._inscrire("024")

        self.assertIsNotNone(eleve.pk)

    def test_un_eleve_sans_frais_n_est_pas_en_impaye(self):
        """La nuance qui compte pour la caisse.

        Sans frais emis, l'eleve ne doit rien: il n'apparait ni dans les
        relances, ni dans les impayes. Ce n'est pas une dette cachee, c'est une
        facture jamais etablie -- et c'est precisement pourquoi l'oubli se voit
        mal.
        """
        tardif = self._inscrire("023")

        du = StudentFee.objects.filter(student=tardif).count()
        regle = Payment.objects.filter(fee__student=tardif).count()

        self.assertEqual(du, 0)
        self.assertEqual(regle, 0)
