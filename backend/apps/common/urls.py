from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import ActivityLogViewSet

router = DefaultRouter()
router.register(r"activity-logs", ActivityLogViewSet, basename="activity-logs")

urlpatterns = [
    path("", include(router.urls)),
]
