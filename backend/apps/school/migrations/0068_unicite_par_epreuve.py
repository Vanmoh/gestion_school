"""Une note par epreuve et par eleve, au lieu d'une par matiere et trimestre.

L'ancienne contrainte portait sur (session, eleve, matiere). Elle interdisait
donc le rattrapage, qui est par definition une seconde epreuve de la meme
matiere dans le meme trimestre -- et le module lui donnait raison, faute de
savoir distinguer deux epreuves.

Les notes qu'aucune epreuve ne porte gardent l'ancienne regle: rien ne les
distingue entre elles, et deux notes de la meme matiere pour le meme
trimestre y resteraient indiscernables. D'ou deux contraintes
conditionnelles plutot qu'une: les NULL ne collisionnent pas, et la
contrainte par epreuve ne protegerait pas ces lignes-la.
"""


from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('school', '0067_l_epreuve_porte_la_note'),
    ]

    operations = [
        migrations.RemoveConstraint(
            model_name='examresult',
            name='uniq_exam_result_session_student_subject',
        ),
        migrations.AddConstraint(
            model_name='examresult',
            constraint=models.UniqueConstraint(condition=models.Q(('planning__isnull', False)), fields=('planning', 'student'), name='uniq_exam_result_planning_student'),
        ),
        migrations.AddConstraint(
            model_name='examresult',
            constraint=models.UniqueConstraint(condition=models.Q(('planning__isnull', True)), fields=('session', 'student', 'subject'), name='uniq_exam_result_sans_epreuve'),
        ),
    ]
