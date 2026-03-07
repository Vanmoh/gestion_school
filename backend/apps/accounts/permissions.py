from rest_framework.permissions import BasePermission


class IsRole(BasePermission):
    allowed_roles = []

    def has_permission(self, request, view):
        return request.user and request.user.is_authenticated and request.user.role in self.allowed_roles


class IsAdminOrDirector(IsRole):
    allowed_roles = ["super_admin", "director"]
