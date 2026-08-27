"""Le stock se deduit de ses mouvements.

`quantity` valait ce qu'un increment avait laisse, et cet increment ne jouait
qu'a la creation d'un mouvement: supprimer une entree de cinquante laissait
les cinquante au stock, corriger un mouvement ne changeait rien, et une
sortie de cent sur cinq disponibles affichait -95.

La reprise ci-dessous rend chaque article coherent avec son historique:

- l'ecart entre la quantite affichee et la somme des mouvements devient un
  mouvement d'entree « Stock initial (reprise) »: c'est ce qui existait avant
  que le magasin ne tienne un journal, et le perdre viderait les rayons;
- une quantite derivee negative est ramenee a zero par un mouvement de
  regularisation explicite. Un stock negatif n'est pas une alerte, c'est une
  donnee fausse -- et la corriger en silence effacerait la trace de ce qui
  s'est passe.
"""

from django.db import migrations
from django.db.models import Q, Sum


def deriver_les_stocks(apps, schema_editor):
    StockItem = apps.get_model("school", "StockItem")
    StockMovement = apps.get_model("school", "StockMovement")

    for article in StockItem.objects.all().iterator():
        totaux = StockMovement.objects.filter(item=article).aggregate(
            entrees=Sum("quantity", filter=Q(movement_type="in")),
            sorties=Sum("quantity", filter=Q(movement_type="out")),
        )
        derivee = (totaux["entrees"] or 0) - (totaux["sorties"] or 0)

        # Ce que le magasin detenait avant de tenir un journal.
        ouverture = article.quantity - derivee
        if ouverture > 0:
            StockMovement.objects.create(
                item=article,
                movement_type="in",
                quantity=ouverture,
                reason="Stock initial (reprise)",
            )
            derivee += ouverture

        if derivee < 0:
            StockMovement.objects.create(
                item=article,
                movement_type="in",
                quantity=-derivee,
                reason="Régularisation d'un stock négatif",
            )
            derivee = 0

        if article.quantity != derivee:
            article.quantity = derivee
            article.save(update_fields=["quantity"])


class Migration(migrations.Migration):

    dependencies = [
        ("school", "0049_annee_scolaire_sur_les_faits_dates"),
    ]

    operations = [
        migrations.RunPython(deriver_les_stocks, migrations.RunPython.noop),
    ]
