from django.contrib.auth import get_user_model
from rest_framework import generics, permissions, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView
from apps.school.models import Etablissement, ParentProfile
from .permissions import IsAdminOrDirector
from .serializers import RegisterSerializer, UserSerializer
from .models import UserRole
from apps.common.pagination import StandardResultsSetPagination

User = get_user_model()


class CustomTokenObtainPairView(TokenObtainPairView):
    pass


class RegisterView(generics.CreateAPIView):
    serializer_class = RegisterSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminOrDirector]

    def _requested_etablissement_id(self):
        raw_value = (
            self.request.headers.get("X-Etablissement-Id")
            or self.request.query_params.get("etablissement")
        )
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    def _requested_etablissement_name(self):
        raw_name = (
            self.request.headers.get("X-Etablissement-Name")
            or self.request.query_params.get("etablissement_name")
        )
        if raw_name is None:
            return None
        cleaned = str(raw_name).strip()
        return cleaned or None

    def _requested_etablissement(self):
        requested_id = self._requested_etablissement_id()
        if requested_id:
            etablissement = Etablissement.objects.filter(id=requested_id).first()
            if etablissement:
                return etablissement

        requested_name = self._requested_etablissement_name()
        if not requested_name:
            return None

        etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
        if etablissement:
            return etablissement

        return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context["target_etablissement"] = self._requested_etablissement()
        return context


class UserViewSet(viewsets.ModelViewSet):
    queryset = User.objects.all().order_by("-id")
    serializer_class = UserSerializer
    pagination_class = StandardResultsSetPagination
    filterset_fields = ["role", "etablissement"]
    search_fields = ["username", "first_name", "last_name", "email"]

    def _requested_etablissement_id(self):
        raw_value = (
            self.request.headers.get("X-Etablissement-Id")
            or self.request.query_params.get("etablissement")
        )
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    def _requested_etablissement_name(self):
        raw_name = (
            self.request.headers.get("X-Etablissement-Name")
            or self.request.query_params.get("etablissement_name")
        )
        if raw_name is None:
            return None
        cleaned = str(raw_name).strip()
        return cleaned or None

    def _requested_etablissement(self):
        requested_id = self._requested_etablissement_id()
        if requested_id:
            etablissement = Etablissement.objects.filter(id=requested_id).first()
            if etablissement:
                return etablissement

        requested_name = self._requested_etablissement_name()
        if not requested_name:
            return None

        etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
        if etablissement:
            return etablissement

        return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()

    def _has_requested_scope(self):
        return self._requested_etablissement_id() is not None or self._requested_etablissement_name() is not None

    def _resolve_target_etablissement(self):
        user = self.request.user
        requested = self._requested_etablissement()
        if getattr(user, "role", None) == "super_admin":
            return requested
        return getattr(user, "etablissement", None)

    def get_queryset(self):
        user = self.request.user
        qs = User.objects.select_related("etablissement").all().order_by("-id")
        requested = self._requested_etablissement()

        if getattr(user, "role", None) == "super_admin":
            if requested is not None:
                return qs.filter(etablissement=requested)
            if self._has_requested_scope():
                return qs.none()
            return qs

        return qs.filter(etablissement=getattr(user, "etablissement", None))

    def perform_create(self, serializer):
        user = serializer.save(etablissement=self._resolve_target_etablissement())
        self._sync_parent_profile(user)

    def perform_update(self, serializer):
        target_etablissement = self._resolve_target_etablissement()
        if getattr(self.request.user, "role", None) == "super_admin":
            user = serializer.save()
            self._sync_parent_profile(user)
            return
        user = serializer.save(etablissement=target_etablissement)
        self._sync_parent_profile(user)

    def _sync_parent_profile(self, user):
        if not user:
            return
        if getattr(user, "role", None) != UserRole.PARENT:
            return

        parent_profile, _ = ParentProfile.objects.get_or_create(
            user=user,
            defaults={"etablissement": user.etablissement},
        )
        if parent_profile.etablissement_id != user.etablissement_id:
            parent_profile.etablissement = user.etablissement
            parent_profile.save(update_fields=["etablissement", "updated_at"])

    def get_permissions(self):
        if self.action in ["me"]:
            return [permissions.IsAuthenticated()]
        return [permissions.IsAuthenticated(), IsAdminOrDirector()]

    @action(detail=False, methods=["get"], permission_classes=[permissions.IsAuthenticated])
    def me(self, request):
        serializer = self.get_serializer(request.user)
        return Response(serializer.data)

    @action(
        detail=False,
        methods=["get"],
        permission_classes=[permissions.IsAuthenticated],
        url_path="etablissements",
    )
    def etablissements(self, request):
        user = request.user
        if getattr(user, "role", None) == "super_admin":
            qs = Etablissement.objects.all().order_by("name")
        elif getattr(user, "etablissement_id", None):
            qs = Etablissement.objects.filter(id=user.etablissement_id)
        else:
            qs = Etablissement.objects.none()

        data = []
        for etab in qs:
            logo_url = None
            if etab.logo:
                try:
                    logo_url = request.build_absolute_uri(etab.logo.url)
                except Exception:
                    logo_url = None
            data.append(
                {
                    "id": etab.id,
                    "name": etab.name,
                    "address": etab.address,
                    "phone": etab.phone,
                    "email": etab.email,
                    "logo": logo_url,
                }
            )

        return Response(data)


token_refresh_view = TokenRefreshView.as_view()
