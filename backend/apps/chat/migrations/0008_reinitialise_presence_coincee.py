from django.db import migrations


def reinitialiser_les_compteurs(apps, schema_editor):
    """Remet a zero les sockets fantomes laisses par l'ancienne logique.

    Un socket ferme sans prevenir -- navigateur tue, wifi coupe, serveur
    redemarre -- n'appelait jamais `disconnect()`: le compteur restait a 1 et
    le compte s'affichait « en ligne » indefiniment. Des comptes trainaient
    ainsi verts depuis des jours.

    La presence se lit desormais sur l'horodatage seul, mais ces compteurs
    restes en l'air fausseraient encore le decompte des sockets ouverts. On
    repart d'une base propre; les vrais sockets se recomptent a la prochaine
    connexion.
    """
    ChatPresence = apps.get_model("chat", "ChatPresence")
    ChatPresence.objects.update(connection_count=0, is_online=False)


class Migration(migrations.Migration):
    dependencies = [
        ("chat", "0007_chatmessage_reply_to"),
    ]

    operations = [
        # Irreversible dans les faits: on ne sait pas reconstituer des sockets
        # dont on vient d'etablir qu'ils n'existaient plus.
        migrations.RunPython(reinitialiser_les_compteurs, migrations.RunPython.noop),
    ]
