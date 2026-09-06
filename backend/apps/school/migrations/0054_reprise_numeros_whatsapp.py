"""Reprise des numeros WhatsApp depuis le repertoire existant.

`ParentProfile.whatsapp_phone` nait vide, et une ecole de six cents eleves ne
va pas ressaisir six cents numeros pour ouvrir la fonction. Ceux que porte
deja `User.phone` sont donc repris -- mais seulement ceux dont la forme ne
laisse aucun doute.

Ce qui est repris: « 76 12 34 56 », « 0022376123456 », « +223 76-12-34-56 ».
Ce qui ne l'est pas: une case contenant deux numeros (« 76 12 34 56 / 66 74
22 32 »), la forme la plus repandue des fiches papier. Choisir le premier des
deux serait deviner a qui l'ecole s'adresse, et un bulletin envoye au mauvais
telephone ne se rattrape pas. Ces fiches restent vides et l'ecran les signale.

La reprise ne donne aucun consentement: `whatsapp_consent` reste faux pour
tout le monde. Un numero connu n'est pas une autorisation d'envoi, et aucun
bulletin ne partira tant que la famille n'aura pas ete interrogee.
"""

from django.db import migrations


def reprendre_les_numeros(apps, schema_editor):
    from apps.school.phone_utils import normaliser_numero

    ParentProfile = apps.get_model("school", "ParentProfile")

    repris = 0
    a_corriger = []

    profils = ParentProfile.objects.select_related("user").exclude(user__isnull=True)
    for profil in profils.iterator():
        if (profil.whatsapp_phone or "").strip():
            continue

        brut = str(getattr(profil.user, "phone", "") or "").strip()
        if not brut:
            continue

        numero = normaliser_numero(brut)
        if numero is None:
            a_corriger.append(f"{profil.user.get_full_name() or profil.user.username} : « {brut} »")
            continue

        profil.whatsapp_phone = numero
        profil.save(update_fields=["whatsapp_phone"])
        repris += 1

    if repris:
        print(f"\n  {repris} numéro(s) WhatsApp repris depuis le répertoire.")
    if a_corriger:
        print(
            f"  {len(a_corriger)} fiche(s) parent à corriger à la main "
            "(numéro ambigu ou incomplet) :"
        )
        for ligne in a_corriger[:20]:
            print(f"    - {ligne}")
        if len(a_corriger) > 20:
            print(f"    ... et {len(a_corriger) - 20} autre(s).")


def vider_les_numeros(apps, schema_editor):
    """Retour en arriere: le champ redevient vide.

    Sans reciproque, un `migrate` descendant echouerait alors que la donnee
    reprise est integralement reconstructible depuis `User.phone`.
    """
    ParentProfile = apps.get_model("school", "ParentProfile")
    ParentProfile.objects.exclude(whatsapp_phone="").update(whatsapp_phone="")


class Migration(migrations.Migration):

    dependencies = [
        ("school", "0053_bulletin_whatsapp"),
    ]

    operations = [
        migrations.RunPython(reprendre_les_numeros, vider_les_numeros),
    ]
