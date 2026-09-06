from django.db import models
from django.conf import settings


class TimeStampedModel(models.Model):
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True


class ActivityLog(TimeStampedModel):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True)
    etablissement = models.ForeignKey("school.Etablissement", on_delete=models.SET_NULL, null=True, blank=True)
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
        indexes = [
            models.Index(fields=["-created_at"], name="actlog_created_desc_idx"),
            models.Index(fields=["user", "-created_at"], name="actlog_user_created_idx"),
            models.Index(fields=["etablissement", "-created_at"], name="actlog_etab_created_idx"),
            models.Index(fields=["module", "-created_at"], name="actlog_module_created_idx"),
            models.Index(fields=["success", "-created_at"], name="actlog_success_created_idx"),
        ]

    def __str__(self):
        return f"{self.created_at} | {self.action} | {self.path}"


class BackupArchive(TimeStampedModel):
    class Scope(models.TextChoices):
        GLOBAL = "global", "Globale plateforme"
        ETABLISSEMENT = "etablissement", "Etablissement"

    class Status(models.TextChoices):
        PENDING = "pending", "En attente"
        RUNNING = "running", "En cours"
        COMPLETED = "completed", "Terminee"
        FAILED = "failed", "Echec"

    class Kind(models.TextChoices):
        PORTABLE = "portable", "Portable ZIP"

    scope = models.CharField(max_length=20, choices=Scope.choices, default=Scope.GLOBAL)
    kind = models.CharField(max_length=20, choices=Kind.choices, default=Kind.PORTABLE)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING)

    etablissement = models.ForeignKey(
        "school.Etablissement",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="backups",
    )
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="created_backups",
    )
    restored_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="restored_backups",
    )

    filename = models.CharField(max_length=255, blank=True)
    file_path = models.CharField(max_length=500, blank=True)
    file_size_bytes = models.BigIntegerField(default=0)
    sha256 = models.CharField(max_length=64, blank=True)
    include_media = models.BooleanField(default=True)
    manifest = models.JSONField(default=dict, blank=True)
    notes = models.TextField(blank=True)
    restore_log = models.TextField(blank=True)
    restore_phase = models.CharField(max_length=120, blank=True)
    restore_progress = models.PositiveSmallIntegerField(default=0)
    restored_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at", "-id"]
        indexes = [
            models.Index(fields=["scope", "-created_at"], name="backup_scope_created_idx"),
            models.Index(fields=["status", "-created_at"], name="backup_status_created_idx"),
            models.Index(fields=["etablissement", "-created_at"], name="backup_etab_created_idx"),
        ]

    def __str__(self):
        return f"{self.get_scope_display()} | {self.filename or '-'} | {self.status}"


class PersonnalisationPlateforme(TimeStampedModel):
    """Ce qui porte le nom de l'ecole dans l'application.

    Tout cela vivait en dur dans le code du client: le nom, le logo, le
    telephone, jusqu'aux filieres affichees sur l'ecran de connexion. Servir
    une autre ecole demandait de recompiler l'application avec ses propres
    constantes -- autant dire de maintenir une version par client.

    Une seule ligne existe (`pk=1`). Ce n'est pas une preference par
    etablissement mais l'identite de l'ecole qui les possede tous: le
    portail de selection s'affiche avant qu'on ait choisi un etablissement,
    il n'aurait donc aucune identite a porter.
    """

    SINGLETON_PK = 1

    # --- Identite ---------------------------------------------------------
    nom_application = models.CharField(
        max_length=80,
        default="GESTION SCOLAIRE",
        help_text="Titre de l'onglet du navigateur et de l'application.",
    )
    nom_ecole = models.CharField(
        max_length=150,
        default="",
        help_text="Nom complet, affiche sur l'ecran de connexion.",
    )
    sigle = models.CharField(
        max_length=20,
        blank=True,
        help_text="Abrege, utilise la ou la place manque.",
    )
    logo = models.ImageField(
        upload_to="personnalisation/",
        null=True,
        blank=True,
        help_text="Affiche sur l'ecran de connexion et le portail.",
    )

    # --- Coordonnees ------------------------------------------------------
    telephone = models.CharField(max_length=80, blank=True)
    email = models.EmailField(blank=True)
    adresse = models.CharField(max_length=200, blank=True)

    # --- Textes des ecrans publics ---------------------------------------
    # Vides, les ecrans gardent leurs formulations d'origine: une ecole qui
    # ne personnalise rien ne doit pas se retrouver avec des libelles blancs.
    titre_connexion = models.CharField(max_length=120, blank=True)
    sous_titre_connexion = models.CharField(max_length=200, blank=True)
    titre_portail = models.CharField(max_length=120, blank=True)
    sous_titre_portail = models.CharField(max_length=200, blank=True)
    message_accueil = models.TextField(
        blank=True,
        help_text="Phrase libre affichee sous le titre du portail.",
    )
    pied_de_page = models.TextField(blank=True)

    # --- Apparence --------------------------------------------------------
    # La couleur principale seulement: le choix clair/sombre a ete retire,
    # l'application se presente en sombre partout.
    couleur_principale = models.CharField(
        max_length=7,
        default="#6D5BFF",
        help_text="Couleur d'accent, au format #RRGGBB.",
    )
    image_fond = models.ImageField(
        upload_to="personnalisation/fonds/",
        null=True,
        blank=True,
        help_text=(
            "Image de fond du portail et de la connexion, sous un voile "
            "sombre. Large plutot que haute, 1600 px minimum."
        ),
    )

    class Meta:
        verbose_name = "Personnalisation de la plateforme"
        verbose_name_plural = "Personnalisation de la plateforme"

    def __str__(self):
        return self.nom_ecole or self.nom_application

    def save(self, *args, **kwargs):
        # Une seule ligne, quoi qu'il arrive: sans cela deux enregistrements
        # concurrents donneraient deux identites, et l'ecran servirait celle
        # que le tri ramene en premier.
        self.pk = self.SINGLETON_PK
        kwargs.pop("force_insert", None)

        deja_la = (
            type(self).objects.filter(pk=self.SINGLETON_PK)
            .values("created_at")
            .first()
        )
        if deja_la is not None:
            # `adding` a faux fait passer Django par la mise a jour: sans
            # cela, un `objects.create()` insere en aveugle sur une cle deja
            # prise et casse sur une violation d'unicite.
            self._state.adding = False
            # Et comme `auto_now_add` ne se declenche qu'a l'insertion, la
            # date de creation d'un objet neuf serait ecrite a NULL par-dessus
            # celle de la ligne qu'on remplace.
            if self.created_at is None:
                self.created_at = deja_la["created_at"]

        super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        """Ne se supprime pas: l'application aurait alors plus d'identite."""
        return (0, {})

    @classmethod
    def actuelle(cls):
        """La personnalisation en vigueur, creee au premier appel."""
        instance, _ = cls.objects.get_or_create(pk=cls.SINGLETON_PK)
        return instance
