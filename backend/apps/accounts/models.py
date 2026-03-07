from django.contrib.auth.models import AbstractUser
from django.db import models


class UserRole(models.TextChoices):
    SUPER_ADMIN = "super_admin", "Super Admin"
    DIRECTOR = "director", "Directeur"
    ACCOUNTANT = "accountant", "Comptable"
    TEACHER = "teacher", "Enseignant"
    SUPERVISOR = "supervisor", "Surveillant"
    PARENT = "parent", "Parent"
    STUDENT = "student", "Élève"


class User(AbstractUser):
    role = models.CharField(max_length=20, choices=UserRole.choices)
    phone = models.CharField(max_length=20, blank=True)
    profile_photo = models.ImageField(upload_to="profiles/", blank=True, null=True)

    class Meta:
        db_table = "users"

    def __str__(self) -> str:
        return f"{self.get_full_name()} ({self.role})"
