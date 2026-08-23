"""Verrou de la matrice de droits.

Trois niveaux de garantie, du plus structurel au plus concret:
  1. la matrice est complete et alignee sur UserRole;
  2. aucune vue routee n'echappe a la matrice (c'est la regression qui
     rouvrirait le trou d'origine: une ressource oubliee, donc ouverte);
  3. la matrice est bien celle qu'applique le HTTP, role par role.
"""

from datetime import date

from django.urls import get_resolver
from rest_framework import status
from rest_framework.test import APIRequestFactory, APITestCase

from apps.accounts import access
from apps.accounts.models import User, UserRole
from apps.accounts.permissions import HasModuleAccess
from apps.school.models import AcademicYear, ClassRoom, Etablissement, Student


class MatrixIntegrityTests(APITestCase):
    def test_roles_match_user_role_choices(self):
        self.assertEqual(sorted(access.ROLES), sorted(UserRole.values))
        self.assertEqual(sorted(access.ROLE_LABELS), sorted(UserRole.values))

    def test_every_module_covers_every_role(self):
        for module, spec in access.MODULES.items():
            with self.subTest(module=module):
                self.assertEqual(sorted(spec["access"]), sorted(access.ROLES))
                self.assertIn(spec["group"], dict(access.MODULE_GROUPS))

    def test_super_admin_is_never_below_another_role(self):
        """Garde-fou de coherence: personne ne depasse le super admin."""
        for module in access.MODULE_KEYS:
            top = access.access_level(access.SUPER_ADMIN, module)
            for role in access.ROLES:
                with self.subTest(module=module, role=role):
                    self.assertLessEqual(access.access_level(role, module), top)

    def test_parent_and_student_never_write_outside_chat(self):
        for module in access.MODULE_KEYS:
            if module == "chat":
                continue
            for role in (access.PARENT, access.STUDENT):
                with self.subTest(module=module, role=role):
                    self.assertFalse(access.can_write(role, module))


class RoutedViewsCoverageTests(APITestCase):
    """Aucune vue de l'API ne doit vivre hors de la matrice.

    C'est ce test qui empeche le retour du defaut permissif: une nouvelle
    ressource sans access_module echoue ici, pas en production.
    """

    EXEMPT = {
        "APIRootView",  # index DRF
        "CustomTokenObtainPairView",  # connexion
        "TokenRefreshView",
        "CustomTokenRefreshView",
        "LogoutView",  # ferme sa propre session, ne touche aucune ressource
        "HealthCheckView",  # sonde d'infrastructure, n'expose aucune donnee
        "ModulePermissionsView",  # sert la matrice elle-meme
        # Cible du QR imprime sur la carte scolaire: celui qui controle au
        # portail n'a pas de compte. Publique par necessite, mais elle
        # n'expose aucune identite et exige la signature de la carte.
        # Voir apps/reports/tests/test_student_card.py.
        "StudentCardVerifyView",
        "SpectacularAPIView",
        "SpectacularSwaggerView",
        "RedirectView",  # admin Django
    }

    def _routed_views(self):
        found = {}

        def walk(patterns):
            for pattern in patterns:
                if hasattr(pattern, "url_patterns"):
                    walk(pattern.url_patterns)
                    continue
                view = getattr(pattern.callback, "cls", None) or getattr(
                    pattern.callback, "view_class", None
                )
                if view is not None:
                    found.setdefault(view.__name__, view)

        walk(get_resolver().url_patterns)
        return found

    def test_every_api_view_declares_a_known_module(self):
        for name, view in self._routed_views().items():
            if name in self.EXEMPT or not name.endswith(("ViewSet", "View")):
                continue
            declared = getattr(view, "permission_classes", [])
            guarded = any(
                isinstance(cls, type) and issubclass(cls, HasModuleAccess)
                for cls in declared
            ) or "get_permissions" in view.__dict__
            with self.subTest(view=name):
                self.assertTrue(guarded, f"{name} n'applique pas HasModuleAccess")
                module = getattr(view, "access_module", None)
                self.assertIn(module, access.MODULES, f"{name} n'a pas de module valide")


class PermissionEnforcementTests(APITestCase):
    """La matrice telle que la permission DRF l'applique, sur les 9 roles."""

    METHOD_FOR_LEVEL = {
        access.READ: "GET",
        access.WRITE: "POST",
        access.ADMIN: "DELETE",
    }

    def setUp(self):
        self.factory = APIRequestFactory()
        self.users = {
            role: User.objects.create_user(
                username=f"matrix_{role}",
                password="Pass1234!",
                role=role,
            )
            for role in access.ROLES
        }

    def _check(self, role, module, method):
        class _View:
            access_module = module

        request = self.factory.generic(method, "/")
        request.user = self.users[role]
        return HasModuleAccess().has_permission(request, _View())

    def test_matrix_is_what_the_permission_applies(self):
        for module in access.MODULE_KEYS:
            for role in access.ROLES:
                granted = access.access_level(role, module)
                for level, method in self.METHOD_FOR_LEVEL.items():
                    with self.subTest(module=module, role=role, method=method):
                        self.assertEqual(
                            self._check(role, module, method),
                            granted >= level,
                        )

    def test_view_without_module_is_denied(self):
        class _Orphan:
            pass

        request = self.factory.get("/")
        request.user = self.users[access.SUPER_ADMIN]
        self.assertFalse(HasModuleAccess().has_permission(request, _Orphan()))

    def test_anonymous_is_denied(self):
        class _View:
            access_module = "dashboard"

        request = self.factory.get("/")
        request.user = None
        self.assertFalse(HasModuleAccess().has_permission(request, _View()))


class PermissionsEndpointTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username="matrix_endpoint_censor",
            password="Pass1234!",
            role=UserRole.CENSOR,
        )

    def test_endpoint_serves_the_role_matrix(self):
        self.client.force_authenticate(self.user)
        response = self.client.get("/api/auth/permissions/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["role"], UserRole.CENSOR)
        modules = response.data["modules"]
        self.assertEqual(sorted(modules), sorted(access.MODULE_KEYS))

        # Le censeur: ecrit les notes, ne touche pas aux finances.
        self.assertTrue(modules["grades"]["write"])
        self.assertEqual(modules["finance"]["level"], "none")
        self.assertFalse(modules["finance"]["read"])

    def test_endpoint_requires_authentication(self):
        response = self.client.get("/api/auth/permissions/")
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)


class ClosedHolesTests(APITestCase):
    """Les ouvertures reelles que la matrice ferme, verifiees en HTTP.

    Chacun de ces appels renvoyait 200/201 avant la matrice, par le simple
    fait que la ressource n'etait rattachee a aucune classe de permission.
    """

    def setUp(self):
        self.etablissement = Etablissement.objects.create(
            name="Etab Matrice",
            address="Conakry",
            phone="620000000",
            email="matrice@example.com",
        )
        self.year = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
        )
        self.classroom = ClassRoom.objects.create(
            name="6e A",
            academic_year=self.year,
            etablissement=self.etablissement,
        )
        student_user = User.objects.create_user(
            username="matrix_student_profile",
            password="Pass1234!",
            first_name="Awa",
            last_name="Diallo",
            role=UserRole.STUDENT,
            etablissement=self.etablissement,
        )
        self.student = Student.objects.create(
            user=student_user,
            matricule="MAT-0001",
            birth_date=date(2012, 5, 4),
            classroom=self.classroom,
            etablissement=self.etablissement,
        )

    def _as(self, role):
        user = User.objects.create_user(
            username=f"hole_{role}",
            password="Pass1234!",
            role=role,
            etablissement=self.etablissement,
        )
        self.client.force_authenticate(user)
        return user

    def _grade_payload(self):
        return {
            "student": self.student.id,
            "classroom": self.classroom.id,
            "academic_year": self.year.id,
            "term": "T1",
            "value": 12,
        }

    def test_supervisor_cannot_write_grades(self):
        self._as(UserRole.SUPERVISOR)
        response = self.client.post("/api/grades/", self._grade_payload(), format="json")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_accountant_cannot_write_grades(self):
        self._as(UserRole.ACCOUNTANT)
        response = self.client.post("/api/grades/", self._grade_payload(), format="json")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_teacher_cannot_delete_a_classroom(self):
        self._as(UserRole.TEACHER)
        response = self.client.delete(f"/api/classrooms/{self.classroom.id}/")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_teacher_cannot_read_sms_provider_credentials(self):
        """La config SMS porte le jeton d'API en clair."""
        self._as(UserRole.TEACHER)
        response = self.client.get("/api/sms-providers/")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_supervisor_cannot_write_canteen_prices(self):
        self._as(UserRole.SUPERVISOR)
        response = self.client.get("/api/suppliers/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        response = self.client.post(
            "/api/suppliers/", {"name": "Fournisseur X"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_read_only_refusal_explains_itself(self):
        self._as(UserRole.SUPERVISOR)
        response = self.client.post("/api/grades/", self._grade_payload(), format="json")
        self.assertIn("Notes", str(response.data.get("detail", "")))
