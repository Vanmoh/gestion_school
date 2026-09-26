"""Le decor de demonstration, et la barriere qui interdit de filmer le reel.

Deux commandes sont eprouvees ici, et pour deux raisons differentes.

`completer_le_decor_de_demonstration` doit etre **idempotente**: `bootstrap.sh`
appelle le peuplement a chaque montage, et une commande qui ajoute des lignes a
chaque passage finirait par decrire une ecole de mille enseignants. Son premier
etat n'etait pas idempotent -- un generateur d'alea partage avancait selon le
nombre d'objets deja crees, si bien que le second passage tombait sur d'autres
jours et d'autres ouvrages, et `get_or_create` ne retrouvait plus les siens.

`verifier_le_decor_de_demonstration` doit **refuser**. Elle s'execute avant
d'enregistrer une video qui sera publiee: sans elle, un nom d'eleve reel, un
matricule, une note ou un montant partiraient en ligne sans retour possible. Un
garde-fou dont on n'a jamais vu le refus n'en est pas un, d'ou les tests qui le
font echouer exprès.
"""

from datetime import date
from io import StringIO

from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import TestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    Payment,
    Student,
    StudentFee,
    Subject,
    Teacher,
    TeacherAssignment,
    TimetablePublication,
)


class SocleDuDecor(TestCase):
    """Le strict necessaire pour que la commande de decor ait prise.

    On ne rejoue pas `seed_demo_data` ici: il refuse de tourner sur une base
    peuplee et lit `settings.DEBUG`, que Django force a faux en test. On pose
    donc a la main l'ecole, l'annee et les classes qu'il aurait creees.
    """

    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(
            name="Établissement Démo", code="ED"
        )
        cls.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.etablissement,
            is_active=True,
        )
        cls.classes = [
            ClassRoom.objects.create(
                name=nom,
                academic_year=cls.annee,
                etablissement=cls.etablissement,
            )
            for nom in ("6A", "5B", "4C", "3D")
        ]
        for classe in cls.classes:
            for code, libelle, coefficient in (
                ("MATH", "Mathématiques", 4),
                ("FR", "Français", 3),
                ("EN", "Anglais", 2),
            ):
                Subject.objects.create(
                    name=libelle,
                    code=f"{code}-{classe.name}",
                    coefficient=coefficient,
                    classroom=classe,
                )

        # Vingt eleves aux noms que les commandes de peuplement produisent.
        cls.eleves = []
        for indice in range(20):
            compte = User.objects.create_user(
                username=f"eleve{indice:03d}",
                password="x",
                role=UserRole.STUDENT,
                first_name="Amadou",
                last_name=["TRAORE", "DIALLO", "KEITA", "COULIBALY"][indice % 4],
                etablissement=cls.etablissement,
            )
            cls.eleves.append(
                Student.objects.create(
                    user=compte,
                    matricule=f"ED{indice:05d}M",
                    classroom=cls.classes[indice % len(cls.classes)],
                    etablissement=cls.etablissement,
                )
            )

        for identifiant, role in (
            ("directeur", UserRole.DIRECTOR),
            ("enseignant1", UserRole.TEACHER),
            ("parent1", UserRole.PARENT),
            ("surveillant1", UserRole.SUPERVISOR),
        ):
            User.objects.create_user(
                username=identifiant,
                password="x",
                role=role,
                etablissement=cls.etablissement,
            )

    def _completer(self, **options):
        sortie = StringIO()
        call_command(
            "completer_le_decor_de_demonstration",
            forcer=True,
            stdout=sortie,
            **options,
        )
        return sortie.getvalue()

    @staticmethod
    def _etat_du_decor():
        """L'etat que deux passages doivent partager, ligne par ligne."""
        return {
            "enseignants": Teacher.objects.count(),
            "affectations": TeacherAssignment.objects.count(),
            "matieres_a_volume": Subject.objects.filter(weekly_slots__gt=0).count(),
            "frais": StudentFee.objects.count(),
            "encaissements": Payment.objects.count(),
            "publications": TimetablePublication.objects.count(),
        }


class LeDecorSeCompleteSansSeDoublerTests(SocleDuDecor):
    def test_le_premier_passage_garnit_l_ecole(self):
        self._completer()

        etat = self._etat_du_decor()
        self.assertEqual(etat["enseignants"], 10)
        self.assertEqual(etat["affectations"], 12)
        self.assertEqual(etat["matieres_a_volume"], 12)
        self.assertGreater(etat["encaissements"], 0)

    def test_un_second_passage_ne_double_rien(self):
        """Le defaut d'origine: l'alea dependait de ce qui existait deja."""
        self._completer()
        premier = self._etat_du_decor()

        self._completer()
        second = self._etat_du_decor()

        self.assertEqual(premier, second)

    def test_les_volumes_horaires_suivent_le_coefficient(self):
        """Sans eux, la generation d'emploi du temps n'a rien a placer.

        C'est le trou que cette commande existe pour combler:
        `Subject.weekly_slots` vaut zero par defaut et aucune autre commande ne
        le renseigne, si bien que la generation repondait « Aucune matiere a
        placer » sur une ecole par ailleurs complete.
        """
        self._completer()

        maths = Subject.objects.filter(name="Mathématiques").first()
        anglais = Subject.objects.filter(name="Anglais").first()

        self.assertGreaterEqual(maths.weekly_slots, 3)
        self.assertIn(anglais.weekly_slots, (2, 3))
        self.assertGreaterEqual(maths.weekly_slots, anglais.weekly_slots)

    def test_une_classe_reste_en_brouillon(self):
        """Sinon le bouton « Publier » n'aurait rien a publier a l'ecran."""
        self._completer()

        self.assertEqual(
            TimetablePublication.objects.filter(is_published=False).count(), 1
        )

    def test_la_meme_graine_donne_la_meme_ecole(self):
        """Une video tournee deux fois doit montrer les memes chiffres."""
        self._completer(graine=99)
        salaires = sorted(
            str(valeur)
            for valeur in Teacher.objects.values_list("salary_base", flat=True)
        )

        Teacher.objects.all().delete()
        User.objects.filter(username__startswith="demo.ens").delete()
        self._completer(graine=99)

        self.assertEqual(
            salaires,
            sorted(
                str(valeur)
                for valeur in Teacher.objects.values_list("salary_base", flat=True)
            ),
        )

    def test_elle_refuse_un_etablissement_inconnu(self):
        with self.assertRaises(CommandError):
            self._completer(etablissement="École qui n'existe pas")


class LaBarriereRefuseLesDonneesReellesTests(SocleDuDecor):
    """Ce que la barriere doit refuser, et ce qu'elle doit laisser passer."""

    def _verifier(self):
        sortie = StringIO()
        call_command(
            "verifier_le_decor_de_demonstration",
            sans_exiger_debug=True,
            stdout=sortie,
            stderr=StringIO(),
        )
        return sortie.getvalue()

    def test_elle_accepte_un_decor_complet(self):
        self._completer()

        self.assertIn("Decor de demonstration confirme", self._verifier())

    def test_elle_refuse_un_nom_d_eleve_reel(self):
        """Le controle qui compte: publier ce nom serait irreversible."""
        self._completer()
        compte = User.objects.create_user(
            username="demo.ens99",  # identifiant du decor, nom bien reel
            password="x",
            role=UserRole.STUDENT,
            first_name="Marie",
            last_name="Dupont",
            etablissement=self.etablissement,
        )
        Student.objects.create(
            user=compte,
            matricule="REEL0001F",
            classroom=self.classes[0],
            etablissement=self.etablissement,
        )

        with self.assertRaises(CommandError):
            self._verifier()

    def test_elle_refuse_un_compte_etranger_au_decor(self):
        """Un compte de direction reel signale une copie de production."""
        self._completer()
        User.objects.create_user(
            username="directrice.reelle",
            password="x",
            role=UserRole.DIRECTOR,
            etablissement=self.etablissement,
        )

        with self.assertRaises(CommandError):
            self._verifier()

    def test_elle_refuse_un_eleve_d_une_autre_ecole(self):
        self._completer()
        autre = Etablissement.objects.create(name="Lycée voisin", code="LV")
        annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=autre,
        )
        classe = ClassRoom.objects.create(
            name="Terminale", academic_year=annee, etablissement=autre
        )
        compte = User.objects.create_user(
            username="eleve900",
            password="x",
            role=UserRole.STUDENT,
            first_name="Amadou",
            last_name="TRAORE",
            etablissement=autre,
        )
        Student.objects.create(
            user=compte,
            matricule="LV00001M",
            classroom=classe,
            etablissement=autre,
        )

        with self.assertRaises(CommandError):
            self._verifier()

    def test_un_etablissement_vide_ne_gene_personne(self):
        """Une migration du depot en insere quatre, sans aucun eleve.

        Exiger un etablissement unique refusait la base de developpement pour
        rien: ce qui compte est qu'aucun **eleve** n'appartienne a une autre
        ecole que le decor.
        """
        self._completer()
        Etablissement.objects.create(name="Lycée sans élève", code="LSE")

        self.assertIn("Decor de demonstration confirme", self._verifier())

    def test_elle_refuse_une_base_trop_maigre_pour_etre_filmee(self):
        """Trente-cinq minutes de runner pour montrer des ecrans vides."""
        Student.objects.all().delete()

        with self.assertRaises(CommandError):
            self._verifier()
