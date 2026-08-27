"""Signale a la direction les cours planifies que personne n'a assures.

La concordance entre l'emploi du temps et l'emargement existe desormais dans
l'API, mais elle demande qu'on aille la consulter. Cette commande la pousse:
une classe restee sans professeur se sait le lendemain matin, pas en fin de
mois sur une fiche de paie.

    manage.py signaler_seances_non_assurees                # la veille
    manage.py signaler_seances_non_assurees --jour 2026-03-12
    manage.py signaler_seances_non_assurees --dry-run
"""

from __future__ import annotations

from datetime import timedelta

from django.core.management.base import BaseCommand, CommandError
from django.utils import timezone
from django.utils.dateparse import parse_date

from apps.accounts.models import UserRole
from apps.school.models import (
    Notification,
    NotificationChannel,
    TeacherScheduleSlot,
    TeacherTimeEntry,
)

DAY_CODES = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]

# Qui doit l'apprendre. Le surveillant organise le remplacement, la direction
# arbitre; le comptable le verra sur la fiche de paie, en son temps.
ROLES_DESTINATAIRES = (UserRole.SUPER_ADMIN, UserRole.DIRECTOR, UserRole.CENSOR)


class Command(BaseCommand):
    help = "Notifie la direction des seances planifiees non assurees."

    def add_arguments(self, parser):
        parser.add_argument(
            "--jour",
            default=None,
            help="Jour a examiner (AAAA-MM-JJ). Par defaut: la veille.",
        )
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Affiche ce qui serait signale sans creer de notification.",
        )

    def handle(self, *args, **options):
        jour = self._jour_examine(options.get("jour"))
        code = DAY_CODES[jour.weekday()]
        if code == "SUN":
            self.stdout.write("Dimanche: aucune seance planifiee.")
            return

        manquees = self._seances_manquees(jour, code)
        if not manquees:
            self.stdout.write(f"{jour}: toutes les seances planifiees ont ete assurees.")
            return

        total = sum(len(seances) for seances in manquees.values())
        if options.get("dry_run"):
            for etablissement, seances in manquees.items():
                self.stdout.write(f"{etablissement}: {len(seances)} seance(s) non assuree(s)")
                for ligne in seances:
                    self.stdout.write(f"  - {ligne}")
            self.stdout.write(f"{total} seance(s) non assuree(s) (dry-run).")
            return

        envoyees = self._notifier(jour, manquees)
        self.stdout.write(
            f"{jour}: {total} seance(s) non assuree(s), {envoyees} notification(s) envoyee(s)."
        )

    def _jour_examine(self, brut):
        if not brut:
            return timezone.localdate() - timedelta(days=1)
        jour = parse_date(str(brut).strip())
        if jour is None:
            raise CommandError("Jour illisible. Format attendu: AAAA-MM-JJ.")
        return jour

    def _seances_manquees(self, jour, code):
        """Les cours du jour qu'aucun pointage ne recoupe, par etablissement."""
        creneaux = TeacherScheduleSlot.objects.select_related(
            "assignment",
            "assignment__teacher",
            "assignment__teacher__user",
            "assignment__teacher__etablissement",
            "assignment__subject",
            "assignment__classroom",
            "assignment__classroom__academic_year",
        ).filter(
            day_of_week=code,
            assignment__classroom__academic_year__start_date__lte=jour,
            assignment__classroom__academic_year__end_date__gte=jour,
        )

        # Une seule requete pour toutes les couvertures du jour: en
        # interroger une par creneau ferait des centaines d'allers-retours.
        couverts = set(
            TeacherTimeEntry.objects.filter(entry_date=jour)
            .filter(slot_coverages__covered_minutes__gt=0)
            .values_list("slot_coverages__schedule_slot_id", flat=True)
        )

        manquees = {}
        for creneau in creneaux:
            if creneau.id in couverts:
                continue
            enseignant = creneau.assignment.teacher
            etablissement = enseignant.etablissement
            if etablissement is None:
                continue

            user = enseignant.user
            nom = (user.get_full_name().strip() or user.username) if user else "Enseignant"
            manquees.setdefault(etablissement, []).append(
                f"{creneau.start_time.strftime('%H:%M')}-{creneau.end_time.strftime('%H:%M')} "
                f"{creneau.assignment.subject.name} en {creneau.assignment.classroom.name} "
                f"({nom})"
            )
        return manquees

    def _notifier(self, jour, manquees):
        """Une notification par responsable, pas une par seance.

        Cinq cours manques un jour de greve produiraient cinq alertes
        identiques dans la meme boite: c'est le recapitulatif du jour qui
        est utile, pas le detail eparpille.
        """
        from apps.accounts.models import User

        envoyees = 0
        for etablissement, seances in manquees.items():
            destinataires = User.objects.filter(
                etablissement=etablissement, role__in=ROLES_DESTINATAIRES
            )
            if not destinataires.exists():
                continue

            detail = "\n".join(f"- {ligne}" for ligne in seances)
            message = (
                f"{len(seances)} séance(s) planifiée(s) le {jour.strftime('%d/%m/%Y')} "
                f"n'ont pas été assurées :\n{detail}"
            )
            for destinataire in destinataires:
                Notification.objects.create(
                    etablissement=etablissement,
                    recipient=destinataire,
                    channel=NotificationChannel.PUSH,
                    title="Séances non assurées",
                    message=message,
                )
                envoyees += 1
        return envoyees
