from rest_framework.permissions import SAFE_METHODS, BasePermission


class IsRole(BasePermission):
    allowed_roles = []

    def has_permission(self, request, view):
        return request.user and request.user.is_authenticated and request.user.role in self.allowed_roles


class IsAdminOrDirector(IsRole):
    allowed_roles = ["super_admin", "director"]


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
        "Acces reserve au super admin et au surveillant. "
        "Le comptable est autorise en lecture seule."
    )

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False

        if request.method in SAFE_METHODS:
            return user.role in {"super_admin", "supervisor", "accountant"}

        return user.role in {"super_admin", "supervisor"}


class IsStudentModuleScopedAccess(BasePermission):
    message = (
        "Acces eleves reserve. Ecriture: super admin/directeur. "
        "Lecture: super admin, directeur, surveillant, enseignant, comptable."
    )

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False

        if request.method in SAFE_METHODS:
            return user.role in {"super_admin", "director", "supervisor", "teacher", "accountant"}

        return user.role in {"super_admin", "director"}


class IsAttendanceModuleScopedAccess(BasePermission):
    message = (
        "Acces absences reserve. Ecriture: super admin/directeur/surveillant. "
        "Lecture: super admin, directeur, surveillant, comptable, parent, eleve."
    )

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False

        if request.method in SAFE_METHODS:
            return user.role in {"super_admin", "director", "supervisor", "accountant", "parent", "student"}

        return user.role in {"super_admin", "director", "supervisor"}


class IsTeacherAttendanceModuleScopedAccess(BasePermission):
    message = (
        "Acces absences enseignants reserve. Ecriture: super admin/directeur/surveillant/enseignant. "
        "Lecture: super admin, directeur, surveillant, enseignant."
    )

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False

        if request.method in SAFE_METHODS:
            return user.role in {"super_admin", "director", "supervisor", "teacher"}

        return user.role in {"super_admin", "director", "supervisor", "teacher"}


class IsDisciplineModuleScopedAccess(BasePermission):
    message = (
        "Acces discipline reserve. Ecriture: super admin/directeur/surveillant/enseignant. "
        "Lecture: super admin, directeur, surveillant, enseignant, comptable."
    )

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False

        if request.method in SAFE_METHODS:
            return user.role in {"super_admin", "director", "supervisor", "teacher", "accountant"}

        return user.role in {"super_admin", "director", "supervisor", "teacher"}


class IsExamsModuleScopedAccess(BasePermission):
    message = (
        "Acces examens reserve. Ecriture: super admin/directeur/enseignant. "
        "Lecture: super admin, directeur, surveillant, comptable, enseignant."
    )

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False

        if request.method in SAFE_METHODS:
            return user.role in {"super_admin", "director", "supervisor", "accountant", "teacher"}

        return user.role in {"super_admin", "director", "teacher"}


class IsTimetableModuleScopedAccess(BasePermission):
    message = (
        "Acces emploi du temps reserve. Ecriture: super admin/directeur. "
        "Lecture: super admin, directeur, surveillant, enseignant, comptable, parent, eleve."
    )

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False

        if request.method in SAFE_METHODS:
            return user.role in {"super_admin", "director", "supervisor", "teacher", "accountant", "parent", "student"}

        return user.role in {"super_admin", "director"}


class IsTeacherAvailabilityModuleScopedAccess(BasePermission):
    message = (
        "Acces disponibilites reserve. Ecriture: super admin/directeur/enseignant. "
        "Lecture: super admin, directeur, surveillant, enseignant."
    )

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False

        if request.method in SAFE_METHODS:
            return user.role in {"super_admin", "director", "supervisor", "teacher"}

        return user.role in {"super_admin", "director", "teacher"}


class IsCommunicationModuleScopedAccess(BasePermission):
    message = (
        "Acces communication reserve. Ecriture: super admin/directeur/surveillant. "
        "Lecture: super admin, directeur, surveillant, enseignant, comptable."
    )

    def has_permission(self, request, view):
        user = request.user
        if not user or not user.is_authenticated:
            return False

        if request.method in SAFE_METHODS:
            return user.role in {"super_admin", "director", "supervisor", "teacher", "accountant"}

        return user.role in {"super_admin", "director", "supervisor"}
