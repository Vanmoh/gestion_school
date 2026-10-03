"""Ce qu'on peut consigner d'un enseignant, et ce qui n'a pas de sens.

Un pointage dit si l'enseignant a assure ses cours ce jour-la. La question ne se
pose pas pour quelqu'un qui n'enseigne rien: il n'y a rien a assurer, rien a
manquer, rien a justifier. La base de developpement en portait pourtant neuf cent
vingt, pour cinquante-deux enseignants sans une matiere -- et personne ne pouvait
le voir, parce qu'un registre d'absences ne dit pas qui enseigne quoi.

Le defaut n'etait pas dans le pointage: il naissait bien avant. Une matiere
pouvait avoir deux titulaires (corrige par la migration 0071), et les
peuplements successifs recrutaient des enseignants sans leur donner de cours. Ce
module ferme la porte qui restait: on ne pointe que quelqu'un qui enseigne.

**Ce qu'on n'exige pas, et pourquoi.** Une declaration de disponibilite ne
demande aucune affectation -- c'est l'inverse: la direction collecte les
disponibilites *pour* arbitrer les affectations, et un enseignant qui vient
d'arriver doit pouvoir declarer les siennes. Une fiche de paie non plus: celle
d'un mois passe reste due a qui n'enseigne plus aujourd'hui. Exiger une
affectation dans ces deux cas casserait un usage legitime, et la regle perdrait
sa credibilite.
"""

from django.core.exceptions import ValidationError


def enseigne_quelque_chose(enseignant) -> bool:
    """Vrai si une matiere lui est confiee, quelque part."""
    if enseignant is None or enseignant.pk is None:
        return False
    return enseignant.assignments.exists()


def refuser_si_il_n_enseigne_rien(enseignant, quoi="Ce pointage"):
    """Leve `ValidationError` quand l'enseignant ne tient aucune matiere.

    Le message nomme l'enseignant et dit quoi faire: un refus qui se contente
    d'interdire fait perdre du temps a qui le lit.
    """
    if enseigne_quelque_chose(enseignant):
        return

    compte = getattr(enseignant, "user", None)
    nom = ""
    if compte is not None:
        nom = compte.get_full_name().strip() or compte.username
    nom = nom or "cet enseignant"

    raise ValidationError(
        {
            "teacher": (
                f"{quoi} est impossible: aucune matière n'est affectée à {nom}. "
                "Affectez-lui d'abord une matière dans « Enseignants > "
                "Affectations »."
            )
        }
    )


def classes_de_l_enseignant(user):
    """Les identifiants des classes ou ce compte a une affectation.

    `StudentViewSet.get_queryset` traitait l'eleve et le parent, puis
    l'enseignant **tombait dans la branche generale** et recevait toute
    l'ecole, comme un directeur. Mesure sur la base reelle: une enseignante
    affectee a deux classes -- soixante eleves -- en recevait cent cinquante,
    et pouvait ouvrir le dossier nominatif d'un enfant qu'elle n'a pas en
    charge.

    La matrice classe pourtant `students` en `L*`: lecture **restreinte**.
    L'etoile y est documentaire, c'est au code de l'appliquer.

    Rend des identifiants et non des objets: les appelants filtrent sur
    `classroom_id__in`, et une sous-requete evite de ramener les lignes pour
    les jeter.
    """
    from apps.school.models import TeacherAssignment

    return TeacherAssignment.objects.filter(teacher__user_id=user.id).values(
        "classroom_id"
    )


def est_enseignant(user):
    """Vrai pour un compte enseignant, faux pour tout le reste.

    Le test vit ici et non en ligne dans chaque vue: quatre vues doivent poser
    la meme question, et quatre comparaisons de chaine finissent par diverger.
    """
    from apps.accounts.models import UserRole

    return getattr(user, "role", "") == UserRole.TEACHER
