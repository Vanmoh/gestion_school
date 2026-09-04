from rest_framework import serializers

from .models import ActivityLog, BackupArchive, PersonnalisationPlateforme


class ActivityLogSerializer(serializers.ModelSerializer):
    user_display = serializers.SerializerMethodField(read_only=True)

    def get_user_display(self, obj):
        if not obj.user:
            return "Anonyme"
        full_name = obj.user.get_full_name().strip()
        return full_name or obj.user.username

    class Meta:
        model = ActivityLog
        fields = "__all__"


class BackupArchiveSerializer(serializers.ModelSerializer):
    created_by_display = serializers.SerializerMethodField(read_only=True)
    restored_by_display = serializers.SerializerMethodField(read_only=True)
    etablissement_name = serializers.SerializerMethodField(read_only=True)

    def get_created_by_display(self, obj):
        user = obj.created_by
        if not user:
            return ""
        full_name = user.get_full_name().strip()
        return full_name or user.username

    def get_restored_by_display(self, obj):
        user = obj.restored_by
        if not user:
            return ""
        full_name = user.get_full_name().strip()
        return full_name or user.username

    def get_etablissement_name(self, obj):
        etablissement = obj.etablissement
        return etablissement.name if etablissement else ""

    class Meta:
        model = BackupArchive
        fields = "__all__"


class PersonnalisationSerializer(serializers.ModelSerializer):
    """L'identite de l'ecole, telle que les ecrans la consomment.

    `logo_url` plutot que le champ brut: le client a besoin d'une adresse
    absolue -- il tourne sur un autre hote que l'API -- et le chemin relatif
    que rend `ImageField` y donnerait une image cassee.
    """

    logo_url = serializers.SerializerMethodField(read_only=True)

    class Meta:
        model = PersonnalisationPlateforme
        fields = [
            "nom_application",
            "nom_ecole",
            "sigle",
            "logo",
            "logo_url",
            "telephone",
            "email",
            "adresse",
            "titre_connexion",
            "sous_titre_connexion",
            "titre_portail",
            "sous_titre_portail",
            "message_accueil",
            "pied_de_page",
            "couleur_principale",
        ]
        extra_kwargs = {
            "logo": {"write_only": True, "required": False},
            # Vider un libelle est une action legitime: c'est ainsi qu'on
            # rend a un ecran sa formulation d'origine. Sans cela, DRF les
            # refuse avant meme d'arriver a la validation.
            "nom_ecole": {"allow_blank": True},
            "sigle": {"allow_blank": True},
            "telephone": {"allow_blank": True},
            "email": {"allow_blank": True},
            "adresse": {"allow_blank": True},
            "titre_connexion": {"allow_blank": True},
            "sous_titre_connexion": {"allow_blank": True},
            "titre_portail": {"allow_blank": True},
            "sous_titre_portail": {"allow_blank": True},
            "message_accueil": {"allow_blank": True},
            "pied_de_page": {"allow_blank": True},
            "couleur_principale": {"allow_blank": True},
        }

    def get_logo_url(self, obj):
        if not obj.logo:
            return ""
        url = obj.logo.url
        requete = self.context.get("request")
        return requete.build_absolute_uri(url) if requete else url

    def validate_couleur_principale(self, valeur):
        """Refuse ce qui n'est pas une couleur.

        Une valeur libre arriverait telle quelle au client, qui la lit comme
        un entier hexadecimal: elle y donnerait une couleur au hasard, ou une
        exception au demarrage de l'application.
        """
        texte = (valeur or "").strip()
        if not texte:
            return "#6D5BFF"
        if not texte.startswith("#"):
            texte = f"#{texte}"
        corps = texte[1:]
        if len(corps) != 6 or any(c not in "0123456789abcdefABCDEF" for c in corps):
            raise serializers.ValidationError(
                "Attendu une couleur au format #RRGGBB, par exemple #6D5BFF."
            )
        return f"#{corps.upper()}"
