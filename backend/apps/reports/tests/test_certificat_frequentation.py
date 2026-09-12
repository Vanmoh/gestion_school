"""Le certificat de frequentation, delivre a la demande d'une famille.

Dossier de bourse, demande de visa, abonnement de transport, ouverture de
compte: la piece se redigeait a la main sur papier a en-tete, et le
secretariat la ressaisissait a chaque demande.

Un certificat affirme. Ce qu'il ne sait pas, il ne doit pas l'inventer:
une date de naissance absente ne se remplace pas par une date par defaut,
et une ecole sans telephone n'emprunte pas celui d'une autre.
"""

from datetime import date

from django.test import SimpleTestCase
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.reports.views import _build_certificat_payload, _certificat_numero
from apps.school.models import AcademicYear, ClassRoom, Etablissement, Student


class _Decor:
    @classmethod
    def _monter(cls, nom="Groupe Scolaire Sankore"):
        cls.etablissement = Etablissement.objects.create(
            name=nom, address="Bamako, Hippodrome", phone="76000000"
        )
        cls.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
            etablissement=cls.etablissement,
        )
        cls.classe = ClassRoom.objects.create(
            name="10ème A", academic_year=cls.annee, etablissement=cls.etablissement
        )

    @classmethod
    def _eleve(cls, username, *, naissance=date(2010, 5, 4), prenom="Awa", nom="Traoré"):
        user = User.objects.create_user(
            username=username,
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=cls.etablissement,
            first_name=prenom,
            last_name=nom,
        )
        return Student.objects.create(
            user=user,
            classroom=cls.classe,
            etablissement=cls.etablissement,
            gender="F",
            birth_date=naissance,
        )


class NumeroDuCertificatTests(SimpleTestCase):
    def test_le_numero_ne_change_pas_d_une_demande_a_l_autre(self):
        # Un parent qui redemande la meme piece le meme jour doit obtenir le
        # meme document: deux numeros laisseraient croire a deux inscriptions.
        class _Eleve:
            id = 42

        self.assertEqual(
            _certificat_numero(_Eleve(), "2025-2026"),
            _certificat_numero(_Eleve(), "2025-2026"),
        )

    def test_le_numero_porte_l_annee_et_l_eleve(self):
        class _Eleve:
            id = 7

        numero = _certificat_numero(_Eleve(), "2025-2026")

        self.assertTrue(numero.startswith("CF-"))
        self.assertIn("20252026", numero)
        self.assertIn("00007", numero)


class ContenuDuCertificatTests(_Decor, APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls._monter()

    def test_le_corps_nomme_l_eleve_sa_classe_et_son_annee(self):
        eleve = self._eleve("eleve_certificat")

        charge = _build_certificat_payload(eleve)

        self.assertIn("Awa Traoré", charge["corps"])
        self.assertIn("10ème A", charge["corps"])
        self.assertIn("2025-2026", charge["corps"])
        self.assertIn(eleve.matricule, charge["corps"])

    def test_une_naissance_inconnue_ne_s_invente_pas(self):
        # Une piece administrative qui affirme une naissance au 1er janvier
        # 1900 se retourne contre l'ecole qui l'a signee.
        eleve = self._eleve("eleve_sans_naissance", naissance=None)

        charge = _build_certificat_payload(eleve)

        self.assertNotIn("né(e) le", charge["corps"])
        self.assertIn("Awa Traoré", charge["corps"])

    def test_une_naissance_connue_figure_au_corps(self):
        eleve = self._eleve("eleve_avec_naissance")

        charge = _build_certificat_payload(eleve)

        self.assertIn("né(e) le 04/05/2010", charge["corps"])

    def test_le_lieu_de_l_ecole_date_la_piece(self):
        # L'etablissement ne porte pas de ville: c'est son adresse qui dit ou
        # la piece a ete etablie, plutot qu'une ville devinee.
        eleve = self._eleve("eleve_lieu")

        charge = _build_certificat_payload(eleve)

        self.assertTrue(
            charge["lieu_et_date"].startswith("Fait à Bamako, Hippodrome, le ")
        )

    def test_une_ecole_sans_adresse_date_quand_meme(self):
        sans_adresse = Etablissement.objects.create(name="École de Kati")
        annee = AcademicYear.objects.create(
            name="2025-2026 Kati",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=sans_adresse,
        )
        classe = ClassRoom.objects.create(
            name="7ème B", academic_year=annee, etablissement=sans_adresse
        )
        user = User.objects.create_user(
            username="eleve_kati",
            password="Pass1234!",
            role=UserRole.STUDENT,
            etablissement=sans_adresse,
        )
        eleve = Student.objects.create(
            user=user, classroom=classe, etablissement=sans_adresse, gender="M"
        )

        charge = _build_certificat_payload(eleve)

        self.assertTrue(charge["lieu_et_date"].startswith("Fait le "))

    def test_un_eleve_sans_classe_ne_bloque_pas_la_piece(self):
        # Le certificat atteste l'inscription, pas l'affectation: un eleve
        # entre les classes doit pouvoir prouver qu'il est bien de l'ecole.
        eleve = self._eleve("eleve_sans_classe")
        eleve.classroom = None
        eleve.save(update_fields=["classroom"])

        charge = _build_certificat_payload(eleve)

        self.assertIn("non affectée", charge["corps"])


class DelivranceDuCertificatTests(_Decor, APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls._monter("Lycée Moderne de Ségou")
        cls.directeur = User.objects.create_user(
            username="dir_certificat",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.etablissement,
        )

    def setUp(self):
        super().setUp()
        self.eleve = self._eleve("eleve_delivrance")
        self.client.force_authenticate(self.directeur)

    def _demander(self, eleve=None):
        cible = eleve or self.eleve
        return self.client.get(
            f"/api/reports/certificat-frequentation/{cible.id}/",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

    def test_la_piece_sort_en_pdf(self):
        reponse = self._demander()

        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.content[:200])
        self.assertEqual(reponse["Content-Type"], "application/pdf")
        self.assertGreater(len(reponse.content), 800)

    def test_le_nom_du_fichier_porte_le_matricule(self):
        reponse = self._demander()

        self.assertIn("certificat_frequentation", reponse["Content-Disposition"])
        self.assertIn(self.eleve.matricule, reponse["Content-Disposition"])

    def test_un_eleve_inconnu_rend_404(self):
        reponse = self.client.get(
            "/api/reports/certificat-frequentation/999999/",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(reponse.status_code, status.HTTP_404_NOT_FOUND)

    def test_sans_authentification_rien_ne_sort(self):
        self.client.force_authenticate(None)

        self.assertEqual(self._demander().status_code, status.HTTP_401_UNAUTHORIZED)
