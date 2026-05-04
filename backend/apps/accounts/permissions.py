from rest_framework.permissions import SAFE_METHODS, BasePermission


class IsRole(BasePermission):
    allowed_roles = []

    def has_permission(self, request, view):
        return request.user and request.user.is_authenticated and request.user.role in self.allowed_roles


class IsAdminOrDirector(IsRole):
    allowed_roles = ["super_admin", "director", "promoter"]


class IsSuperAdmin(IsRole):
    allowed_roles = ["super_admin"]


class IsReadOnlyForParentStudent(BasePermission):
    message = "Les profils parent/élève sont en lecture seule sur cette ressource."

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False

        if request.method in SAFE_METHODS:
            return True

        return user.role not in {"parent", "student"}


class IsSuperAdminSupervisorOrAccountantReadOnly(BasePermission):
    message = (
        "Acces reserve au super admin et au censeur. "
        "Le comptable est autorise en lecture seule."
    )

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False

        if request.method in SAFE_METHODS:
            return user.role in {"super_admin", "censor", "accountant"}

        return user.role in {"super_admin", "censor"}


class IsStudentModuleScopedAccess(BasePermission):
    message = (
        "Acces eleves reserve. Ecriture: super admin/directeur/promoteur. "
        "Lecture: super admin, directeur, promoteur, censeur, enseignant, comptable."
    )

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False

        if request.method in SAFE_METHODS:
            return user.role in {
                "super_admin",
                "director",
                "promoter",
                "censor",
                "teacher",
                "accountant",
            }

        return user.role in {"super_admin", "director", "promoter"}


class IsAttendanceModuleScopedAccess(BasePermission):
    message = (
        "Acces absences reserve. Ecriture: super admin/directeur/promoteur/censeur/surveillant. "
        "Lecture: super admin, directeur, promoteur, censeur, surveillant, comptable, parent, eleve."
    )

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False

        if request.method in SAFE_METHODS:
            return user.role in {
                "super_admin",
                "director",
                "promoter",
                "censor",
                "supervisor",
                "accountant",
                "parent",
                "student",
            }

        return user.role in {
            "super_admin",
            "director",
            "promoter",
            "censor",
            "supervisor",
        }


class IsTeacherAttendanceModuleScopedAccess(BasePermission):
    message = (
        "Acces absences enseignants reserve. Ecriture: super admin/directeur/promoteur/censeur/enseignant. "
        "Lecture: super admin, directeur, promoteur, censeur, enseignant."
    )

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False

        if request.method in SAFE_METHODS:
            return user.role in {
                "super_admin",
                "director",
                "promoter",
                "censor",
                "teacher",
            }

        return user.role in {
            "super_admin",
            "director",
            "promoter",
            "censor",
            "teacher",
        }


class IsTeacherTimesheetModuleScopedAccess(BasePermission):
    message = (
        "Acces emargement enseignants reserve. Ecriture: super admin/censeur, "
        "et enseignant sur son propre pointage. Lecture: super admin, censeur, "
        "directeur, promoteur, comptable et enseignant. Le directeur et le promoteur sont en lecture seule sur ce module."
    )

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False

        if request.method in SAFE_METHODS:
            return user.role in {
                "super_admin",
                "censor",
                "director",
                "promoter",
                "accountant",
                "teacher",
            }

        return user.role in {"super_admin", "censor", "teacher"}


class IsDisciplineModuleScopedAccess(BasePermission):
    message = (
        "Acces discipline reserve. Ecriture: super admin/directeur/promoteur/censeur/surveillant/enseignant. "
        "Lecture: super admin, directeur, promoteur, censeur, surveillant, enseignant, comptable."
    )

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False

        if request.method in SAFE_METHODS:
            return user.role in {
                "super_admin",
                "director",
                "promoter",
                "censor",
                "supervisor",
                "teacher",
                "accountant",
            }

        return user.role in {
            "super_admin",
            "director",
            "promoter",
            "censor",
            "supervisor",
            "teacher",
        }


class IsExamsModuleScopedAccess(BasePermission):
    message = (
        "Acces examens reserve. Ecriture: super admin/directeur/promoteur/enseignant. "
        "Lecture: super admin, directeur, promoteur, censeur, comptable, enseignant."
    )

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False

        if request.method in SAFE_METHODS:
            return user.role in {
                "super_admin",
                "director",
                "promoter",
                "censor",
                "accountant",
                "teacher",
            }

        return user.role in {"super_admin", "director", "promoter", "teacher"}


class IsTimetableModuleScopedAccess(BasePermission):
    message = (
        "Acces emploi du temps reserve. Ecriture: super admin/directeur/promoteur/censeur. "
        "Lecture: super admin, directeur, promoteur, censeur, enseignant, comptable, parent, eleve."
    )

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False

        if request.method in SAFE_METHODS:
            return user.role in {
                "super_admin",
                "director",
                "promoter",
                "censor",
                "teacher",
                "accountant",
                "parent",
                "student",
            }

        return user.role in {
            "super_admin",
            "director",
            "promoter",
            "censor",
        }


class IsTeacherAvailabilityModuleScopedAccess(BasePermission):
    message = (
        "Acces disponibilites reserve. Ecriture: super admin/directeur/promoteur/enseignant. "
        "Lecture: super admin, directeur, promoteur, censeur, enseignant."
    )

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False

        if request.method in SAFE_METHODS:
            return user.role in {
                "super_admin",
                "director",
                "promoter",
                "censor",
                "teacher",
            }

        return user.role in {"super_admin", "director", "promoter", "teacher"}


class IsCommunicationModuleScopedAccess(BasePermission):
    message = (
        "Acces communication reserve. Ecriture: super admin/directeur/promoteur/censeur. "
        "Lecture: super admin, directeur, promoteur, censeur, enseignant, comptable."
    )

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False

        if request.method in SAFE_METHODS:
            return user.role in {
                "super_admin",
                "director",
                "promoter",
                "censor",
                "teacher",
                "accountant",
            }

        return user.role in {
            "super_admin",
            "director",
            "promoter",
            "censor",
        }


class IsTeacherModuleScopedAccess(BasePermission):
    message = (
        "Acces enseignants reserve. Ecriture: super admin/directeur/promoteur. "
        "Lecture: super admin, directeur, promoteur, censeur."
    )

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False

        if request.method in SAFE_METHODS:
            return user.role in {"super_admin", "director", "promoter", "censor"}

        return user.role in {"super_admin", "director", "promoter"}


class IsFinanceModuleScopedAccess(BasePermission):
    message = (
        "Acces finance reserve. Ecriture: super admin/directeur/promoteur/comptable. "
        "Lecture: super admin, directeur, promoteur, comptable, parent, eleve."
    )

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False

        if request.method in SAFE_METHODS:
            return user.role in {
                "super_admin",
                "director",
                "promoter",
                "accountant",
                "parent",
                "student",
            }

        return user.role in {"super_admin", "director", "promoter", "accountant"}
