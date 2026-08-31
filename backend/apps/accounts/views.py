from django.contrib.auth import get_user_model
from rest_framework import generics, permissions, status, viewsets
from django.db.models import Q
from rest_framework.decorators import action
from rest_framework.exceptions import ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView
from apps.school.models import Etablissement, ParentProfile
from .access import can_read, role_payload
from .access_routes import module_paths
from .permissions import HasModuleAccess
from .serializers import RegisterSerializer, UserSerializer
from .models import UserRole
from apps.common.pagination import StandardResultsSetPagination

User = get_user_model()


class CustomTokenObtainPairView(TokenObtainPairView):
    # Seule route ou un anonyme peut tester un secret: elle porte le quota
    # etroit "login" plutot que le quota anonyme general.
    throttle_scope = "login"


class CustomTokenRefreshView(TokenRefreshView):
    # Un refresh token vole se rejoue ici: meme quota que la connexion.
    throttle_scope = "login"


class ModulePermissionsView(APIView):
    """Droits du profil connecte, tels que le backend les applique.

    Le frontend consomme cette reponse au lieu de redupliquer la carte des
    roles: les deux couches ne peuvent plus diverger sans que ce soit visible.
    """

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        payload = role_payload(getattr(request.user, "role", ""))
        # Les chemins accompagnent la matrice: le client peut ainsi refuser
        # une ecriture sur un module en lecture seule sans connaitre le
        # routage, et sans qu'on recopie ce routage dans le frontend.
        payload["paths"] = module_paths()
        return Response(payload)


class RegisterView(generics.CreateAPIView):
    access_module = "users"
    serializer_class = RegisterSerializer
    permission_classes = [permissions.IsAuthenticated, HasModuleAccess]

    def _requested_etablissement_id(self):
        raw_value = (
            self.request.headers.get("X-Etablissement-Id")
            or self.request.query_params.get("etablissement")
        )
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    def _requested_etablissement_name(self):
        raw_name = (
            self.request.headers.get("X-Etablissement-Name")
            or self.request.query_params.get("etablissement_name")
        )
        if raw_name is None:
            return None
        cleaned = str(raw_name).strip()
        return cleaned or None

    def _requested_etablissement(self):
        requested_id = self._requested_etablissement_id()
        if requested_id:
            etablissement = Etablissement.objects.filter(id=requested_id).first()
            if etablissement:
                return etablissement

        requested_name = self._requested_etablissement_name()
        if not requested_name:
            return None

        etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
        if etablissement:
            return etablissement

        return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context["target_etablissement"] = self._requested_etablissement()
        return context


class UserViewSet(viewsets.ModelViewSet):
    access_module = "users"
    queryset = User.objects.all().order_by("-id")
    serializer_class = UserSerializer
    pagination_class = StandardResultsSetPagination
    # `is_active` fait partie des filtres et non de la seule lecture: c'est
    # lui qui sort la liste des comptes restes ouverts apres un depart.
    filterset_fields = ["role", "etablissement", "is_active"]
    # La recherche est construite a la main (voir `_chercher`): le
    # `search_fields` de DRF interrogeait l'email entier, domaine compris.
    # Tous les comptes d'une ecole partageant « @ifp-obk.com », taper « o »
    # ou « k » ramenait l'annuaire complet et la recherche paraissait cassee.
    search_fields = []

    def _requested_etablissement_id(self):
        raw_value = (
            self.request.headers.get("X-Etablissement-Id")
            or self.request.query_params.get("etablissement")
        )
        if raw_value in (None, ""):
            return None
        try:
            parsed = int(raw_value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed > 0 else None

    def _requested_etablissement_name(self):
        raw_name = (
            self.request.headers.get("X-Etablissement-Name")
            or self.request.query_params.get("etablissement_name")
        )
        if raw_name is None:
            return None
        cleaned = str(raw_name).strip()
        return cleaned or None

    def _requested_etablissement(self):
        requested_id = self._requested_etablissement_id()
        if requested_id:
            etablissement = Etablissement.objects.filter(id=requested_id).first()
            if etablissement:
                return etablissement

        requested_name = self._requested_etablissement_name()
        if not requested_name:
            return None

        etablissement = Etablissement.objects.filter(name__iexact=requested_name).first()
        if etablissement:
            return etablissement

        return Etablissement.objects.filter(name__icontains=requested_name).order_by("name").first()

    def _has_requested_scope(self):
        return self._requested_etablissement_id() is not None or self._requested_etablissement_name() is not None

    def _resolve_target_etablissement(self):
        user = self.request.user
        requested = self._requested_etablissement()
        if getattr(user, "role", None) == "super_admin":
            return requested
        return getattr(user, "etablissement", None)

    def _chercher(self, queryset):
        """Cherche un compte par ce qui l'identifie, pas par son domaine.

        L'email entier entrait dans la recherche. Tous les comptes d'une
        ecole partageant le meme domaine, taper une lettre qu'il contient --
        le « o » de « @ifp-obk.com » -- ramenait l'annuaire complet.

        L'email n'est donc interroge que par son debut: « ali » trouve
        « ali.cisse@... », « com » ne trouve plus personne. Le telephone
        reste cherche en entier: un numero se retient souvent par sa fin.
        """
        terme = (self.request.query_params.get("search") or "").strip()
        if not terme:
            return queryset

        return queryset.filter(
            Q(username__icontains=terme)
            | Q(first_name__icontains=terme)
            | Q(last_name__icontains=terme)
            | Q(phone__icontains=terme)
            | Q(email__istartswith=terme)
        )

    def get_queryset(self):
        user = self.request.user
        # `chat_presence` est jointe ici: la fiche affiche « en ligne », et
        # sans cela chaque ligne de la liste declencherait sa propre requete.
        qs = (
            User.objects.select_related("etablissement", "chat_presence")
            .all()
            .order_by("-id")
        )
        requested = self._requested_etablissement()

        if getattr(user, "role", None) == "super_admin":
            if requested is not None:
                return self._chercher(qs.filter(etablissement=requested))
            if self._has_requested_scope():
                return qs.none()
            return self._chercher(qs)

        return self._chercher(
            qs.filter(etablissement=getattr(user, "etablissement", None))
        )

    def perform_create(self, serializer):
        user = serializer.save(etablissement=self._resolve_target_etablissement())
        self._sync_parent_profile(user)

    def perform_update(self, serializer):
        self._verifier_la_desactivation(serializer)
        target_etablissement = self._resolve_target_etablissement()
        if getattr(self.request.user, "role", None) == "super_admin":
            user = serializer.save()
            self._sync_parent_profile(user)
            return
        user = serializer.save(etablissement=target_etablissement)
        self._sync_parent_profile(user)

    def _verifier_la_desactivation(self, serializer):
        """Deux comptes ne doivent jamais pouvoir etre coupes.

        Le sien -- on se retrouverait dehors sans pouvoir revenir -- et le
        dernier super-administrateur actif, sans lequel plus personne ne
        pourrait reactiver quoi que ce soit.
        """
        if serializer.validated_data.get("is_active") is not False:
            return

        cible = serializer.instance
        if cible is None:
            return

        if cible.pk == self.request.user.pk:
            raise ValidationError(
                {"is_active": "Vous ne pouvez pas désactiver votre propre compte."}
            )

        if cible.role == UserRole.SUPER_ADMIN:
            restants = (
                User.objects.filter(role=UserRole.SUPER_ADMIN, is_active=True)
                .exclude(pk=cible.pk)
                .count()
            )
            if restants == 0:
                raise ValidationError(
                    {
                        "is_active": "C'est le dernier super-administrateur actif : "
                                     "le désactiver fermerait la porte à tout le monde."
                    }
                )

    def _donnees_liees(self, user):
        """Ce qu'une suppression de compte emporterait avec elle.

        `Student.user` et `Teacher.user` sont en CASCADE: supprimer le compte
        d'un enseignant efface sa fiche, ses affectations, ses creneaux
        d'emploi du temps et ses pointages. Rien ne le disait avant de le
        faire.
        """
        from apps.school.models import Student, Teacher

        inventaire = {}

        eleve = Student.objects.filter(user=user).first()
        if eleve is not None:
            inventaire["fiche élève"] = 1
            inventaire["notes"] = eleve.grades.count() if hasattr(eleve, "grades") else 0
            inventaire["paiements"] = sum(
                frais.payments.count() for frais in eleve.fees.all()
            )

        enseignant = Teacher.objects.filter(user=user).first()
        if enseignant is not None:
            inventaire["fiche enseignant"] = 1
            inventaire["affectations"] = enseignant.assignments.count()
            inventaire["pointages"] = enseignant.time_entries.count()
            inventaire["créneaux d'emploi du temps"] = sum(
                affectation.schedule_slots.count()
                for affectation in enseignant.assignments.all()
            )

        return {nom: compte for nom, compte in inventaire.items() if compte}

    def destroy(self, request, *args, **kwargs):
        """La suppression dit d'abord ce qu'elle emporte.

        Elle reste possible -- c'est une decision d'administration --, mais
        plus a l'aveugle: le premier appel rend l'inventaire, et il faut le
        confirmer explicitement pour qu'elle ait lieu. Desactiver reste
        preferable dans presque tous les cas, et le message le rappelle.
        """
        cible = self.get_object()

        if cible.pk == request.user.pk:
            raise ValidationError(
                {"detail": "Vous ne pouvez pas supprimer votre propre compte."}
            )

        lie = self._donnees_liees(cible)
        confirme = str(
            request.query_params.get("confirm")
            or (request.data.get("confirm") if isinstance(request.data, dict) else "")
        ).lower() in ("1", "true", "oui")

        if lie and not confirme:
            detail = ", ".join(f"{compte} {nom}" for nom, compte in lie.items())
            raise ValidationError(
                {
                    "detail": f"Ce compte porte des données liées : {detail}. "
                              "Elles seront définitivement supprimées avec lui. "
                              "Désactivez-le plutôt, ou confirmez avec « confirm ».",
                    "linked_data": lie,
                }
            )

        return super().destroy(request, *args, **kwargs)

    @action(detail=True, methods=["post"], url_path="reset-password")
    def reset_password(self, request, pk=None):
        """L'administration fixe un mot de passe provisoire, qu'elle communique.

        L'ecran offrait un champ « Mot de passe » a la modification, et le
        serializer ne le connaissait pas: l'API repondait 200 sans rien
        changer. Personne ne pouvait donc depanner un compte dont le mot de
        passe etait perdu.
        """
        cible = self.get_object()
        nouveau = str(request.data.get("password") or "")

        if len(nouveau) < 8:
            raise ValidationError(
                {"password": "Le mot de passe provisoire doit faire 8 caractères au moins."}
            )

        cible.set_password(nouveau)
        cible.save(update_fields=["password"])

        return Response(
            {
                "detail": f"Mot de passe réinitialisé pour {cible.username}. "
                          "Communiquez-le à la personne concernée : elle devrait "
                          "le changer à sa prochaine connexion.",
                "user": cible.id,
            }
        )

    def _sync_parent_profile(self, user):
        if not user:
            return
        if getattr(user, "role", None) != UserRole.PARENT:
            return

        parent_profile, _ = ParentProfile.objects.get_or_create(
            user=user,
            defaults={"etablissement": user.etablissement},
        )
        if parent_profile.etablissement_id != user.etablissement_id:
            parent_profile.etablissement = user.etablissement
            parent_profile.save(update_fields=["etablissement", "updated_at"])

    def get_permissions(self):
        # "me" et "directory" ne sont pas de l'administration d'utilisateurs:
        # l'un renvoie son propre profil, l'autre l'annuaire minimal dont les
        # autres modules ont besoin (choisir un destinataire, un enseignant,
        # un surveillant). Les soumettre au module "users" fermerait ces
        # ecrans a tous les profils sauf la direction.
        if self.action in ["me", "directory"]:
            return [permissions.IsAuthenticated()]
        return [permissions.IsAuthenticated(), HasModuleAccess()]

    @action(
        detail=False,
        methods=["get"],
        permission_classes=[permissions.IsAuthenticated],
        url_path="directory",
    )
    def directory(self, request):
        """Annuaire en lecture: identite et role pour tous, contacts pour ceux
        qui gerent le personnel.

        L'annuaire est servi a tout compte authentifie -- c'est voulu, sans
        quoi les ecrans qui choisissent un destinataire se fermeraient a tous
        sauf a la direction. Y verser en clair le telephone et la photo des
        enseignants les exposerait donc aussi aux familles.

        Les coordonnees ne sont ajoutees qu'aux lecteurs ayant acces au module
        « teachers ». Le tri se fait ici, cote serveur: laisser le client
        demander la version riche reviendrait a lui confier la regle.
        """
        queryset = self.filter_queryset(self.get_queryset())
        avec_contacts = can_read(getattr(request.user, "role", ""), "teachers")

        rows = []
        for item in queryset:
            ligne = {
                "id": item.id,
                "username": item.username,
                "first_name": item.first_name,
                "last_name": item.last_name,
                "full_name": item.get_full_name() or item.username,
                "role": item.role,
                "etablissement": item.etablissement_id,
            }
            if avec_contacts:
                ligne["email"] = item.email
                ligne["phone"] = item.phone
                ligne["profile_photo"] = self._photo_url(request, item)
            rows.append(ligne)

        return Response(rows)

    @staticmethod
    def _photo_url(request, item):
        """URL absolue de la photo, ou None.

        Le stockage objet signe deja ses liens; en local l'API sert un chemin
        relatif que le navigateur ne saurait pas resoudre seul.
        """
        photo = getattr(item, "profile_photo", None)
        if not photo:
            return None
        try:
            return request.build_absolute_uri(photo.url)
        except Exception:
            # Un fichier reference mais absent ne doit pas vider l'annuaire.
            return None

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


class LogoutView(APIView):
    """Revoque le refresh token presente, sans jamais faire echouer la sortie.

    Le client efface son stockage local des qu'il appelle cette route: renvoyer
    une erreur sur un token deja expire ou deja revoque le laisserait croire
    qu'il est encore connecte. On repond donc 205 dans tous les cas ou la
    demande est bien formee.
    """

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        raw_token = (request.data.get("refresh") or "").strip()
        if not raw_token:
            return Response(
                {"refresh": "Ce champ est obligatoire."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            RefreshToken(raw_token).blacklist()
        except TokenError:
            # Token expire, malforme ou deja revoque: la session est close
            # dans tous les cas, il n'y a rien de plus a revoquer.
            pass

        return Response(status=status.HTTP_205_RESET_CONTENT)


token_refresh_view = CustomTokenRefreshView.as_view()
