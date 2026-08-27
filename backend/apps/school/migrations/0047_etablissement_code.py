"""L'etablissement porte enfin son propre code.

Le prefixe des matricules eleves -- « RC15 » dans RC15CG25E3566F -- etait
derive des initiales du nom a chaque generation. Deux consequences: renommer
une ecole changeait le prefixe de tous ses futurs matricules, et deux ecoles
aux memes initiales (« Rive Ouest » et « Rive Centre ») produisaient le meme
prefixe, donc des matricules qui se disputaient la meme unicite globale.

La reprise ci-dessous pose le code que la derivation aurait produit, en
departageant les doublons: aucun matricule deja emis ne change de forme, et
les codes cessent de bouger.
"""

from django.db import migrations, models


def _initiales(nom):
    import re
    import unicodedata

    decompose = unicodedata.normalize("NFD", nom or "")
    sans_accent = "".join(c for c in decompose if unicodedata.category(c) != "Mn")
    mots = re.findall(r"[A-Z0-9]+", sans_accent.upper())
    if len(mots) >= 2:
        return "".join(mot[0] for mot in mots[:2])
    if mots:
        return mots[0][:2]
    return "GS"


def poser_les_codes(apps, schema_editor):
    """Le code que la derivation produisait, fige une fois pour toutes.

    Les collisions sont departagees par un suffixe numerique: deux ecoles
    aux memes initiales gardent des prefixes distincts, ce que la derivation
    ne savait pas faire.
    """
    Etablissement = apps.get_model("school", "Etablissement")

    pris = set()
    for etablissement in Etablissement.objects.order_by("id"):
        if (etablissement.code or "").strip():
            pris.add(etablissement.code.strip().upper())
            continue

        base = _initiales(etablissement.name)
        candidat = base
        suffixe = 2
        while candidat in pris:
            candidat = f"{base}{suffixe}"
            suffixe += 1

        etablissement.code = candidat
        etablissement.save(update_fields=["code"])
        pris.add(candidat)


class Migration(migrations.Migration):

    dependencies = [
        ('school', '0046_retrait_annee_partagee'),
    ]

    operations = [
        migrations.AddField(
            model_name='etablissement',
            name='code',
            field=models.CharField(blank=True, max_length=8),
        ),
        migrations.AddConstraint(
            model_name='etablissement',
            constraint=models.UniqueConstraint(condition=models.Q(('code', ''), _negated=True), fields=('code',), name='etablissement_code_unique'),
        ),
        migrations.RunPython(poser_les_codes, migrations.RunPython.noop),
    ]
