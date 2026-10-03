"""Ce que chaque role a le droit de lire sur le tableau de bord.

`/dashboard/` rendait **la meme charge utile a tout le monde**. Un parent et un
eleve recevaient donc le recouvrement de l'ecole (93,0 %), ses 5 040 000 FCFA
d'impayes et sa **masse salariale de 29 913 950 FCFA**. Un censeur et un
surveillant aussi, alors que la matrice leur interdit le module `finance`. Un
comptable recevait la moyenne generale et les absences, qui ne le concernent
pas.

La matrice classait pourtant parent, eleve et enseignant en `L*` -- lecture
**restreinte**. L'etoile y est documentaire: c'est au code de l'appliquer, et
la vue ne regardait pas le role.

La regle tient en une ligne, et elle ne s'invente pas: un chiffre global n'est
rendu que si le role lit son module **et** que cet acces n'est pas restreint.
Un `L*` signifie « ton propre dossier » -- jamais un agregat de l'ecole, quel
que soit le module.

C'est la meme regle que pour `ExpenseViewSet`, qui rend `none()` a une famille.
Ce qui changeait ici, c'est qu'un agregat n'a pas de lignes a filtrer: il faut
retirer la cle.
"""

from __future__ import annotations

from apps.accounts.access import can_read, is_scoped

# Le module dont chaque chiffre releve.
#
# Les cles absentes de cette table sont rendues a tout le monde: l'annee
# consultee et l'etablissement actif ne sont pas des chiffres, ce sont les
# coordonnees de la lecture -- un ecran qui les cacherait ne saurait plus de
# quoi il parle.
MODULE_DU_CHIFFRE = {
    # --- les effectifs ----------------------------------------------------
    "students": "students",
    "students_unassigned": "students",
    "classrooms": "academics",
    "teachers": "teachers",
    # --- l'argent ---------------------------------------------------------
    "monthly_revenue": "finance",
    "monthly_expenses": "finance",
    "monthly_expenses_pending": "finance",
    "monthly_profit": "finance",
    "expenses_pending_count": "finance",
    "year_expenses_pending": "finance",
    "year_expenses_pending_count": "finance",
    "fees_due": "finance",
    "fees_collected": "finance",
    "fees_outstanding": "finance",
    "collection_rate": "finance",
    "students_unpaid": "finance",
    # La paie a son propre module: un censeur la lit, un surveillant non.
    "payroll_total": "payroll",
    "payroll_count": "payroll",
    # --- l'ecole ----------------------------------------------------------
    "general_average": "grades",
    "grades_count": "grades",
    "bulletins_delivered": "reports",
    "bulletins_total": "reports",
    "bulletins_failed": "reports",
    "monthly_absences": "attendance",
    "monthly_absence_hours": "attendance",
    # L'assiduite des enseignants releve de l'emargement, pas de l'assiduite
    # des eleves: un surveillant suit les seconds et pas les premiers.
    "teacher_absences": "teacher_timesheet",
    "teacher_late": "teacher_timesheet",
    "stock_below_threshold": "stock",
    "stock_total": "stock",
}


def peut_lire_globalement(role: str, module: str) -> bool:
    """Le role lit-il ce module **pour toute l'ecole**?

    Deux conditions, et la seconde est celle qui manquait: un acces restreint
    (`L*`) donne droit a ses propres lignes, jamais a une somme qui couvre
    l'etablissement. Une moyenne generale n'a pas de version « restreinte ».
    """
    return can_read(role, module) and not is_scoped(role, module)


def restreindre_au_role(charge_utile: dict, role: str) -> dict:
    """Retire de la charge utile les chiffres que ce role ne doit pas lire.

    Retirer la cle plutot que la mettre a zero: un zero se lit comme une
    information -- « l'ecole n'a rien encaisse » -- alors que l'absence de cle
    dit « cela ne vous regarde pas », et l'ecran sait alors ne pas peindre la
    carte.
    """
    return {
        cle: valeur
        for cle, valeur in charge_utile.items()
        if cle not in MODULE_DU_CHIFFRE
        or peut_lire_globalement(role, MODULE_DU_CHIFFRE[cle])
    }
