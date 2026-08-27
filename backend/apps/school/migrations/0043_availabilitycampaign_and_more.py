"""La collecte des disponibilites entre dans un cadre.

Elle n'avait ni debut, ni fin, ni annee scolaire: les declarations de l'an
dernier se melaient a celles de la rentree, et rien ne disait qui avait
repondu. Une campagne borne la collecte dans le temps, la rattache a une
annee, et `TeacherAvailabilityResponse` distingue enfin l'enseignant qui n'a
rien a declarer de celui qui n'a pas encore ouvert l'ecran.

`campaign` reste vide sur les declarations existantes: elles ont ete saisies
hors de tout cadre, et leur en inventer un retroactivement les rattacherait
a une annee dont personne ne peut affirmer qu'elle est la bonne. Elles
restent lisibles, et la premiere campagne creee repart sur des bases
propres.
"""

import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('school', '0042_teacherscheduleslot_off_availability_reason'),
    ]

    operations = [
        migrations.CreateModel(
            name='AvailabilityCampaign',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('label', models.CharField(max_length=150)),
                ('opens_on', models.DateField()),
                ('closes_on', models.DateField()),
                ('status', models.CharField(choices=[('draft', 'Préparée'), ('open', 'Ouverte'), ('closed', 'Close')], default='draft', max_length=10)),
                ('instructions', models.TextField(blank=True)),
                ('academic_year', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, related_name='availability_campaigns', to='school.academicyear')),
                ('etablissement', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='availability_campaigns', to='school.etablissement')),
            ],
            options={
                'ordering': ['-opens_on', '-id'],
            },
        ),
        migrations.AddField(
            model_name='teacheravailabilityslot',
            name='campaign',
            field=models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.CASCADE, related_name='slots', to='school.availabilitycampaign'),
        ),
        migrations.CreateModel(
            name='TeacherAvailabilityResponse',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('submitted_at', models.DateTimeField(blank=True, null=True)),
                ('reminded_at', models.DateTimeField(blank=True, null=True)),
                ('reminder_count', models.PositiveSmallIntegerField(default=0)),
                ('campaign', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='responses', to='school.availabilitycampaign')),
                ('teacher', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='availability_responses', to='school.teacher')),
            ],
            options={
                'ordering': ['teacher_id'],
            },
        ),
        migrations.AddConstraint(
            model_name='availabilitycampaign',
            constraint=models.UniqueConstraint(fields=('etablissement', 'academic_year'), name='availability_campaign_unique_par_annee'),
        ),
        migrations.AddConstraint(
            model_name='teacheravailabilityresponse',
            constraint=models.UniqueConstraint(fields=('campaign', 'teacher'), name='availability_response_unique'),
        ),
    ]
