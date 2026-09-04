from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import ActivityLogViewSet, BackupArchiveViewSet, PersonnalisationView

router = DefaultRouter()
router.register(r"activity-logs", ActivityLogViewSet, basename="activity-logs")
router.register(r"backup-archives", BackupArchiveViewSet, basename="backup-archives")

urlpatterns = [
    # Avant le routeur: une route nommee ne doit pas se faire absorber par
    # le prefixe vide du routeur.
    path("personnalisation/", PersonnalisationView.as_view(), name="personnalisation"),
    path("", include(router.urls)),
]
