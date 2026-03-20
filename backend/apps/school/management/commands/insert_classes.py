from django.core.management.base import BaseCommand
from apps.school.models import Etablissement, ClassRoom, AcademicYear, Level, Section
from django.db import transaction

CLASSES = {
    "Lycée Technique Oumar Bah (LTOB)": [
        "10ème CT", "11ème CG", "11ème GM", "12ème CG", "12ème GM"
    ],
    "Lycée Technique Oumar Bah (LOBK)": [
        "10ème CG1", "10ème CG2", "11ème SES1", "11ème SES2", "11ème TLL", "11ème S", "12ème TSS1", "12ème TSS2", "12ème TSECO1", "12ème TSECO2", "12ème TLL", "12ème TSE", "12ème TSEXP"
    ],
    "IFP-OBK": [
        "1ère Année TC", "1ère Année DB1", "1ère Année DB2", "1ère Année EM1", "1ère Année EM2",
        "2ème Année TC", "2ème Année DB1", "2ème Année DB2", "2ème Année EM1", "2ème Année EM2",
        "3ème Année TC", "3ème Année BD1", "3ème Année BD2", "3ème Année EM1", "3ème Année EM2"
    ],
    "Complexe Scolaire Omar Bah (CSOB)": [
        "1ère Année", "2ème année", "3ème Année", "4ème Année", "5ème Année", "6ème Année", "7ème Année", "8ème Année", "9ème Année (DEF)"
    ]
}

DEFAULT_LEVEL = "Général"
DEFAULT_SECTION = "Aucune"

class Command(BaseCommand):
    help = 'Insère les classes dans chaque établissement selon la liste fournie.'

    @transaction.atomic
    def handle(self, *args, **options):
        self.stdout.write(self.style.WARNING("Début de l'insertion des classes par établissement..."))
        # Récupère ou crée le niveau et la section par défaut
        level, _ = Level.objects.get_or_create(name=DEFAULT_LEVEL)
        section, _ = Section.objects.get_or_create(name=DEFAULT_SECTION)
        # Récupère l'année académique active
        academic_year = AcademicYear.objects.filter(is_active=True).order_by('-start_date').first()
        if not academic_year:
            self.stdout.write(self.style.ERROR("Aucune année académique active trouvée !"))
            return
        for etab_name, classes in CLASSES.items():
            etab = Etablissement.objects.filter(name__icontains=etab_name).first()
            if not etab:
                self.stdout.write(self.style.ERROR(f"Établissement non trouvé : {etab_name}"))
                continue
            self.stdout.write(self.style.WARNING(f"Insertion des classes pour {etab.name}..."))
            created = 0
            for class_name in classes:
                obj, was_created = ClassRoom.objects.get_or_create(
                    name=class_name,
                    level=level,
                    section=section,
                    academic_year=academic_year,
                    etablissement=etab
                )
                if was_created:
                    created += 1
            self.stdout.write(self.style.SUCCESS(f"{created} classes insérées pour {etab.name}"))
        self.stdout.write(self.style.SUCCESS("Insertion des classes terminée."))
