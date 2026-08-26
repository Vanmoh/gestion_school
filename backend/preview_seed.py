"""Enrichit l'etablissement de demonstration pour l'apercu UI.

Cree assez d'eleves, de creneaux d'emploi du temps et d'incidents
disciplinaires pour que les ecrans concernes soient reellement lisibles.
Idempotent: relancer le script ne duplique rien.

Usage:
    docker compose exec -T backend python preview_seed.py
"""

import os
from datetime import date, time

import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
django.setup()

from apps.accounts.models import User, UserRole  # noqa: E402
from apps.school.models import (  # noqa: E402
    ClassRoom,
    DisciplineIncident,
    ParentProfile,
    Student,
    TeacherAssignment,
    TeacherScheduleSlot,
)

FIRST_NAMES_M = [
    "Mamadou", "Amadou", "Ibrahim", "Ousmane", "Boubacar",
    "Souleymane", "Adama", "Issa", "Daouda", "Youssouf",
]
FIRST_NAMES_F = [
    "Fatoumata", "Aissatou", "Mariam", "Kadiatou", "Oumou",
    "Aminata", "Awa", "Ramata", "Safiatou", "Hawa",
]
LAST_NAMES = [
    "Coulibaly", "Diarra", "Keita", "Diallo", "Traore",
    "Cisse", "Sow", "Kone", "Camara", "Bah",
    "Sidibe", "Ndiaye", "Fall", "Thiam", "Gueye",
    "Sangare", "Dembele", "Toure", "Konate", "Maiga",
]


def main():
    classroom = ClassRoom.objects.order_by("id").first()
    if classroom is None:
        raise SystemExit("Aucune classe: lance d'abord seed_demo_data.")
    etablissement = classroom.etablissement
    parent = ParentProfile.objects.order_by("id").first()

    print(f"Classe cible: {classroom.name} ({etablissement.name})")

    # --- Eleves -------------------------------------------------------
    created_students = 0
    for index in range(20):
        female = index % 2 == 1
        first = (FIRST_NAMES_F if female else FIRST_NAMES_M)[index // 2 % 10]
        last = LAST_NAMES[index % len(LAST_NAMES)]
        username = f"eleve_demo_{index + 1:02d}"

        user, user_created = User.objects.get_or_create(
            username=username,
            defaults={
                "first_name": first,
                "last_name": last,
                "role": UserRole.STUDENT,
                "email": f"{username}@demo.local",
                "phone": f"+223 70 {10 + index:02d} {20 + index:02d} {30 + index:02d}",
                "etablissement": etablissement,
            },
        )
        if user_created:
            user.set_password("Password@123")
            user.save()

        student, student_created = Student.objects.get_or_create(
            user=user,
            defaults={
                "gender": "F" if female else "M",
                "birth_date": date(2010 + index % 4, 1 + index % 12, 1 + index % 27),
                "classroom": classroom,
                "etablissement": etablissement,
                # Quelques archives pour que le tri sur Statut soit visible.
                "is_archived": index % 7 == 0,
                # Un enfant du parent de demo sur trois, pour la vue parent.
                "parent": parent if index % 3 == 0 else None,
            },
        )
        if student_created:
            created_students += 1
    print(f"Eleves crees: {created_students}")

    # --- Emploi du temps ----------------------------------------------
    assignments = list(TeacherAssignment.objects.filter(classroom=classroom))
    if not assignments:
        print("Aucune affectation enseignant: creneaux ignores.")
    else:
        ranges = [
            (time(8, 0), time(10, 0)),
            (time(10, 15), time(12, 15)),
            (time(14, 0), time(16, 0)),
        ]
        days = ["MON", "TUE", "WED", "THU", "FRI", "SAT"]
        created_slots = 0
        position = 0
        for day in days:
            for slot_index, (start, end) in enumerate(ranges):
                # Le samedi s'arrete a midi, comme dans un vrai planning.
                if day == "SAT" and slot_index == 2:
                    continue
                assignment = assignments[position % len(assignments)]
                position += 1
                _, created = TeacherScheduleSlot.objects.get_or_create(
                    assignment=assignment,
                    day_of_week=day,
                    start_time=start,
                    end_time=end,
                    defaults={"room": f"Salle {101 + (position % 4)}"},
                )
                if created:
                    created_slots += 1
        print(f"Creneaux crees: {created_slots}")

    # --- Incidents disciplinaires --------------------------------------
    if parent is None:
        print("Aucun parent de demo: incidents ignores.")
    else:
        children = list(Student.objects.filter(parent=parent).order_by("id")[:3])
        incidents = [
            ("retard", "Trois retards en une semaine sur le cours de 8h.",
             "low", "resolved", "Avertissement oral", True),
            ("indiscipline", "Bavardages repetes malgre deux rappels a l'ordre.",
             "medium", "open", "", True),
            ("degradation", "Degradation d'une chaise en salle 102.",
             "high", "open", "Reparation a la charge de la famille", False),
            ("absence_injustifiee", "Absent au cours de mathematiques du matin.",
             "medium", "resolved", "Rattrapage impose", True),
            ("tenue", "Tenue non conforme au reglement interieur.",
             "low", "open", "", False),
        ]
        created_incidents = 0
        for index, (category, description, severity, status, sanction, notified) in enumerate(
            incidents
        ):
            if not children:
                break
            student = children[index % len(children)]
            _, created = DisciplineIncident.objects.get_or_create(
                student=student,
                category=category,
                incident_date=date(2026, 3 + index % 4, 5 + index * 3),
                defaults={
                    "description": description,
                    "severity": severity,
                    "status": status,
                    "sanction": sanction,
                    "parent_notified": notified,
                },
            )
            if created:
                created_incidents += 1
        print(f"Incidents crees: {created_incidents} sur {len(children)} enfant(s)")

    print("Enrichissement termine.")


if __name__ == "__main__":
    main()
