"""Le calcul d'une moyenne trimestrielle, en un seul endroit.

Il vivait jusqu'ici en deux exemplaires qui ne disaient pas la meme chose:
`_build_bulletin_rows` dans apps/reports/views.py pour le bulletin imprime,
et `recalculate_term_ranking` dans apps/school/models.py pour le classement.
Le premier comptait la conduite avec un coefficient 2; le second ne la
comptait pas du tout. Un eleve pouvait donc etre classe derriere un camarade
dont le bulletin affichait une moyenne inferieure a la sienne -- ce que les
familles voient, et qui se plaide mal au secretariat.

Les deux passent desormais par ici. Le bulletin garde la mise en forme de ses
lignes, le classement ne prend que la moyenne, mais le nombre sort du meme
calcul.

Le module ne connait ni l'ORM ni Django: il recoit des notes deja chargees et
rend des nombres. C'est ce qui lui permet d'etre appele depuis `models.py`
comme depuis `reports/views.py` sans refermer un cycle d'import.
"""

from __future__ import annotations

from decimal import Decimal, ROUND_HALF_UP

# Coefficient de la conduite quand l'etablissement n'en fixe aucun. C'etait
# la valeur codee en dur dans le bulletin; elle reste le defaut pour que rien
# ne bouge sur les ecoles qui n'y touchent pas.
CONDUITE_COEFFICIENT_PAR_DEFAUT = Decimal("2")

# Note de conduite retenue quand la fiche de l'eleve n'en porte pas. Le modele
# Student la fixe deja a 18 par defaut; la reprendre ici evite qu'une fiche
# importee avec un champ vide compte comme un zero.
CONDUITE_PAR_DEFAUT = Decimal("18")

CENTIEME = Decimal("0.01")


def en_decimal(valeur, defaut: Decimal | None = None) -> Decimal | None:
    """Un Decimal, quelle que soit la forme d'ou vient le nombre.

    Les notes arrivent tantot en Decimal (ORM), tantot en float (bulletin),
    tantot en chaine (`homework_scores`, saisies importees). Melanger Decimal
    et float dans une meme addition leve un TypeError, et convertir un float
    directement en Decimal traine ses decimales binaires: `Decimal(15.7)` vaut
    15.699999999999999289457264239899814128875732421875. Le passage par `str`
    l'evite.
    """
    if valeur is None:
        return defaut
    if isinstance(valeur, Decimal):
        return valeur
    try:
        return Decimal(str(valeur))
    except Exception:
        return defaut


def arrondir(valeur: Decimal) -> Decimal:
    """Deux decimales, au plus proche.

    ROUND_HALF_UP et non l'arrondi bancaire de Python: une moyenne de 9,995
    doit donner 10,00 -- le seuil de passage -- et non 9,99.
    """
    return valeur.quantize(CENTIEME, rounding=ROUND_HALF_UP)


def note_finale_matiere(note_classe, note_examen) -> Decimal | None:
    """La note retenue pour une matiere sur la periode.

    Devoirs et composition pesent le meme poids quand les deux existent. Quand
    une seule est saisie, elle vaut pour la matiere entiere plutot que d'etre
    divisee par deux: une composition non encore corrigee ne doit pas amputer
    la moyenne de l'eleve.
    """
    classe = en_decimal(note_classe)
    examen = en_decimal(note_examen)

    if classe is not None and examen is not None:
        return arrondir((classe + examen) / Decimal("2"))
    if classe is not None:
        return arrondir(classe)
    if examen is not None:
        return arrondir(examen)
    return None


def moyenne_ponderee(
    *,
    notes_finales_par_matiere: dict[int, Decimal | None],
    coefficients_par_matiere: dict[int, Decimal],
    conduite_note=None,
    conduite_coefficient=None,
) -> tuple[Decimal, Decimal]:
    """La moyenne de la periode et la somme des coefficients qui la portent.

    Une matiere sans note ne compte pas -- ni au numerateur ni au
    denominateur. La compter a zero ferait chuter la moyenne d'un eleve pour
    une matiere que personne n'a encore saisie.

    La conduite entre dans le calcul comme une matiere ordinaire, avec le
    coefficient de l'etablissement. Elle en etait absente cote classement,
    d'ou la divergence que ce module ferme.
    """
    somme_ponderee = Decimal("0")
    somme_coefficients = Decimal("0")

    coef_conduite = en_decimal(conduite_coefficient, CONDUITE_COEFFICIENT_PAR_DEFAUT)
    if coef_conduite is None:
        coef_conduite = CONDUITE_COEFFICIENT_PAR_DEFAUT
    if coef_conduite > 0:
        note_conduite = en_decimal(conduite_note, CONDUITE_PAR_DEFAUT)
        if note_conduite is None:
            note_conduite = CONDUITE_PAR_DEFAUT
        somme_ponderee += arrondir(note_conduite * coef_conduite)
        somme_coefficients += coef_conduite

    for matiere_id, note_finale in notes_finales_par_matiere.items():
        if note_finale is None:
            continue
        coef = en_decimal(coefficients_par_matiere.get(matiere_id), Decimal("0"))
        if coef is None or coef <= 0:
            continue
        somme_ponderee += arrondir(note_finale * coef)
        somme_coefficients += coef

    if somme_coefficients <= 0:
        return Decimal("0.00"), Decimal("0")

    return arrondir(somme_ponderee / somme_coefficients), somme_coefficients


def coefficient_de_conduite(etablissement) -> Decimal:
    """Le coefficient de conduite de l'etablissement, ou celui par defaut.

    Tolere un etablissement absent: un eleve peut ne pas encore etre rattache,
    et un bulletin doit sortir quand meme.
    """
    if etablissement is None:
        return CONDUITE_COEFFICIENT_PAR_DEFAUT
    valeur = en_decimal(
        getattr(etablissement, "conduite_coefficient", None),
        CONDUITE_COEFFICIENT_PAR_DEFAUT,
    )
    if valeur is None or valeur < 0:
        return CONDUITE_COEFFICIENT_PAR_DEFAUT
    return valeur
