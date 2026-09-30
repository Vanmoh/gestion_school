"""Rattacher une ligne datee a son annee scolaire, quand personne ne l'a fait.

Quatre modeles portent un `academic_year` **facultatif**: les absences, les
incidents de discipline, les depenses et les fiches de paie. Le champ a ete
rendu facultatif pour ne pas casser les lignes anterieures a son introduction.

C'est cette tolerance qui se retourne contre nous. Une ligne sans annee
disparait de l'ecran des qu'une annee est choisie -- le filtre demande
`academic_year=<annee>`, et `NULL` n'y repond pas. Et comme l'en-tete d'annee
part sur *toutes* les requetes de l'application, ces lignes ne s'affichent
jamais: personne ne peut les corriger, puisque personne ne les voit. Sur la
base reelle, 44 lignes etaient dans ce cas -- 9 absences, 1 incident,
10 depenses et 24 fiches de paie.

La date, elle, est toujours renseignee: ces quatre modeles sont dates par
nature. Et deux annees d'un meme etablissement ne peuvent pas se chevaucher
(`AcademicYearSerializer.validate` le refuse, et `AcademicYear.clean` aussi).
Une date designe donc **au plus une** annee: le rattachement est deductible,
et c'est tout ce que fait ce module.

Ce qu'il ne fait pas: deviner. Quand l'etablissement est inconnu, ou qu'aucune
annee ne couvre la date, la ligne reste sans annee. Mieux vaut une ligne
orpheline qu'une ligne rangee dans la mauvaise annee -- la premiere se
retrouve par une requete, la seconde faussera un bilan sans jamais se
signaler.
"""

from __future__ import annotations


def annee_de_la_date(etablissement, date):
    """L'annee scolaire de cet etablissement qui contient cette date.

    `None` si l'etablissement est inconnu, si la date manque, ou si aucune
    annee ne la couvre -- une absence saisie pendant les grandes vacances,
    par exemple, n'appartient a aucune annee et ce n'est pas une anomalie.
    """
    if etablissement is None or date is None:
        return None

    from apps.school.models import AcademicYear

    return (
        AcademicYear.objects.filter(
            etablissement=etablissement,
            start_date__lte=date,
            end_date__gte=date,
        )
        .order_by("-is_active", "-start_date", "-id")
        .first()
    )


def deja_rattache(instance):
    """Sortie rapide pour les `pre_save`, avant toute requete.

    Python evalue les arguments avant d'appeler: passer
    `etablissement=etablissement_de_l_eleve(instance.student)` declenche une
    requete sur l'eleve meme quand l'annee est deja posee -- c'est-a-dire dans
    le cas courant, puisque les vues la posent a la creation. Une feuille
    d'appel de trente lignes payait trente requetes pour rien.
    """
    return getattr(instance, "academic_year_id", None) is not None


def rattacher_a_l_annee(instance, date, etablissement):
    """Pose `academic_year` si elle manque. Ne corrige jamais une annee posee.

    Le silence est volontaire: un `pre_save` qui leve une exception refuserait
    un enregistrement pour un rattachement, alors que la ligne elle-meme est
    valide. On comble ce qu'on peut, on laisse le reste visible a
    `controler_la_dotation`.
    """
    if getattr(instance, "academic_year_id", None) is not None:
        return None

    annee = annee_de_la_date(etablissement, date)
    if annee is not None:
        instance.academic_year = annee
    return annee


def etablissement_de_l_eleve(eleve):
    """L'etablissement d'un eleve, par son rattachement puis par sa classe.

    Les deux chemins existent parce que `Student.etablissement` est nullable:
    un eleve importe sans etablissement mais affecte a une classe reste
    localisable par elle.
    """
    if eleve is None:
        return None
    direct = getattr(eleve, "etablissement", None)
    if direct is not None:
        return direct
    classe = getattr(eleve, "classroom", None)
    annee = getattr(classe, "academic_year", None)
    return getattr(annee, "etablissement", None)


def etablissement_de_l_enseignant(enseignant):
    """L'etablissement d'un enseignant, par son rattachement puis par ses classes."""
    if enseignant is None:
        return None
    direct = getattr(enseignant, "etablissement", None)
    if direct is not None:
        return direct
    if getattr(enseignant, "pk", None) is None:
        return None
    affectation = (
        enseignant.assignments.select_related("classroom__academic_year")
        .order_by("id")
        .first()
    )
    annee = getattr(getattr(affectation, "classroom", None), "academic_year", None)
    return getattr(annee, "etablissement", None)
