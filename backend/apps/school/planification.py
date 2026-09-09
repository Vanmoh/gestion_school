"""La generation automatique d'un emploi du temps.

Le cahier des charges la demande au module 11; elle n'existait pas. Un
etablissement saisissait ses centaines de creneaux un par un, en verifiant de
tete qu'aucun enseignant n'etait attendu dans deux classes a la fois -- la
detection de conflits n'intervenant qu'apres coup, au moment d'enregistrer.

Ce module ne connait ni l'ORM ni Django: il recoit des structures simples et
rend un placement. C'est ce qui permet de l'eprouver sur des cas tordus sans
monter une base, et de le relire sans avoir a suivre des requetes.

La strategie est gloutonne, avec un ordre choisi: les seances les plus
contraintes d'abord. Un enseignant qui n'a que trois creneaux libres dans la
semaine doit etre servi avant celui qui en a vingt, sinon ses trois creneaux
sont pris et il ne reste plus rien pour lui. C'est ce qu'on appelle placer
les pieces difficiles en premier, et cela suffit largement a un emploi du
temps scolaire -- ou les contraintes sont locales et peu nombreuses.

Ce que la generation ne fait pas: elle ne cherche pas l'optimum. Elle place
ce qu'elle peut, dit ce qu'elle n'a pas pu placer et pourquoi, et laisse
l'administration arbitrer le reste a la main. Un planning refuse en bloc
parce qu'une seule seance ne rentre pas serait inutilisable.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import time, timedelta, datetime

# Ordre de la semaine scolaire. Le samedi en fait partie: il est ouvre dans
# beaucoup d'etablissements, et l'ecarter d'office retirerait des creneaux a
# ceux qui en ont besoin.
JOURS_OUVRES = ("MON", "TUE", "WED", "THU", "FRI", "SAT")

# Ce que vaut une disponibilite au moment de choisir entre deux creneaux
# egalement libres. « Preferee » passe avant « possible »; « indisponible »
# n'est jamais choisi tant qu'un autre creneau existe.
POIDS_DISPONIBILITE = {"preferred": 0, "possible": 1, "": 2, "unavailable": 3}


@dataclass(frozen=True)
class Creneau:
    """Une case de la grille: un jour, une heure de debut, une heure de fin."""

    jour: str
    debut: time
    fin: time

    def chevauche(self, autre: "Creneau") -> bool:
        if self.jour != autre.jour:
            return False
        return self.debut < autre.fin and autre.debut < self.fin


@dataclass
class Besoin:
    """Une seance a placer: qui enseigne quoi, a qui, et combien de fois."""

    assignment_id: int
    teacher_id: int
    classroom_id: int
    subject_id: int
    subject_name: str
    seances: int
    room: str = ""


@dataclass
class Placement:
    assignment_id: int
    creneau: Creneau
    room: str = ""
    # Renseigne quand la seance est posee hors de ce que l'enseignant avait
    # declare. Le placement reste possible -- l'administration arbitre, pas
    # l'enseignant -- mais la raison voyage avec.
    hors_disponibilite: str = ""


@dataclass
class Echec:
    assignment_id: int
    subject_name: str
    motif: str


@dataclass
class Resultat:
    placements: list[Placement] = field(default_factory=list)
    echecs: list[Echec] = field(default_factory=list)

    @property
    def tout_place(self) -> bool:
        return not self.echecs


def construire_la_grille(
    *,
    jours: list[str],
    debut: time,
    fin: time,
    duree_minutes: int,
    pause_debut: time | None = None,
    pause_fin: time | None = None,
) -> list[Creneau]:
    """Les cases disponibles dans la semaine.

    La pause meridienne est retiree plutot que contournee: un creneau qui la
    chevauche, meme d'un quart d'heure, n'est pas utilisable et le proposer
    ferait perdre du temps a qui relit le planning.
    """
    if duree_minutes <= 0:
        return []

    grille: list[Creneau] = []
    for jour in jours:
        if jour not in JOURS_OUVRES:
            continue
        curseur = datetime.combine(datetime.today(), debut)
        borne = datetime.combine(datetime.today(), fin)
        while curseur + timedelta(minutes=duree_minutes) <= borne:
            creneau = Creneau(
                jour=jour,
                debut=curseur.time(),
                fin=(curseur + timedelta(minutes=duree_minutes)).time(),
            )
            curseur += timedelta(minutes=duree_minutes)

            if pause_debut and pause_fin:
                pause = Creneau(jour=jour, debut=pause_debut, fin=pause_fin)
                if creneau.chevauche(pause):
                    continue
            grille.append(creneau)
    return grille


def _disponibilite(disponibilites, teacher_id, creneau) -> str:
    """Ce que l'enseignant a declare sur ce creneau, ou '' s'il n'a rien dit.

    Rien dit n'est pas un refus: beaucoup d'enseignants ne repondent jamais a
    la campagne, et les ecarter du planning reviendrait a ne rien pouvoir
    generer.
    """
    for declaree, genre in disponibilites.get(teacher_id, ()):
        if declaree.chevauche(creneau):
            return genre
    return ""


def generer(
    *,
    besoins: list[Besoin],
    grille: list[Creneau],
    disponibilites: dict[int, list[tuple[Creneau, str]]] | None = None,
    occupes_enseignants: dict[int, list[Creneau]] | None = None,
    occupes_classes: dict[int, list[Creneau]] | None = None,
    occupees_salles: dict[str, list[Creneau]] | None = None,
    autoriser_hors_disponibilite: bool = True,
    max_par_jour: int = 2,
) -> Resultat:
    """Place les seances demandees dans la grille.

    `occupes_*` porte ce qui existe deja: une generation ne doit pas ecraser
    les creneaux poses a la main, ni ceux d'une autre classe qui partage
    l'enseignant.

    `max_par_jour` borne les seances d'une meme matiere dans une meme
    journee. Sans cette borne, le glouton empile volontiers les six heures de
    mathematiques d'une classe le lundi, ce qui est valide et inutilisable.

    `autoriser_hors_disponibilite` decide du dernier recours: placer une
    seance sur un creneau que l'enseignant avait dit ne pas pouvoir assurer.
    Le placement le signale, il ne le cache pas.
    """
    disponibilites = disponibilites or {}
    resultat = Resultat()

    pris_enseignants: dict[int, list[Creneau]] = {
        cle: list(valeurs) for cle, valeurs in (occupes_enseignants or {}).items()
    }
    pris_classes: dict[int, list[Creneau]] = {
        cle: list(valeurs) for cle, valeurs in (occupes_classes or {}).items()
    }
    prises_salles: dict[str, list[Creneau]] = {
        cle: list(valeurs) for cle, valeurs in (occupees_salles or {}).items()
    }
    par_jour: dict[tuple[int, int, str], int] = {}

    def _libre(pris, cle, creneau) -> bool:
        return not any(occupe.chevauche(creneau) for occupe in pris.get(cle, ()))

    def _liberte(besoin: Besoin) -> int:
        """Combien de creneaux restent ouverts a cet enseignant.

        C'est la mesure de difficulte qui commande l'ordre: le plus contraint
        passe en premier, sinon ses rares creneaux sont pris par d'autres.
        """
        return sum(
            1
            for creneau in grille
            if _disponibilite(disponibilites, besoin.teacher_id, creneau)
            != "unavailable"
            and _libre(pris_enseignants, besoin.teacher_id, creneau)
        )

    # Les seances les plus contraintes d'abord, et a difficulte egale les
    # matieres les plus lourdes: elles ont le plus de cases a caser.
    ordre = sorted(besoins, key=lambda b: (_liberte(b), -b.seances, b.subject_name))

    for besoin in ordre:
        for numero in range(besoin.seances):
            candidats = []
            for creneau in grille:
                if not _libre(pris_classes, besoin.classroom_id, creneau):
                    continue
                if not _libre(pris_enseignants, besoin.teacher_id, creneau):
                    continue
                if besoin.room and not _libre(prises_salles, besoin.room, creneau):
                    continue

                cle_jour = (besoin.classroom_id, besoin.subject_id, creneau.jour)
                if par_jour.get(cle_jour, 0) >= max_par_jour:
                    continue

                genre = _disponibilite(disponibilites, besoin.teacher_id, creneau)
                if genre == "unavailable" and not autoriser_hors_disponibilite:
                    continue

                candidats.append((POIDS_DISPONIBILITE.get(genre, 2), creneau, genre))

            if not candidats:
                resultat.echecs.append(
                    Echec(
                        assignment_id=besoin.assignment_id,
                        subject_name=besoin.subject_name,
                        motif=(
                            f"Séance {numero + 1}/{besoin.seances} non placée: "
                            "aucun créneau ne laisse l'enseignant, la classe "
                            "et la salle libres en même temps."
                        ),
                    )
                )
                continue

            # Le meilleur creneau: d'abord la disponibilite declaree, puis
            # l'ordre de la semaine -- a egalite, on remplit le debut de
            # semaine et de journee plutot que de disperser.
            candidats.sort(
                key=lambda item: (
                    item[0],
                    JOURS_OUVRES.index(item[1].jour),
                    item[1].debut,
                )
            )
            _, creneau, genre = candidats[0]

            pris_enseignants.setdefault(besoin.teacher_id, []).append(creneau)
            pris_classes.setdefault(besoin.classroom_id, []).append(creneau)
            if besoin.room:
                prises_salles.setdefault(besoin.room, []).append(creneau)
            par_jour[(besoin.classroom_id, besoin.subject_id, creneau.jour)] = (
                par_jour.get((besoin.classroom_id, besoin.subject_id, creneau.jour), 0)
                + 1
            )

            resultat.placements.append(
                Placement(
                    assignment_id=besoin.assignment_id,
                    creneau=creneau,
                    room=besoin.room,
                    hors_disponibilite=(
                        "Créneau déclaré indisponible par l'enseignant."
                        if genre == "unavailable"
                        else ""
                    ),
                )
            )

    return resultat
