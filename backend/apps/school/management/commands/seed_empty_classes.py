"""Peuple les classes vides d'eleves de demonstration.

Une classe sans eleve rend l'ecran d'emargement intestable: la feuille
d'appel affiche « aucun eleve », ce qui est exact mais ne montre rien. Cette
commande comble les classes vides pour qu'on puisse voir, et essayer.

Elle ne touche jamais une classe qui a deja des eleves.
"""

import random
from datetime import date, timedelta

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand
from django.db import transaction
from django.db.models import Count

from apps.accounts.models import UserRole
from apps.school.models import ClassRoom, Student

User = get_user_model()

# Prenoms et noms courants au Mali. Les listes sont separees par genre pour
# que le prenom, le genre et le matricule -- qui encode le genre -- restent
# coherents entre eux.
PRENOMS_GARCONS = [
    "Amadou", "Boubacar", "Cheick", "Daouda", "Drissa", "Ibrahim", "Issa",
    "Lassine", "Mamadou", "Modibo", "Moussa", "Oumar", "Ousmane", "Salif",
    "Seydou", "Sekou", "Souleymane", "Adama", "Bakary", "Bourama", "Fousseyni",
    "Hamidou", "Karim", "Madou", "Mahamadou", "Nouhoum", "Sidiki", "Yacouba",
    "Youssouf", "Abdoulaye",
]

PRENOMS_FILLES = [
    "Aminata", "Assitan", "Awa", "Bintou", "Coumba", "Djeneba", "Fanta",
    "Fatoumata", "Hawa", "Kadiatou", "Kadidia", "Korotoumou", "Mariam",
    "Nana", "Oumou", "Ramata", "Rokia", "Safiatou", "Salimata", "Sanata",
    "Tenin", "Aissata", "Alima", "Batoma", "Diahara", "Fadima", "Hapsatou",
    "Maimouna", "Naba", "Sitan",
]

NOMS = [
    "Bagayoko", "Ballo", "Bamba", "Berthe", "Camara", "Cisse", "Coulibaly",
    "Dembele", "Diakite", "Diallo", "Diarra", "Doumbia", "Fofana", "Guindo",
    "Haidara", "Kane", "Keita", "Kone", "Konate", "Maiga", "Mariko", "Niang",
    "Ouattara", "Samake", "Sangare", "Sanogo", "Sidibe", "Sissoko", "Sow",
    "Tangara", "Toure", "Traore", "Sacko", "Kouyate", "Dicko",
]


class Command(BaseCommand):
    help = "Cree des eleves de demonstration dans les classes vides."

    def add_arguments(self, parser):
        parser.add_argument(
            "--cible",
            type=int,
            default=30,
            help="Effectif vise par classe (defaut: 30). Les classes qui "
            "l'atteignent deja ne sont pas touchees.",
        )
        parser.add_argument(
            "--graine",
            type=int,
            default=2026,
            help="Graine aleatoire: deux executions donnent les memes noms.",
        )

    def handle(self, *args, **options):
        cible = options["cible"]
        alea = random.Random(options["graine"])

        # Objectif d'effectif plutot que remplissage: la commande devient
        # rejouable, et une classe a demi peuplee est completee au lieu d'etre
        # ignoree parce qu'elle n'est plus « vide ».
        a_completer = [
            classe
            for classe in ClassRoom.objects.annotate(effectif=Count("students"))
            .select_related("etablissement")
            .order_by("etablissement__name", "name")
            if classe.effectif < cible
        ]

        if not a_completer:
            self.stdout.write(f"Toutes les classes atteignent deja {cible} eleves.")
            return

        self.stdout.write(
            f"{len(a_completer)} classes sous {cible} eleves."
        )

        total = 0
        for classe in a_completer:
            manquants = cible - classe.effectif
            cree = self._peupler(classe, manquants, alea)
            total += cree
            etablissement = getattr(classe.etablissement, "name", "-")
            self.stdout.write(
                f"  {etablissement:22} {classe.name:24} "
                f"{classe.effectif} -> {classe.effectif + cree}"
            )

        self.stdout.write(self.style.SUCCESS(f"\n{total} eleves crees."))

    def _peupler(self, classe, nombre, alea):
        cree = 0
        deja = classe.students.count()
        for rang in range(nombre):
            index = deja + rang
            # Alternance stricte plutot qu'un tirage: un tirage laisse des
            # classes a 25 garcons pour 5 filles, ce qui ne ressemble a rien.
            fille = index % 2 == 1
            prenom = alea.choice(PRENOMS_FILLES if fille else PRENOMS_GARCONS)
            nom = alea.choice(NOMS)

            with transaction.atomic():
                utilisateur = self._creer_compte(classe, prenom, nom, alea)
                Student.objects.create(
                    user=utilisateur,
                    classroom=classe,
                    etablissement=classe.etablissement,
                    gender=Student.Gender.FEMALE if fille else Student.Gender.MALE,
                    birth_date=self._naissance(alea),
                    enrollment_date=self._inscription(classe),
                )
            cree += 1
        return cree

    def _creer_compte(self, classe, prenom, nom, alea):
        base = f"{prenom}.{nom}".lower().replace(" ", "")
        identifiant = base
        suffixe = 1
        while User.objects.filter(username=identifiant).exists():
            suffixe += 1
            identifiant = f"{base}{suffixe}"

        return User.objects.create_user(
            username=identifiant,
            password=f"Eleve{alea.randint(1000, 9999)}!",
            first_name=prenom,
            last_name=nom.upper(),
            role=UserRole.STUDENT,
            etablissement=classe.etablissement,
        )

    @staticmethod
    def _naissance(alea):
        """Entre 11 et 19 ans: la fourchette du secondaire."""
        age_en_jours = alea.randint(11 * 365, 19 * 365)
        return date.today() - timedelta(days=age_en_jours)

    @staticmethod
    def _inscription(classe):
        """Rentree de l'annee scolaire de la classe, jamais dans le futur.

        `Student.clean` refuse une inscription postdatee: elle fausserait les
        effectifs de l'annee en cours sans qu'aucun ecran ne le signale.
        """
        annee = getattr(classe, "academic_year", None)
        debut = getattr(annee, "start_date", None)
        aujourdhui = date.today()
        if debut and debut <= aujourdhui:
            return debut
        return aujourdhui
