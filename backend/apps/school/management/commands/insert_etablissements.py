from django.core.management.base import BaseCommand
from django.apps import apps
from django.db import transaction
from django.db.models import ForeignKey
from apps.school.models import Etablissement


class Command(BaseCommand):
    help = 'Insère les établissements de référence dans la base.'

    CANONICAL_ETABLISSEMENTS = [
        "LTOB",
        "LOBK",
        "IFP-OBK",
        "Complexe Scolaire Oumar Bah",
    ]

    ALIAS_TO_CANONICAL = {
        "Lycée Technique Oumar Bah (LTOB)": "LTOB",
        "Lycée Technique Oumar Bah (LOBK)": "LOBK",
        "Lycée Oumar Bah de Kaloum": "LOBK",
        "Complexe Scolaire Omar Bah (CSOB)": "Complexe Scolaire Oumar Bah",
    }

    def handle(self, *args, **options):
        self.stdout.write(self.style.WARNING("Début de la commande d'insertion des établissements..."))

        self.stdout.write(self.style.WARNING(
            f"Nombre d'établissements canoniques : {len(self.CANONICAL_ETABLISSEMENTS)}"
        ))

        created = 0
        for name in self.CANONICAL_ETABLISSEMENTS:
            self.stdout.write(self.style.WARNING(f"Insertion ou récupération de : {name}"))
            obj, was_created = Etablissement.objects.get_or_create(name=name)
            self.stdout.write(self.style.WARNING(f"Résultat : {'créé' if was_created else 'déjà existant'}"))
            if was_created:
                created += 1

        merged_updates = 0
        with transaction.atomic():
            for alias_name, canonical_name in self.ALIAS_TO_CANONICAL.items():
                alias = Etablissement.objects.filter(name=alias_name).first()
                if not alias:
                    continue

                canonical = Etablissement.objects.get(name=canonical_name)
                if alias.id == canonical.id:
                    continue

                self.stdout.write(
                    self.style.WARNING(f"Fusion de l'alias '{alias_name}' vers '{canonical_name}'")
                )

                for model in apps.get_models():
                    for field in model._meta.get_fields():
                        if isinstance(field, ForeignKey) and getattr(field.remote_field, "model", None) is Etablissement:
                            updated = model.objects.filter(**{field.name: alias}).update(**{field.name: canonical})
                            merged_updates += updated

                alias.delete()

        total = Etablissement.objects.count()
        self.stdout.write(
            self.style.SUCCESS(
                f"{created} établissements insérés (nouveaux). Références fusionnées : {merged_updates}. Total en base : {total}"
            )
        )
