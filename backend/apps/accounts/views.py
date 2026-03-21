from django.contrib.auth import get_user_model
from rest_framework import generics, permissions, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView
from apps.school.models import Etablissement
from .permissions import IsAdminOrDirector
from .serializers import RegisterSerializer, UserSerializer

User = get_user_model()


class CustomTokenObtainPairView(TokenObtainPairView):
    pass


class RegisterView(generics.CreateAPIView):
    serializer_class = RegisterSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminOrDirector]


class UserViewSet(viewsets.ModelViewSet):
    queryset = User.objects.all().order_by("-id")
    serializer_class = UserSerializer
    filterset_fields = ["role"]
    search_fields = ["username", "first_name", "last_name", "email"]

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
