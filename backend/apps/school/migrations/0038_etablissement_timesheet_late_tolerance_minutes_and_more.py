"""La concordance entre l'emploi du temps et l'emargement enseignant.

Le lien existait, mais sans laisser de trace: le creneau correspondant a un
pointage etait devine a chaque calcul, jamais conserve, et un seul etait
retenu. Un enseignant assurant 8h-10h puis 14h-16h et pointant de 8h a 16h
etait paye deux heures au lieu de quatre.

`TeacherTimeEntryCoverage` conserve desormais chaque cours reellement
couvert. La reprise ci-dessous reconstruit cette liste pour l'historique et
corrige les heures des mois dont la paie n'est pas encore validee -- ceux qui
le sont restent tels qu'ils ont ete payes.
"""

from django.db import migrations, models
import django.db.models.deletion


DAY_MAP = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]


def _minutes(valeur):
    return valeur.hour * 60 + valeur.minute


def _couvertures(entry, slots, tolerance):
    """Les creneaux du jour que la presence recoupe reellement."""
    if entry.check_out_time is None or entry.check_out_time <= entry.check_in_time:
        return []

    presence_debut = _minutes(entry.check_in_time)
    presence_fin = _minutes(entry.check_out_time)

    resultat = []
    for slot in slots:
        debut = _minutes(slot.start_time)
        fin = _minutes(slot.end_time)
        duree = max(fin - debut, 0)
        if duree <= 0:
            continue
        chevauchement = min(fin, presence_fin) - max(debut, presence_debut)
        if chevauchement <= 0:
            continue
        retard = max(presence_debut - debut, 0)
        tolere = min(retard, tolerance)
        resultat.append(
            {
                "slot": slot,
                "planned_minutes": duree,
                "covered_minutes": max(min(chevauchement + tolere, duree), 0),
                "late_minutes": retard,
                "tolerated_late_minutes": tolere,
            }
        )
    return resultat


def reconstruire_les_couvertures(apps, schema_editor):
    """Rejoue le rattachement sur tout l'historique des pointages.

    Les heures ne sont reecrites que la ou la paie du mois n'a pas ete
    validee jusqu'au bout: un bulletin signe par la comptabilite ne change
    pas retroactivement, meme si le nouveau calcul lui est favorable. Ce que
    la reprise apporte partout, en revanche, c'est la trace du rattachement.
    """
    TeacherTimeEntry = apps.get_model("school", "TeacherTimeEntry")
    TeacherTimeEntryCoverage = apps.get_model("school", "TeacherTimeEntryCoverage")
    TeacherScheduleSlot = apps.get_model("school", "TeacherScheduleSlot")
    TeacherPayroll = apps.get_model("school", "TeacherPayroll")

    entrees = list(
        TeacherTimeEntry.objects.select_related("teacher", "etablissement").all()
    )
    if not entrees:
        return

    # Un seul passage sur les creneaux: une requete par pointage ferait des
    # milliers d'allers-retours sur une annee scolaire entiere.
    slots_par_enseignant = {}
    for slot in TeacherScheduleSlot.objects.select_related(
        "assignment", "assignment__classroom", "assignment__classroom__academic_year"
    ):
        slots_par_enseignant.setdefault(slot.assignment.teacher_id, []).append(slot)

    mois_valides = {
        (paie.teacher_id, paie.month.year, paie.month.month)
        for paie in TeacherPayroll.objects.filter(
            level_two_validated_at__isnull=False
        ).only("teacher_id", "month")
    }

    a_creer = []
    a_mettre_a_jour = []
    for entry in entrees:
        jour = DAY_MAP[entry.entry_date.weekday()]
        tolerance = getattr(
            entry.etablissement, "timesheet_late_tolerance_minutes", 15
        ) or 15

        candidats = [
            slot
            for slot in slots_par_enseignant.get(entry.teacher_id, [])
            if slot.day_of_week == jour
            and _annee_couvre(slot, entry.entry_date)
        ]
        candidats.sort(key=lambda slot: (slot.start_time, slot.end_time, slot.id))

        couvertures = _couvertures(entry, candidats, tolerance)
        a_creer.extend(
            TeacherTimeEntryCoverage(
                time_entry_id=entry.id,
                schedule_slot_id=couverture["slot"].id,
                planned_minutes=couverture["planned_minutes"],
                covered_minutes=couverture["covered_minutes"],
                late_minutes=couverture["late_minutes"],
                tolerated_late_minutes=couverture["tolerated_late_minutes"],
            )
            for couverture in couvertures
        )

        entry.planned_minutes = sum(
            max(_minutes(slot.end_time) - _minutes(slot.start_time), 0)
            for slot in candidats
        )
        entry.covered_minutes = sum(c["covered_minutes"] for c in couvertures)

        fige = (
            entry.teacher_id,
            entry.entry_date.year,
            entry.entry_date.month,
        ) in mois_valides
        if not fige and couvertures:
            payables = sum(c["covered_minutes"] for c in couvertures)
            entry.worked_hours = round(payables / 60, 2)
            entry.late_minutes = couvertures[0]["late_minutes"]
            entry.tolerated_late_minutes = couvertures[0]["tolerated_late_minutes"]

        a_mettre_a_jour.append(entry)

    if a_creer:
        TeacherTimeEntryCoverage.objects.bulk_create(a_creer, batch_size=500)
    TeacherTimeEntry.objects.bulk_update(
        a_mettre_a_jour,
        ["planned_minutes", "covered_minutes", "worked_hours", "late_minutes", "tolerated_late_minutes"],
        batch_size=500,
    )


def _annee_couvre(slot, jour):
    """L'annee scolaire de la classe englobe-t-elle cette date."""
    annee = getattr(slot.assignment.classroom, "academic_year", None)
    if annee is None:
        return True
    if annee.start_date and annee.start_date > jour:
        return False
    if annee.end_date and annee.end_date < jour:
        return False
    return True


class Migration(migrations.Migration):

    dependencies = [
        ('school', '0037_discipline_resolved_at_and_categories'),
    ]

    operations = [
        migrations.AddField(
            model_name='etablissement',
            name='timesheet_late_tolerance_minutes',
            field=models.PositiveSmallIntegerField(default=15, validators=[django.core.validators.MaxValueValidator(120)]),
        ),
        migrations.AddField(
            model_name='teachertimeentry',
            name='covered_minutes',
            field=models.PositiveIntegerField(default=0),
        ),
        migrations.AddField(
            model_name='teachertimeentry',
            name='off_schedule_reason',
            field=models.CharField(blank=True, max_length=255),
        ),
        migrations.AddField(
            model_name='teachertimeentry',
            name='planned_minutes',
            field=models.PositiveIntegerField(default=0),
        ),
        migrations.CreateModel(
            name='TeacherTimeEntryCoverage',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('planned_minutes', models.PositiveIntegerField(default=0)),
                ('covered_minutes', models.PositiveIntegerField(default=0)),
                ('late_minutes', models.PositiveIntegerField(default=0)),
                ('tolerated_late_minutes', models.PositiveIntegerField(default=0)),
                ('schedule_slot', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='time_coverages', to='school.teacherscheduleslot')),
                ('time_entry', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='slot_coverages', to='school.teachertimeentry')),
            ],
            options={
                'ordering': ['schedule_slot__start_time', 'id'],
                'indexes': [models.Index(fields=['schedule_slot'], name='ttcoverage_slot_idx')],
                'constraints': [models.UniqueConstraint(fields=('time_entry', 'schedule_slot'), name='teacher_time_entry_coverage_unique')],
            },
        ),
        migrations.RunPython(
            reconstruire_les_couvertures,
            migrations.RunPython.noop,
        ),
    ]
