"""Le fonds papier remis d'aplomb.

Trois corrections de fond, sans rapport avec l'affichage:

- l'ISBN etait unique pour toute la plateforme, ce qui empechait la deuxieme
  ecole d'enregistrer le manuel que la premiere possedait deja;
- `quantity_available` etait saisi a la main et ne bougeait jamais: un livre
  prete restait annonce disponible. Il devient derive, et la reprise
  ci-dessous remet les compteurs d'accord avec les emprunts en cours;
- la penalite de retard etait tapee a la main a la creation de l'emprunt,
  c'est-a-dire avant meme qu'il y ait retard. Elle se calcule desormais au
  retour, au tarif journalier de l'etablissement -- zero par defaut, donc
  sans effet tant qu'une ecole ne le renseigne pas.
"""

from django.db import migrations, models


def recalculer_les_disponibilites(apps, schema_editor):
    """Le compteur en rayon, remis d'accord avec les emprunts non rendus.

    Les valeurs en base viennent d'une saisie manuelle jamais decrementee:
    les reprendre telles quelles laisserait le premier ecran mentir encore.
    """
    Book = apps.get_model("school", "Book")
    Borrow = apps.get_model("school", "Borrow")

    sortis = {}
    for livre_id in Borrow.objects.filter(returned_at__isnull=True).values_list(
        "book_id", flat=True
    ):
        sortis[livre_id] = sortis.get(livre_id, 0) + 1

    a_corriger = []
    for livre in Book.objects.all().only("id", "quantity_total", "quantity_available"):
        disponible = max(0, livre.quantity_total - sortis.get(livre.id, 0))
        if disponible != livre.quantity_available:
            livre.quantity_available = disponible
            a_corriger.append(livre)

    if a_corriger:
        Book.objects.bulk_update(a_corriger, ["quantity_available"])


class Migration(migrations.Migration):

    dependencies = [
        ('school', '0034_librarycollection_etablissement_and_more'),
    ]

    operations = [
        migrations.RunPython(
            recalculer_les_disponibilites,
            migrations.RunPython.noop,
        ),
        migrations.AddField(
            model_name='etablissement',
            name='library_penalty_per_day',
            field=models.DecimalField(decimal_places=2, default=0, max_digits=10),
        ),
        migrations.AlterField(
            model_name='book',
            name='isbn',
            field=models.CharField(max_length=30),
        ),
        migrations.AddConstraint(
            model_name='book',
            constraint=models.UniqueConstraint(condition=models.Q(('etablissement__isnull', True), models.Q(('isbn', ''), _negated=True)), fields=('isbn',), name='book_isbn_unique_sans_etablissement'),
        ),
        migrations.AddConstraint(
            model_name='book',
            constraint=models.UniqueConstraint(condition=models.Q(('etablissement__isnull', False), models.Q(('isbn', ''), _negated=True)), fields=('etablissement', 'isbn'), name='book_isbn_unique_par_etablissement'),
        ),
    ]
