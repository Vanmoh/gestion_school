"""La validation des bulletins d'une classe pour une periode.

Elle sert de verrou a la diffusion aux familles: tant qu'une periode n'est
pas arretee, aucun bulletin ne part. Ces tests tiennent donc autant qui peut
la poser que ce qu'elle vaut par defaut -- « non validee », faute de quoi la
mise a jour aurait ouvert d'un coup tout l'historique deja saisi.
"""

from datetime import date

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    BulletinPublication,
    ClassRoom,
    Etablissement,
    Subject,
    Teacher,
    TeacherAssignment,
)


class BulletinPublicationApiTests(APITestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(
            name="Etab Validation",
            address="Bamako",
            email="validation@example.com",
        )
        self.annee = AcademicYear.objects.create(
            etablissement=self.etablissement,
            name="2025-2026",
            start_date=date(2025, 10, 1),
            end_date=date(2026, 6, 30),
            is_active=True,
        )
        self.classe = ClassRoom.objects.create(
            name="6eme A",
            academic_year=self.annee,
            etablissement=self.etablissement,
        )
        self.autre_classe = ClassRoom.objects.create(
            name="6eme B",
            academic_year=self.annee,
            etablissement=self.etablissement,
        )

        self.directeur = User.objects.create_user(
            username="directeur_validation",
            password="pass12345",
            role=UserRole.DIRECTOR,
            first_name="Amadou",
            last_name="Sidibé",
            etablissement=self.etablissement,
        )
        self.censeur = User.objects.create_user(
            username="censeur_validation",
            password="pass12345",
            role=UserRole.CENSOR,
            etablissement=self.etablissement,
        )
        self.comptable = User.objects.create_user(
            username="comptable_validation",
            password="pass12345",
            role=UserRole.ACCOUNTANT,
            etablissement=self.etablissement,
        )

        self.enseignant_user = User.objects.create_user(
            username="enseignant_validation",
            password="pass12345",
            role=UserRole.TEACHER,
            etablissement=self.etablissement,
        )
        self.enseignant = Teacher.objects.create(
            user=self.enseignant_user,
            employee_code="ENS-VALIDATION",
            hire_date=date(2020, 9, 1),
            etablissement=self.etablissement,
        )
        self.maths = Subject.objects.create(
            name="Maths", code="M1", classroom=self.classe
        )
        TeacherAssignment.objects.create(
            teacher=self.enseignant,
            subject=self.maths,
            classroom=self.classe,
        )

    def _corps(self, classe=None, term="T1"):
        return {
            "classroom": (classe or self.classe).id,
            "academic_year": self.annee.id,
            "term": term,
        }

    # --- poser et lever la validation ------------------------------------

    def test_la_direction_arrete_les_bulletins_d_une_periode(self):
        self.client.force_authenticate(self.directeur)
        response = self.client.post(
            "/api/bulletin-publications/publish/",
            {**self._corps(), "notes": "Conseil du 12"},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data["is_published"])
        self.assertEqual(response.data["notes"], "Conseil du 12")
        self.assertEqual(response.data["published_by_name"], "Amadou Sidibé")
        self.assertIsNotNone(response.data["published_at"])

    def test_valider_deux_fois_ne_cree_pas_deux_lignes(self):
        """Un second clic ne doit pas dedoubler l'historique de la classe."""
        self.client.force_authenticate(self.directeur)
        self.client.post("/api/bulletin-publications/publish/", self._corps(), format="json")
        self.client.post("/api/bulletin-publications/publish/", self._corps(), format="json")

        self.assertEqual(
            BulletinPublication.objects.filter(classroom=self.classe, term="T1").count(),
            1,
        )

    def test_rouvrir_une_periode_efface_la_signature(self):
        """« Validé par le directeur » ne doit pas survivre a la reouverture."""
        self.client.force_authenticate(self.directeur)
        self.client.post("/api/bulletin-publications/publish/", self._corps(), format="json")

        response = self.client.post(
            "/api/bulletin-publications/unpublish/", self._corps(), format="json"
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertFalse(response.data["is_published"])
        self.assertEqual(response.data["published_by_name"], "")
        self.assertIsNone(response.data["published_at"])

    def test_rouvrir_une_periode_jamais_validee_le_dit(self):
        self.client.force_authenticate(self.directeur)
        response = self.client.post(
            "/api/bulletin-publications/unpublish/", self._corps(), format="json"
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_la_signature_ne_se_poste_pas_a_la_main(self):
        """Sinon on ferait signer l'arret d'une periode par quelqu'un d'autre."""
        self.client.force_authenticate(self.censeur)
        response = self.client.post(
            "/api/bulletin-publications/publish/",
            {
                **self._corps(),
                "published_by": self.directeur.id,
                "published_at": "2020-01-01T08:00:00Z",
            },
            format="json",
        )

        publication = BulletinPublication.objects.get(classroom=self.classe, term="T1")
        self.assertEqual(publication.published_by, self.censeur)
        self.assertEqual(response.data["published_at"][:4], str(date.today().year))

    # --- etat --------------------------------------------------------------

    def test_une_periode_jamais_validee_repond_sans_erreur(self):
        """« Pas encore validee » n'est pas une erreur, c'est le defaut."""
        self.client.force_authenticate(self.directeur)
        response = self.client.get(
            "/api/bulletin-publications/status/",
            self._corps(),
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertFalse(response.data["is_published"])
        self.assertFalse(BulletinPublication.objects.exists())

    def test_une_periode_inconnue_est_refusee(self):
        self.client.force_authenticate(self.directeur)
        response = self.client.post(
            "/api/bulletin-publications/publish/",
            self._corps(term="T9"),
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_les_trois_parametres_sont_exiges(self):
        self.client.force_authenticate(self.directeur)
        response = self.client.post(
            "/api/bulletin-publications/publish/",
            {"classroom": self.classe.id},
            format="json",
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    # --- droits ------------------------------------------------------------

    def test_l_enseignant_lit_l_etat_mais_ne_valide_pas(self):
        """Saisir des notes n'emporte pas le droit de clore le trimestre."""
        self.client.force_authenticate(self.enseignant_user)

        self.assertEqual(
            self.client.get("/api/bulletin-publications/").status_code,
            status.HTTP_200_OK,
        )
        self.assertEqual(
            self.client.post(
                "/api/bulletin-publications/publish/", self._corps(), format="json"
            ).status_code,
            status.HTTP_403_FORBIDDEN,
        )

    def test_l_enseignant_ne_voit_que_ses_classes(self):
        """L'etoile de la matrice s'applique, sinon elle ne documente rien."""
        BulletinPublication.objects.create(
            classroom=self.classe, academic_year=self.annee, term="T1", is_published=True
        )
        BulletinPublication.objects.create(
            classroom=self.autre_classe, academic_year=self.annee, term="T1", is_published=True
        )

        self.client.force_authenticate(self.enseignant_user)
        response = self.client.get("/api/bulletin-publications/")

        lignes = response.data["results"] if isinstance(response.data, dict) else response.data
        self.assertEqual({ligne["classroom"] for ligne in lignes}, {self.classe.id})

    def test_le_comptable_n_y_a_pas_sa_place(self):
        self.client.force_authenticate(self.comptable)
        self.assertEqual(
            self.client.get("/api/bulletin-publications/").status_code,
            status.HTTP_403_FORBIDDEN,
        )

    def test_une_autre_ecole_ne_valide_pas_cette_classe(self):
        autre = Etablissement.objects.create(name="Ecole voisine", email="voisine@example.com")
        directeur_voisin = User.objects.create_user(
            username="directeur_voisin",
            password="pass12345",
            role=UserRole.DIRECTOR,
            etablissement=autre,
        )

        self.client.force_authenticate(directeur_voisin)
        response = self.client.post(
            "/api/bulletin-publications/publish/", self._corps(), format="json"
        )

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertFalse(BulletinPublication.objects.exists())
