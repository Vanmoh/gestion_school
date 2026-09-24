"""La note se rattache a l'epreuve qui l'a produite, et l'epreuve se publie.

Une note portait `(session, eleve, matiere)` et ignorait le planning. Une
note pouvait donc exister pour une epreuve jamais planifiee, une epreuve
corrigee ne se distinguait pas d'une epreuve en attente, et la publication ne
se decidait que pour la campagne entiere -- alors que les copies reviennent
classe par classe.

La reprise est etroite et ne fabrique rien. Elle rattache par correspondance
exacte, laisse le reste a NULL, et compte ce qu'elle n'a pas pu trancher.
Inventer « l'epreuve de maths de 6e a eu lieu le 12 janvier de 8h a 10h »
pour les notes nees de l'ecran Notes -- qui n'a jamais cree de planning --
aurait pose un fait que l'ecran des familles afficherait comme vrai.

Une note restee sans epreuve suit le drapeau de sa session, qui prend ici son
sens definitif: il gouverne ce qu'aucune epreuve ne porte.
"""

from datetime import timedelta

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models

# Duree retenue pour une epreuve dont les deux horaires sont identiques.
# Deux heures est la duree d'une composition; la valeur est un pis-aller
# visible, que le secretariat corrige, et non une donnee.
DUREE_PAR_DEFAUT = timedelta(hours=2)


def horaire_redresse(debut, fin):
    """Le couple (debut, fin) rendu coherent, ou None s'il l'etait deja.

    Deux cas, deux traitements. Les horaires inverses sont echanges: 10h->8h
    est une transposition, personne n'a voulu dire autre chose. Les horaires
    identiques recoivent une duree par defaut, faute de pouvoir deviner
    laquelle -- c'est le seul endroit de cette migration ou une valeur est
    posee, et elle l'est sur un champ que l'ecole relit.

    Fonction pure, sans base de donnees: c'est la decision qui merite d'etre
    verifiee, et la contrainte interdit desormais d'ecrire en base les cas
    qu'elle traite.
    """
    if fin > debut:
        return None
    if fin < debut:
        return fin, debut

    depuis_minuit = timedelta(
        hours=debut.hour, minutes=debut.minute, seconds=debut.second
    )
    arrivee = depuis_minuit + DUREE_PAR_DEFAUT
    # 23h30 + 2h deborde le jour: on s'arrete a la derniere minute plutot
    # que de repartir a zero, ce qui recreerait l'inversion.
    if arrivee >= timedelta(days=1):
        return debut, fin.replace(hour=23, minute=59, second=59)
    total = int(arrivee.total_seconds())
    return debut, fin.replace(
        hour=total // 3600, minute=(total % 3600) // 60, second=total % 60
    )


def redresser_les_horaires(apps, schema_editor):
    """Rend possible la contrainte « une epreuve finit apres avoir commence ».

    Le modele n'en portait aucune et l'ecran ne validait rien: des epreuves
    saisies a l'envers existent, et la contrainte les refuserait au moment de
    sa creation -- une migration qui echoue sur des donnees reelles.
    """
    ExamPlanning = apps.get_model("school", "ExamPlanning")

    corrigees = []
    for epreuve in ExamPlanning.objects.filter(end_time__lte=models.F("start_time")):
        redresse = horaire_redresse(epreuve.start_time, epreuve.end_time)
        if redresse is None:
            continue
        epreuve.start_time, epreuve.end_time = redresse
        corrigees.append(epreuve)

    if corrigees:
        ExamPlanning.objects.bulk_update(
            corrigees, ["start_time", "end_time"], batch_size=500
        )
        print(f"  {len(corrigees)} horaire(s) d'epreuve redresse(s).")


def ne_rien_defaire(apps, schema_editor):
    """Un horaire redresse ne se reinverse pas: on ne saurait pas lequel."""


def rattacher_les_notes_a_leur_epreuve(apps, schema_editor):
    """Relie chaque note a son epreuve, quand la correspondance est certaine.

    La classe retenue est celle de l'epoque -- `StudentAcademicHistory` -- et
    non `Student.classroom`, que la passation en fin d'annee reecrit: pour une
    note de l'an dernier, la classe actuelle de l'eleve ne designe pas
    l'epreuve qu'il a passee.

    Trois cas sont laisses a NULL et comptes plutot que tranches: l'eleve sans
    classe connue, l'absence d'epreuve correspondante, et l'ambiguite --
    plusieurs epreuves pour la meme classe et la meme matiere dans la meme
    session, ce que la commande de dedoublonnage conserve deliberement quand
    les dates different.
    """
    ExamResult = apps.get_model("school", "ExamResult")
    ExamPlanning = apps.get_model("school", "ExamPlanning")
    StudentAcademicHistory = apps.get_model("school", "StudentAcademicHistory")

    notes = list(
        ExamResult.objects.filter(planning__isnull=True).values(
            "id", "session_id", "subject_id", "student_id"
        )
    )
    if not notes:
        print("  Aucune note a rattacher.")
        return

    sessions = {
        ligne["id"]: (ligne["academic_year_id"], ligne["term"])
        for ligne in apps.get_model("school", "ExamSession")
        .objects.values("id", "academic_year_id", "term")
    }

    # Les epreuves, groupees par (session, classe, matiere). Une liste et non
    # un identifiant: c'est le nombre de candidates qui dit si l'on peut
    # trancher.
    epreuves = {}
    for ligne in ExamPlanning.objects.values(
        "id", "session_id", "classroom_id", "subject_id"
    ):
        cle = (ligne["session_id"], ligne["classroom_id"], ligne["subject_id"])
        epreuves.setdefault(cle, []).append(ligne["id"])

    classes_de_l_epoque = {
        (ligne["student_id"], ligne["academic_year_id"], ligne["term"]): ligne[
            "classroom_id"
        ]
        for ligne in StudentAcademicHistory.objects.values(
            "student_id", "academic_year_id", "term", "classroom_id"
        )
    }
    classe_actuelle = {
        ligne["id"]: ligne["classroom_id"]
        for ligne in apps.get_model("school", "Student").objects.values(
            "id", "classroom_id"
        )
    }

    a_rattacher = []
    sans_classe = 0
    sans_epreuve = 0
    ambigues = 0

    for note in notes:
        annee_et_periode = sessions.get(note["session_id"])
        if annee_et_periode is None:
            sans_epreuve += 1
            continue
        annee_id, periode = annee_et_periode

        classe_id = classes_de_l_epoque.get(
            (note["student_id"], annee_id, periode)
        ) or classe_actuelle.get(note["student_id"])
        if classe_id is None:
            sans_classe += 1
            continue

        candidates = epreuves.get(
            (note["session_id"], classe_id, note["subject_id"]), []
        )
        if not candidates:
            sans_epreuve += 1
            continue
        if len(candidates) > 1:
            ambigues += 1
            continue

        a_rattacher.append(
            ExamResult(id=note["id"], planning_id=candidates[0])
        )

    if a_rattacher:
        ExamResult.objects.bulk_update(a_rattacher, ["planning"], batch_size=500)

    print(
        f"  {len(a_rattacher)} note(s) rattachee(s) a leur epreuve; "
        f"{sans_epreuve} sans epreuve planifiee, {ambigues} ambigue(s), "
        f"{sans_classe} sans classe connue -- celles-ci suivent le drapeau "
        f"de leur session."
    )


def detacher_les_notes(apps, schema_editor):
    """Retour en arriere: la colonne disparait de toute facon."""
    ExamResult = apps.get_model("school", "ExamResult")
    ExamResult.objects.update(planning=None)


def publier_les_epreuves_des_sessions_ouvertes(apps, schema_editor):
    """Une epreuve d'une session deja publiee reste ouverte.

    Sans ce report, la migration refermerait ce que les familles lisaient la
    veille: leur note suivrait desormais le drapeau de l'epreuve, tout neuf
    et donc ferme. C'est la meme precaution que prenait la migration 0059 en
    publiant d'office les sessions terminees.
    """
    ExamPlanning = apps.get_model("school", "ExamPlanning")
    ouvertes = ExamPlanning.objects.filter(session__results_published=True).update(
        results_published=True
    )
    if ouvertes:
        print(f"  {ouvertes} epreuve(s) ouverte(s), leur session l'etait deja.")


def refermer_les_epreuves(apps, schema_editor):
    ExamPlanning = apps.get_model("school", "ExamPlanning")
    ExamPlanning.objects.update(results_published=False)


class Migration(migrations.Migration):

    dependencies = [
        ("school", "0066_etablissement_mot_de_passe_parent_modele"),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.AddField(
            model_name="examplanning",
            name="results_published",
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name="examplanning",
            name="results_published_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="examplanning",
            name="results_published_by",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="published_exam_plannings",
                to=settings.AUTH_USER_MODEL,
            ),
        ),
        migrations.AddField(
            model_name="examresult",
            name="planning",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.RESTRICT,
                related_name="results",
                to="school.examplanning",
            ),
        ),
        # Les donnees avant la contrainte: elle refuserait les epreuves
        # saisies a l'envers, qui existent faute de toute validation jusqu'ici.
        migrations.RunPython(redresser_les_horaires, ne_rien_defaire),
        migrations.AddConstraint(
            model_name="examplanning",
            constraint=models.CheckConstraint(
                condition=models.Q(("end_time__gt", models.F("start_time"))),
                name="epreuve_finit_apres_avoir_commence",
            ),
        ),
        migrations.RunPython(
            rattacher_les_notes_a_leur_epreuve, detacher_les_notes
        ),
        migrations.RunPython(
            publier_les_epreuves_des_sessions_ouvertes, refermer_les_epreuves
        ),
    ]
