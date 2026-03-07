from django.db import models
from django.conf import settings


class TimeStampedModel(models.Model):
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True


class ActivityLog(TimeStampedModel):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True)
    role = models.CharField(max_length=20, blank=True)
    action = models.CharField(max_length=120)
    method = models.CharField(max_length=10)
    path = models.CharField(max_length=255)
    module = models.CharField(max_length=80, blank=True)
    target = models.CharField(max_length=120, blank=True)
    status_code = models.PositiveIntegerField(default=0)
    success = models.BooleanField(default=True)
    ip_address = models.CharField(max_length=45, blank=True)
    user_agent = models.CharField(max_length=255, blank=True)
    details = models.TextField(blank=True)

    class Meta:
        ordering = ["-created_at", "-id"]

    def __str__(self):
        return f"{self.created_at} | {self.action} | {self.path}"
