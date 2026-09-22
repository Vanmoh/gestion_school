from django.contrib.auth.models import AbstractUser
from django.db import models


class UserRole(models.TextChoices):
    SUPER_ADMIN = "super_admin", "Super Admin"
    DIRECTOR = "director", "Directeur/Proviseur"
    PROMOTER = "promoter", "Promoteur"
    CENSOR = "censor", "Censeur"
    ACCOUNTANT = "accountant", "Comptable"
    TEACHER = "teacher", "Enseignant"
    SUPERVISOR = "supervisor", "Surveillant"
    PARENT = "parent", "Parent"
    STUDENT = "student", "Élève"



from apps.school.models import Etablissement

class User(AbstractUser):
    role = models.CharField(max_length=20, choices=UserRole.choices)
    phone = models.CharField(max_length=20, blank=True)
    profile_photo = models.ImageField(upload_to="profiles/", blank=True, null=True)
    etablissement = models.ForeignKey(Etablissement, on_delete=models.PROTECT, related_name="users", null=True, blank=True)

    # Le mot de passe remis a la famille est ecrit sur un papier, et il suit
    # une regle que l'ecole applique a tous. Il n'est donc un secret qu'une
    # fois: tant que son titulaire ne l'a pas remplace, l'application ne lui
    # ouvre que l'ecran du changement.
    doit_changer_mot_de_passe = models.BooleanField(default=False)

    class Meta:
        db_table = "users"

    def __str__(self) -> str:
        return f"{self.get_full_name()} ({self.role})"
