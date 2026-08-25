"""Confie le catalogage du fonds documentaire au worker.

Depose un message dans la file et rend la main: c'est tout ce que le service
web doit faire au demarrage. Auparavant il lisait lui-meme neuf pages chez
bkalan.ml, source dont personne ne garantit le temps de reponse, sur les
0,1 CPU du plan gratuit et au moment ou quelqu'un attendait sa premiere page.

    manage.py queue_library_catalogue          # ne recatalogue pas si c'est deja fait
    manage.py queue_library_catalogue --forcer # relit la source malgre tout
"""

from django.core.management.base import BaseCommand

from apps.school.tasks import import_library_catalogue


class Command(BaseCommand):
    help = "Demande au worker Celery de cataloguer le fonds documentaire."

    def add_arguments(self, parser):
        parser.add_argument(
            "--forcer",
            action="store_true",
            help="Recatalogue meme si le fonds est deja en base.",
        )

    def handle(self, *args, **options):
        try:
            resultat = import_library_catalogue.delay(si_vide=not options["forcer"])
        except Exception as exc:  # noqa: BLE001 - le courtier peut etre injoignable
            # Volontairement non bloquant, et sans code de sortie en erreur:
            # un courtier absent ne doit pas empecher le service de demarrer.
            # Le catalogue restera vide, l'API relaiera la source, et la tache
            # planifiee (CELERY_BEAT_SCHEDULE) rattrapera au prochain passage.
            self.stderr.write(
                self.style.WARNING(
                    f"Catalogue non demande: file de travaux injoignable ({exc})."
                )
            )
            return

        self.stdout.write(f"Catalogue confie au worker (tache {resultat.id}).")
