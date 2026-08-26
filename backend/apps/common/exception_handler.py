"""Traduction des erreurs base de donnees en reponses metier.

Les cles etrangeres du projet sont en `PROTECT`: supprimer une classe qui
porte des notes, une matiere enseignee ou une annee scolaire utilisee doit
echouer, et c'est voulu. Mais l'echec remontait tel quel -- Django levait
`ProtectedError`, DRF ne le connaissait pas, et l'utilisateur recevait un
500 avec une trace. Le directeur qui supprimait une classe de l'an dernier
lisait « Internal Server Error » sans savoir ce qui bloquait ni quoi faire.
"""

from __future__ import annotations

from django.db.models.deletion import ProtectedError, RestrictedError
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import exception_handler as drf_exception_handler


# Nom technique du modele -> ce que l'utilisateur reconnait. Les modeles ne
# portent pas de `verbose_name` francais, et en ajouter trente pour ce seul
# message aurait touche autant de migrations. Ce qui manque ici retombe sur
# le nom du modele, lisible faute d'etre elegant.
LIBELLES_MODELES = {
    "Attendance": "des absences",
    "Borrow": "des emprunts",
    "CanteenService": "des services de cantine",
    "CanteenSubscription": "des abonnements a la cantine",
    "ClassRoom": "des classes",
    "DisciplineIncident": "des incidents disciplinaires",
    "ExamPlanning": "des plannings d'examen",
    "ExamResult": "des resultats d'examen",
    "ExamSession": "des sessions d'examen",
    "Grade": "des notes",
    "GradeValidation": "des validations de notes",
    "Payment": "des paiements",
    "PromotionDecision": "des decisions de passage",
    "Student": "des eleves",
    "StudentAcademicHistory": "des historiques de scolarite",
    "StudentFee": "des frais scolaires",
    "Subject": "des matieres",
    "Teacher": "des enseignants",
    "TeacherAssignment": "des affectations d'enseignant",
    "TeacherScheduleSlot": "des creneaux d'emploi du temps",
}


def _libelles_bloquants(objets) -> list[str]:
    """Ce qui empeche la suppression, dedoublonne et en clair."""
    noms = []
    for objet in objets:
        modele = type(objet).__name__
        libelle = LIBELLES_MODELES.get(modele, modele)
        if libelle not in noms:
            noms.append(libelle)
    return noms


def custom_exception_handler(exc, context):
    """Ajoute a DRF les erreurs de suppression protegee."""
    reponse = drf_exception_handler(exc, context)
    if reponse is not None:
        return reponse

    if isinstance(exc, (ProtectedError, RestrictedError)):
        objets = getattr(exc, "protected_objects", None) or getattr(
            exc, "restricted_objects", ()
        )
        noms = _libelles_bloquants(objets)
        if noms:
            detail = (
                "Suppression impossible: cet element est encore utilise par "
                + ", ".join(noms)
                + ". Supprimez ou reaffectez ces elements d'abord."
            )
        else:
            detail = (
                "Suppression impossible: cet element est encore utilise "
                "ailleurs dans l'application."
            )
        # 409 et non 400: la requete est correcte, c'est l'etat des donnees
        # qui s'y oppose, et il peut changer.
        return Response({"detail": detail}, status=status.HTTP_409_CONFLICT)

    return None
