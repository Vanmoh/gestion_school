from django.urls import include, path
from rest_framework.routers import DefaultRouter
from .views import CustomTokenObtainPairView, RegisterView, UserViewSet, token_refresh_view

router = DefaultRouter()
router.register(r"users", UserViewSet, basename="users")

urlpatterns = [
    path("login/", CustomTokenObtainPairView.as_view(), name="token_obtain_pair"),
    path("refresh/", token_refresh_view, name="token_refresh"),
    path("register/", RegisterView.as_view(), name="register"),
    path("", include(router.urls)),
]
