"""Ce qu'une famille a le droit de lire d'un resultat d'examen.

`ExamSession` porte une docstring qui dit pourquoi la publication existe: une
note vue pendant la correction est une note qui a circule dans la cour avant
que le jury ne l'arrete. Le verrou a bien ete pose -- et il ne tenait qu'a une
seule porte, `ExamResultViewSet.get_queryset`. Quatre autres l'ignoraient: le
dossier eleve, le bulletin PDF d'un eleve, celui d'une classe entiere, et le
lien signe envoye par WhatsApp, qui regenere le document a chaque ouverture.
Une famille lisait donc ses notes de composition avant leur publication, par
le chemin le plus ordinaire qui soit: telecharger son bulletin.

La regle vit ici, une fois. Les vues l'appellent, aucune ne la reecrit.

Deux choses que ce module ne fait pas, et qu'il ne faut pas lui faire faire:

1. **Il ne filtre pas le calcul de l'ecole.** `moyenne_de_la_periode`,
   `recalculate_term_ranking` et les decisions de passage lisent toutes les
   notes des leur saisie. Un rang qui dependrait de qui le demande ne serait
   pas un rang, et un eleve ne doit pas redoubler parce que sa composition
   n'etait pas encore ouverte aux familles. L'embargo porte sur le lecteur,
   jamais sur la donnee.

2. **Il ne sert pas a amputer un bulletin.** `moyennes.note_finale_matiere`
   retient la note de classe pour la matiere entiere quand la composition
   manque: retirer une composition d'un bulletin n'y laisse pas un trou, cela
   promeut la note de classe a tout le coefficient. Le document imprimerait
   une moyenne differente de celle du registre, et un rang qui ne s'accorde
   plus avec `StudentAcademicHistory`. Un bulletin sous embargo se refuse; il
   ne se caviarde pas.

Le module ne connait pas les modeles -- seulement des `Q` et des querysets
qu'on lui passe. C'est ce qui lui permet d'etre appele depuis `school/views.py`
comme depuis `reports/views.py` sans refermer un cycle d'import, comme
`moyennes.py` a cote.
"""

from __future__ import annotations

from django.db.models import Q

# Les profils pour qui une note n'existe qu'une fois publiee. Le personnel
# lit tout: c'est lui qui corrige, et c'est lui qui decide d'ouvrir.
ROLES_SOUS_EMBARGO = frozenset({"parent", "student"})

# La note est ouverte quand sa session l'est.
#
# L'expression est isolee ici pour que le filtre et sa negation ne divergent
# jamais: les vues qui listent ont besoin du premier, celles qui refusent un
# document ont besoin de la seconde.
EMBARGO_LEVE = Q(session__results_published=True)


def sous_embargo(role: str) -> bool:
    """Ce profil doit-il attendre la publication?"""
    return str(role or "") in ROLES_SOUS_EMBARGO


def resultats_lisibles_par(user, queryset):
    """Les resultats que ce compte a le droit de lire, dans cet ensemble.

    L'appelant a deja restreint le queryset a ce qui le concerne -- ses
    enfants, son dossier, sa classe. Ici on ne retranche que ce que l'ecole
    n'a pas encore ouvert.
    """
    if sous_embargo(getattr(user, "role", "")):
        return queryset.filter(EMBARGO_LEVE)
    return queryset


def resultats_sous_embargo(queryset):
    """Les resultats de cet ensemble que l'ecole n'a pas encore ouverts.

    La question negative, pour les deux usages ou taire une note ne suffit
    pas: annoncer a la famille combien de notes lui restent dues, et refuser
    un bulletin qui en contiendrait.
    """
    return queryset.exclude(EMBARGO_LEVE)
