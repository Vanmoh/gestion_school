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
