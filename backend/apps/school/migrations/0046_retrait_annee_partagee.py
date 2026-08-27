"""Retire l'annee partagee, une fois qu'elle ne sert plus a rien.

L'eclatement par etablissement (0044) l'a videe de ses classes, notes,
frais et sessions. La supprimer dans la meme migration etait impossible:
un DELETE laisse des declencheurs de cle etrangere en attente, et Postgres
refuse alors de creer un index dans la meme transaction.

Une annee encore referencee est conservee: un objet dont l'etablissement
reste indeterminable doit rester rattache a quelque chose.
"""

from django.db import migrations, models


def retirer_les_annees_vides(apps, schema_editor):
    AcademicYear = apps.get_model("school", "AcademicYear")
    PromotionRun = apps.get_model("school", "PromotionRun")
    porteurs = [
        apps.get_model("school", nom)
        for nom in (
            "ClassRoom",
            "Grade",
            "GradeValidation",
            "StudentFee",
            "StudentAcademicHistory",
            "CanteenSubscription",
            "ExamSession",
        )
    ]

    for annee in AcademicYear.objects.filter(etablissement__isnull=True):
        encore_utilisee = any(
            modele.objects.filter(academic_year_id=annee.id).exists()
            for modele in porteurs
        ) or PromotionRun.objects.filter(
            models.Q(source_academic_year_id=annee.id)
            | models.Q(target_academic_year_id=annee.id)
        ).exists()

        if not encore_utilisee:
            AcademicYear.objects.filter(pk=annee.id).delete()


def sans_retour(apps, schema_editor):
    """Rien a defaire: seule une annee vide est retiree."""


class Migration(migrations.Migration):

    dependencies = [
        ('school', '0045_contraintes_annee_scolaire'),
    ]

    operations = [
        migrations.RunPython(retirer_les_annees_vides, sans_retour),
    ]
