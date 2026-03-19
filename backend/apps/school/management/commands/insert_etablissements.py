from django.core.management.base import BaseCommand
from apps.school.models import Etablissement

class Command(BaseCommand):
    help = 'Insère les établissements de référence dans la base.'

    def handle(self, *args, **options):
        self.stdout.write(self.style.WARNING("Début de la commande d'insertion des établissements..."))
        etablissements = [
            "Lycée Technique Oumar Bah (LTOB)",
            "Lycée Technique Oumar Bah (LOBK)",
            "IFP-OBK",
            "Complexe Scolaire Omar Bah (CSOB)",
        ]
        self.stdout.write(self.style.WARNING(f"Nombre d'établissements à insérer : {len(etablissements)}"))
        created = 0
        for name in etablissements:
            self.stdout.write(self.style.WARNING(f"Insertion ou récupération de : {name}"))
            obj, was_created = Etablissement.objects.get_or_create(name=name)
            self.stdout.write(self.style.WARNING(f"Résultat : {'créé' if was_created else 'déjà existant'}"))
            if was_created:
                created += 1
        total = Etablissement.objects.count()
        self.stdout.write(self.style.SUCCESS(f"{created} établissements insérés (nouveaux). Total en base : {total}"))
