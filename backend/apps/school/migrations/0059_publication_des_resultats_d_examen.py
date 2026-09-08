"""Les resultats d'examen s'ouvrent aux familles par un geste, non par la saisie.

Les sessions deja terminees sont publiees d'office: leurs notes etaient
visibles avant cette migration, et les refermer retirerait aux familles ce
qu'elles consultaient hier. Les sessions en cours ou a venir restent fermees
-- c'est precisement le cas que la publication vient couvrir.
"""

from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


def publier_les_sessions_terminees(apps, schema_editor):
    """Ouvre les sessions dont les epreuves sont passees.

    Le critere est la date de fin: une session terminee a deja rendu ses
    notes visibles, la refermer serait une regression pour les familles.
    """
    from django.utils import timezone

    ExamSession = apps.get_model("school", "ExamSession")
    aujourd_hui = timezone.now().date()
    ExamSession.objects.filter(end_date__lt=aujourd_hui).update(
        results_published=True
    )


def refermer_les_sessions_publiees(apps, schema_editor):
    """Retour en arriere: tout se referme, le champ disparait de toute facon."""
    ExamSession = apps.get_model("school", "ExamSession")
    ExamSession.objects.update(results_published=False)


class Migration(migrations.Migration):

    dependencies = [
        ('school', '0058_bareme_de_frais'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.AddField(
            model_name='examsession',
            name='results_published',
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name='examsession',
            name='results_published_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='examsession',
            name='results_published_by',
            field=models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='published_exam_sessions', to=settings.AUTH_USER_MODEL),
        ),
        migrations.RunPython(
            publier_les_sessions_terminees, refermer_les_sessions_publiees
        ),
    ]
