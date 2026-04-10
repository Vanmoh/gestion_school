from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand
from django.db import transaction

from apps.accounts.models import UserRole
from apps.school.models import ClassRoom, Student


class Command(BaseCommand):
    help = (
        "Ajoute N eleves dans chaque classe ayant au moins une matiere attribuee "
        "(TeacherAssignment)."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--per-class",
            type=int,
            default=10,
            help="Nombre d'eleves a ajouter par classe (defaut: 10)",
        )
        parser.add_argument(
            "--password",
            type=str,
            default="Student@123",
            help="Mot de passe par defaut des comptes eleves crees",
        )

    @transaction.atomic
    def handle(self, *args, **options):
        per_class = max(0, int(options["per_class"]))
        raw_password = options["password"]

        if per_class == 0:
            self.stdout.write(self.style.WARNING("Aucun eleve a ajouter (per-class=0)."))
            return

        User = get_user_model()

        target_classes = (
            ClassRoom.objects.filter(teacher_assignments__isnull=False)
            .select_related("etablissement")
            .distinct()
            .order_by("etablissement__name", "name", "id")
        )

        if not target_classes.exists():
            self.stdout.write(self.style.WARNING("Aucune classe avec matieres attribuees trouvee."))
            return

        total_students_created = 0
        total_users_created = 0

        for classroom in target_classes:
            etab = classroom.etablissement
            if etab is None:
                self.stdout.write(
                    self.style.WARNING(
                        f"Classe ignoree (pas d'etablissement): {classroom.id} - {classroom.name}"
                    )
                )
                continue

            existing_in_class = Student.objects.filter(classroom=classroom).count()

            class_students_created = 0
            class_users_created = 0

            for offset in range(1, per_class + 1):
                rank = existing_in_class + offset
                base_username = f"stu_e{etab.id}_c{classroom.id}_{rank:03d}".lower()
                username = base_username
                suffix = 1
                while User.objects.filter(username=username).exists():
                    suffix += 1
                    username = f"{base_username}_{suffix}"

                first_name = f"Eleve{rank:02d}"
                last_name = classroom.name.replace(" ", "")[:20]
                email = f"{username}@gestion.school"

                user = User.objects.create(
                    username=username,
                    first_name=first_name,
                    last_name=last_name,
                    email=email,
                    role=UserRole.STUDENT,
                    etablissement=etab,
                    is_active=True,
                )
                user.set_password(raw_password)
                user.save(update_fields=["password"])

                Student.objects.create(
                    user=user,
                    classroom=classroom,
                    etablissement=etab,
                    is_archived=False,
                )

                class_students_created += 1
                class_users_created += 1

            total_students_created += class_students_created
            total_users_created += class_users_created

            self.stdout.write(
                self.style.SUCCESS(
                    f"{etab.name} | {classroom.name}: +{class_students_created} eleves"
                )
            )

        self.stdout.write(
            self.style.SUCCESS(
                f"Termine. Utilisateurs crees: {total_users_created}, eleves crees: {total_students_created}."
            )
        )
