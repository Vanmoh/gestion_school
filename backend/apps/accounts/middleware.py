"""Tant que le mot de passe remis n'est pas remplace, rien d'autre ne s'ouvre.

Le mot de passe d'un eleve est calcule par une regle que l'ecole applique a
tous -- souvent son matricule, qui est imprime sur sa carte, sur les listes
d'appel et sur ses bulletins. Il ne protege donc rien: n'importe qui ayant vu
une carte et devine la regle ouvrirait le compte de toute la classe.

Le rendre sans danger tient a une seule chose: qu'il cesse de fonctionner des
que son titulaire en a choisi un autre. Un drapeau sur le compte ne suffit
pas, il faut que quelque chose l'applique -- sans quoi le « changement
obligatoire » n'est qu'une phrase a l'ecran.

Un middleware et non une permission DRF: beaucoup de vues declarent leurs
propres `permission_classes`, qui remplacent celles par defaut. Une
permission globale n'aurait couvert que les vues qui n'en declarent pas,
c'est-a-dire les moins nombreuses.
"""

from django.http import JsonResponse

# Ce qui reste joignable: de quoi se connecter, se deconnecter, changer son
# mot de passe, et laisser l'hebergeur verifier que le service est vivant.
CHEMINS_AUTORISES = (
    "/api/auth/login/",
    "/api/auth/refresh/",
    "/api/auth/logout/",
    "/api/auth/changer-mot-de-passe/",
    # C'est par la que l'application apprend qui est connecte -- et qu'un
    # changement lui est demande. La fermer laisserait l'ecran de connexion
    # tourner sur un refus qu'il ne saurait pas expliquer.
    "/api/auth/users/me/",
    "/api/healthz/",
)

MESSAGE = (
    "Choisissez votre mot de passe avant de continuer : celui qui vous a été "
    "remis est provisoire."
)


class ChangementDeMotDePasseMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        chemin = request.path or ""

        if not chemin.startswith("/api/") or chemin in CHEMINS_AUTORISES:
            return self.get_response(request)

        utilisateur = self._utilisateur_du_jeton(request)
        if utilisateur is not None and getattr(
            utilisateur, "doit_changer_mot_de_passe", False
        ):
            return JsonResponse(
                {"detail": MESSAGE, "changement_de_mot_de_passe_requis": True},
                status=403,
            )

        return self.get_response(request)

    @staticmethod
    def _utilisateur_du_jeton(request):
        """L'utilisateur porte par le jeton, ou None.

        `request.user` ne vaut rien ici: l'authentification JWT a lieu dans la
        vue, pas dans la chaine des middlewares. On refait donc la lecture du
        jeton -- un HMAC, sans requete supplementaire pour le decoder.
        """
        entete = request.META.get("HTTP_AUTHORIZATION") or ""
        if not entete.lower().startswith("bearer "):
            return None

        try:
            from rest_framework_simplejwt.authentication import JWTAuthentication

            resultat = JWTAuthentication().authenticate(request)
        except Exception:
            # Un jeton invalide ou expire n'est pas notre affaire: la vue
            # repondra 401 comme d'habitude.
            return None

        return resultat[0] if resultat else None
