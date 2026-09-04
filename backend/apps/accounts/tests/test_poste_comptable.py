"""Le poste du comptable, verifie de bout en bout.

Un droit accorde dans la matrice ne prouve pas que l'ecran s'ouvre: le module
« rapports » etait ouvert au censeur et a l'enseignant, et une liste de roles
ecrite a la main dans la vue les refusait quand meme. Chaque moitie etait
coherente avec elle-meme, et l'entree de menu ne menait nulle part.

Ce qui suit parcourt le travail reel du comptable -- encaisser, suivre les
impayes, engager et contresigner une depense, contresigner la paie, tenir la
cantine et le stock, sortir ses journaux -- en appelant les routes que ses
ecrans appellent. Un « acces refuse » ici veut dire qu'il ne peut pas faire
son travail, quoi que dise la matrice.
"""

from datetime import date

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts import access
from apps.accounts.access_routes import module_paths
from apps.accounts.models import User, UserRole
from apps.school.models import AcademicYear, ClassRoom, Etablissement


class PosteComptableTests(APITestCase):
    @classmethod
    def setUpTestData(cls):
        cls.etablissement = Etablissement.objects.create(
            name="Etab Comptable", code="ECO"
        )
        cls.annee = AcademicYear.objects.create(
            name="2025-2026 ECO",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            etablissement=cls.etablissement,
            is_active=True,
        )
        cls.classe = ClassRoom.objects.create(
            name="6eme ECO", academic_year=cls.annee, etablissement=cls.etablissement
        )
        cls.comptable = User.objects.create_user(
            username="comptable_poste",
            password="Pass1234!",
            role=UserRole.ACCOUNTANT,
            etablissement=cls.etablissement,
        )

    def setUp(self):
        self.client.force_authenticate(self.comptable)

    def test_il_atteint_chaque_route_des_modules_qui_lui_sont_ouverts(self):
        """Aucun refus la ou la matrice le laisse entrer.

        Les exports nominatifs font exception dans l'autre sens: ils lui sont
        ouverts par un affinement, et sont donc verifies plus bas.
        """
        for module, chemins in module_paths().items():
            if not access.can_read(UserRole.ACCOUNTANT, module):
                continue

            for chemin in chemins:
                url = chemin if chemin.endswith("/") else f"{chemin}/"
                reponse = self.client.get(f"/api{url}")

                # 404 et 405 ne sont pas des refus: le prefixe s'arrete au
                # premier parametre d'URL, ou la route ne se lit pas en GET.
                # Seul 403 dit « ce profil n'a pas le droit ».
                with self.subTest(module=module, route=url):
                    self.assertNotEqual(
                        reponse.status_code,
                        status.HTTP_403_FORBIDDEN,
                        f"Le comptable lit « {module} » dans la matrice et voit "
                        f"l'entree dans son menu, mais {url} lui repond « acces "
                        f"refuse »: l'ecran est mort pour lui.",
                    )

    def test_l_ecran_de_facturation_charge_ce_dont_il_depend(self):
        """Classes et annees d'abord, frais ensuite.

        L'ecran des frais eleves les demande avant d'afficher quoi que ce
        soit: sans elles, il ne rend que son message d'erreur. C'est pour
        cette raison que le referentiel scolaire lui est ouvert en lecture,
        et non parce qu'il aurait a s'occuper de pedagogie.
        """
        for url in ("/api/classrooms/", "/api/academic-years/", "/api/fees/"):
            with self.subTest(route=url):
                self.assertEqual(
                    self.client.get(url).status_code, status.HTTP_200_OK
                )

    def test_il_encaisse_et_suit_la_caisse(self):
        for url in ("/api/payments/", "/api/expenses/", "/api/students/"):
            with self.subTest(route=url):
                self.assertEqual(
                    self.client.get(url).status_code, status.HTTP_200_OK
                )

    def test_il_contresigne_la_paie_mais_ne_la_genere_pas(self):
        """Le censeur genere et signe le niveau 1, le comptable le niveau 2.

        La separation ne tient que si aucun des deux ne fait les deux, et
        qu'aucun ne peut defaire la signature de l'autre.
        """
        self.assertTrue(
            access.affinement_autorise(UserRole.ACCOUNTANT, "validation_paie_niveau_2")
        )
        self.assertFalse(
            access.affinement_autorise(UserRole.ACCOUNTANT, "validation_paie_niveau_1")
        )
        self.assertFalse(
            access.affinement_autorise(
                UserRole.ACCOUNTANT, "annulation_validation_paie"
            )
        )
        self.assertEqual(
            self.client.get("/api/teacher-payrolls/").status_code, status.HTTP_200_OK
        )

    def test_il_voit_l_emargement_des_enseignants_qu_il_paie(self):
        """Sans les heures pointees, le montant du n'est pas verifiable."""
        self.assertEqual(
            self.client.get("/api/teacher-time-entries/").status_code,
            status.HTTP_200_OK,
        )

    def test_il_tient_la_cantine_et_le_stock(self):
        for url in (
            "/api/canteen-services/",
            "/api/canteen-subscriptions/",
            "/api/stock-items/",
            "/api/suppliers/",
        ):
            with self.subTest(route=url):
                self.assertEqual(
                    self.client.get(url).status_code, status.HTTP_200_OK
                )

    def test_il_sort_ses_journaux_et_ses_exports(self):
        """Les exports nominatifs lui sont ouverts: la caisse est son metier."""
        self.assertTrue(
            access.affinement_autorise(UserRole.ACCOUNTANT, "exports_sensibles")
        )
        for url in (
            "/api/reports/context/",
            "/api/reports/journal/payments/",
            "/api/reports/journal/expenses/",
            "/api/reports/payments/export-excel/",
        ):
            with self.subTest(route=url):
                self.assertEqual(
                    self.client.get(url).status_code, status.HTTP_200_OK
                )

    def test_ce_qui_ne_le_regarde_pas_lui_reste_ferme(self):
        """L'ouverture du poste ne doit pas devenir un passe-partout.

        Les absences des eleves, les notes et les comptes utilisateurs ne
        servent pas a facturer.
        """
        for url in ("/api/attendances/", "/api/grades/", "/api/auth/users/"):
            with self.subTest(route=url):
                self.assertEqual(
                    self.client.get(url).status_code, status.HTTP_403_FORBIDDEN
                )
