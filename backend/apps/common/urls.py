from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import ActivityLogViewSet, BackupArchiveViewSet

router = DefaultRouter()
router.register(r"activity-logs", ActivityLogViewSet, basename="activity-logs")
router.register(r"backup-archives", BackupArchiveViewSet, basename="backup-archives")

urlpatterns = [
    path("", include(router.urls)),
]
