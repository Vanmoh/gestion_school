"""Un pointage suppose quelque chose a assurer.

Pointer quelqu'un dit « il etait la ». Emarger dit « il a couvert ces
seances ». Les deux supposent des cours: quelqu'un qui ne tient aucune matiere
n'en a **aucun jour**, donc ni presence a constater ni seance a couvrir.

Depuis `signals._ne_pointer_que_ceux_qui_enseignent`, la base refuse d'en
creer. Mais les lignes anterieures a la regle sont restees -- 20 pointages et
14 emargements sur la base reelle, tous portes par un seul compte -- et elles
faussent la charge horaire, la concordance, et le calcul de paie:
`_teacher_hours_worked` comptait des heures travaillees sur des seances qui
n'ont jamais existe.

`controler_la_dotation` les signalait sans pouvoir les corriger. Cette commande
est le remede manquant.
"""

from datetime import date, time
from decimal import Decimal

from django.core.management import call_command
from django.test import TestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    Subject,
    Teacher,
    TeacherAssignment,
    TeacherAttendance,
    TeacherTimeEntry,
)


class SoclePointages(TestCase):
    @classmethod
    def setUpTestData(cls):
        cls.ecole = Etablissement.objects.create(name="École A", code="ECA")
        cls.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.ecole,
            is_active=True,
        )
        cls.classe = ClassRoom.objects.create(
            name="6ème", academic_year=cls.annee, etablissement=cls.ecole
        )
        cls.matiere = Subject.objects.create(
            name="Mathématiques",
            code="MA",
            coefficient=Decimal(4),
            classroom=cls.classe,
        )

        cls.titulaire = cls._enseignant("titulaire", "ECA-01")
        TeacherAssignment.objects.create(
            teacher=cls.titulaire, subject=cls.matiere, classroom=cls.classe
        )
        cls.sans_matiere = cls._enseignant("orphelin", "ECA-02")

    @classmethod
    def _enseignant(cls, suffixe, code):
        compte = User.objects.create_user(
            username=f"eca.{suffixe}",
            password="x",
            role=UserRole.TEACHER,
            last_name=suffixe.upper(),
            etablissement=cls.ecole,
        )
        return Teacher.objects.create(
            user=compte,
            employee_code=code,
            hire_date=date(2024, 9, 1),
            etablissement=cls.ecole,
        )

    def _pointer(self, enseignant, combien):
        """Ecriture directe: le `pre_save` refuserait l'enseignant sans matiere.

        C'est bien la preuve que la regle tient -- et la raison pour laquelle
        les lignes anterieures a cette regle ne peuvent etre retirees que par
        une commande.
        """
        lignes = [
            TeacherAttendance(teacher=enseignant, date=date(2025, 10, 1 + rang))
            for rang in range(combien)
        ]
        TeacherAttendance.objects.bulk_create(lignes)

    def _emarger(self, enseignant, combien):
        lignes = [
            TeacherTimeEntry(
                teacher=enseignant,
                etablissement=enseignant.etablissement,
                entry_date=date(2025, 10, 1 + rang),
                check_in_time=time(8, 0),
            )
            for rang in range(combien)
        ]
        TeacherTimeEntry.objects.bulk_create(lignes)


class LeRetraitTests(SoclePointages):
    def test_un_essai_a_blanc_n_efface_rien(self):
        self._pointer(self.sans_matiere, 3)

        call_command("retirer_les_pointages_sans_matiere")

        self.assertEqual(TeacherAttendance.objects.count(), 3)

    def test_appliquer_retire_les_pointages_de_celui_qui_n_enseigne_rien(self):
        self._pointer(self.sans_matiere, 3)
        self._emarger(self.sans_matiere, 2)

        call_command("retirer_les_pointages_sans_matiere", "--appliquer")

        self.assertEqual(TeacherAttendance.objects.count(), 0)
        self.assertEqual(TeacherTimeEntry.objects.count(), 0)

    def test_le_titulaire_garde_les_siens(self):
        """La garde la plus importante: ne pas confondre les deux enseignants.

        Un titulaire pointe legitimement. Une commande qui retirerait ses lignes
        detruirait la base de son salaire.
        """
        self._pointer(self.titulaire, 4)
        self._emarger(self.titulaire, 3)
        self._pointer(self.sans_matiere, 2)

        call_command("retirer_les_pointages_sans_matiere", "--appliquer")

        self.assertEqual(
            TeacherAttendance.objects.filter(teacher=self.titulaire).count(), 4
        )
        self.assertEqual(
            TeacherTimeEntry.objects.filter(teacher=self.titulaire).count(), 3
        )
        self.assertEqual(
            TeacherAttendance.objects.filter(teacher=self.sans_matiere).count(), 0
        )

    def test_l_enseignant_lui_meme_n_est_pas_supprime(self):
        """Retirer un pointage n'est pas retirer une personne.

        `retirer_les_enseignants_sans_matiere` s'en charge, et c'est une
        decision separee: un enseignant sans matiere cette annee peut en
        reprendre une la prochaine.
        """
        self._pointer(self.sans_matiere, 2)

        call_command("retirer_les_pointages_sans_matiere", "--appliquer")

        self.assertTrue(Teacher.objects.filter(id=self.sans_matiere.id).exists())

    def test_une_autre_ecole_n_est_pas_touchee(self):
        voisine = Etablissement.objects.create(name="École B", code="ECB")
        compte = User.objects.create_user(
            username="ecb.orphelin",
            password="x",
            role=UserRole.TEACHER,
            etablissement=voisine,
        )
        chez_la_voisine = Teacher.objects.create(
            user=compte,
            employee_code="ECB-01",
            hire_date=date(2024, 9, 1),
            etablissement=voisine,
        )
        self._pointer(chez_la_voisine, 3)
        self._pointer(self.sans_matiere, 2)

        call_command(
            "retirer_les_pointages_sans_matiere", "--appliquer", "--etablissement=ECA"
        )

        self.assertEqual(
            TeacherAttendance.objects.filter(teacher=chez_la_voisine).count(), 3
        )
        self.assertEqual(
            TeacherAttendance.objects.filter(teacher=self.sans_matiere).count(), 0
        )

    def test_relancer_sur_une_base_saine_ne_fait_rien(self):
        self._pointer(self.titulaire, 2)

        call_command("retirer_les_pointages_sans_matiere", "--appliquer")

        self.assertEqual(TeacherAttendance.objects.count(), 2)
