"""L'algorithme de génération d'emploi du temps, éprouvé hors base.

Le cahier des charges demande la génération automatique au module 11; elle
n'existait pas. Un établissement saisissait ses centaines de créneaux un par
un, en vérifiant de tête qu'aucun enseignant n'était attendu dans deux
classes à la fois.

Ces tests portent sur le placement lui-même — le module ne connaît ni l'ORM
ni Django, ce qui permet de l'éprouver sur des cas tordus sans monter une
base.
"""

from datetime import time

from django.test import SimpleTestCase

from apps.school.planification import (
    Besoin,
    Creneau,
    construire_la_grille,
    generer,
)


class GrilleTests(SimpleTestCase):
    def test_elle_decoupe_la_journee_en_seances(self):
        grille = construire_la_grille(
            jours=["MON"],
            debut=time(8, 0),
            fin=time(11, 0),
            duree_minutes=60,
        )

        self.assertEqual(len(grille), 3)
        self.assertEqual(grille[0], Creneau("MON", time(8, 0), time(9, 0)))
        self.assertEqual(grille[-1], Creneau("MON", time(10, 0), time(11, 0)))

    def test_une_seance_qui_deborde_n_est_pas_produite(self):
        """Mieux vaut trois heures pleines qu'une quatrième tronquée."""
        grille = construire_la_grille(
            jours=["MON"],
            debut=time(8, 0),
            fin=time(10, 30),
            duree_minutes=60,
        )

        self.assertEqual(len(grille), 2)

    def test_la_pause_meridienne_est_retiree(self):
        grille = construire_la_grille(
            jours=["MON"],
            debut=time(8, 0),
            fin=time(16, 0),
            duree_minutes=60,
            pause_debut=time(12, 0),
            pause_fin=time(13, 0),
        )

        heures = [creneau.debut for creneau in grille]
        self.assertNotIn(time(12, 0), heures)
        self.assertIn(time(11, 0), heures)
        self.assertIn(time(13, 0), heures)

    def test_un_jour_inconnu_est_ignore(self):
        grille = construire_la_grille(
            jours=["MON", "DIM"],
            debut=time(8, 0),
            fin=time(9, 0),
            duree_minutes=60,
        )

        self.assertEqual([creneau.jour for creneau in grille], ["MON"])

    def test_une_duree_nulle_ne_produit_rien(self):
        self.assertEqual(
            construire_la_grille(
                jours=["MON"], debut=time(8, 0), fin=time(9, 0), duree_minutes=0
            ),
            [],
        )


class PlacementTests(SimpleTestCase):
    def setUp(self):
        self.grille = construire_la_grille(
            jours=["MON", "TUE"],
            debut=time(8, 0),
            fin=time(12, 0),
            duree_minutes=60,
        )

    def _besoin(self, **extra):
        donnees = {
            "assignment_id": 1,
            "teacher_id": 10,
            "classroom_id": 100,
            "subject_id": 1000,
            "subject_name": "Maths",
            "seances": 1,
        }
        donnees.update(extra)
        return Besoin(**donnees)

    def test_une_seance_est_placee(self):
        resultat = generer(besoins=[self._besoin()], grille=self.grille)

        self.assertTrue(resultat.tout_place)
        self.assertEqual(len(resultat.placements), 1)

    def test_un_enseignant_n_est_jamais_a_deux_endroits(self):
        """Le cœur du problème: c'est ce qu'on vérifiait de tête."""
        besoins = [
            self._besoin(assignment_id=1, classroom_id=100, seances=4),
            self._besoin(assignment_id=2, classroom_id=200, seances=4),
        ]

        resultat = generer(besoins=besoins, grille=self.grille)

        creneaux = [placement.creneau for placement in resultat.placements]
        self.assertEqual(len(creneaux), len(set(creneaux)))

    def test_une_classe_n_a_jamais_deux_cours_en_meme_temps(self):
        besoins = [
            self._besoin(assignment_id=1, teacher_id=10, subject_id=1, seances=3),
            self._besoin(assignment_id=2, teacher_id=20, subject_id=2, seances=3),
        ]

        resultat = generer(besoins=besoins, grille=self.grille)

        creneaux = [placement.creneau for placement in resultat.placements]
        self.assertEqual(len(creneaux), len(set(creneaux)))

    def test_une_salle_n_accueille_qu_un_cours_a_la_fois(self):
        besoins = [
            self._besoin(assignment_id=1, teacher_id=10, classroom_id=100, room="Labo", seances=2),
            self._besoin(assignment_id=2, teacher_id=20, classroom_id=200, room="Labo", seances=2),
        ]

        resultat = generer(besoins=besoins, grille=self.grille)

        creneaux = [placement.creneau for placement in resultat.placements]
        self.assertEqual(len(creneaux), len(set(creneaux)))

    def test_les_creneaux_deja_pris_sont_respectes(self):
        """Une génération n'écrase pas ce qui a été posé à la main."""
        occupe = Creneau("MON", time(8, 0), time(9, 0))

        resultat = generer(
            besoins=[self._besoin()],
            grille=self.grille,
            occupes_classes={100: [occupe]},
        )

        self.assertNotEqual(resultat.placements[0].creneau, occupe)

    def test_une_indisponibilite_est_evitee_quand_c_est_possible(self):
        indispo = Creneau("MON", time(8, 0), time(9, 0))

        resultat = generer(
            besoins=[self._besoin()],
            grille=self.grille,
            disponibilites={10: [(indispo, "unavailable")]},
        )

        self.assertNotEqual(resultat.placements[0].creneau, indispo)
        self.assertEqual(resultat.placements[0].hors_disponibilite, "")

    def test_un_creneau_prefere_passe_avant_un_creneau_possible(self):
        """La campagne de disponibilités sert à arbitrer, pas à décorer."""
        prefere = Creneau("TUE", time(10, 0), time(11, 0))

        resultat = generer(
            besoins=[self._besoin()],
            grille=self.grille,
            disponibilites={10: [(prefere, "preferred")]},
        )

        self.assertEqual(resultat.placements[0].creneau, prefere)

    def test_en_dernier_recours_le_hors_disponibilite_est_signale(self):
        # Un seul créneau dans toute la grille, et l'enseignant l'a refusé.
        grille = [Creneau("MON", time(8, 0), time(9, 0))]

        resultat = generer(
            besoins=[self._besoin()],
            grille=grille,
            disponibilites={10: [(grille[0], "unavailable")]},
        )

        self.assertEqual(len(resultat.placements), 1)
        self.assertIn("indisponible", resultat.placements[0].hors_disponibilite)

    def test_le_hors_disponibilite_peut_etre_interdit(self):
        grille = [Creneau("MON", time(8, 0), time(9, 0))]

        resultat = generer(
            besoins=[self._besoin()],
            grille=grille,
            disponibilites={10: [(grille[0], "unavailable")]},
            autoriser_hors_disponibilite=False,
        )

        self.assertEqual(resultat.placements, [])
        self.assertEqual(len(resultat.echecs), 1)

    def test_une_matiere_ne_s_empile_pas_sur_une_journee(self):
        """Six heures de maths le lundi: valide, et inutilisable."""
        resultat = generer(
            besoins=[self._besoin(seances=4)],
            grille=self.grille,
            max_par_jour=2,
        )

        lundi = [p for p in resultat.placements if p.creneau.jour == "MON"]
        self.assertLessEqual(len(lundi), 2)

    def test_ce_qui_ne_rentre_pas_est_dit_plutot_que_tu(self):
        """Un planning refusé en bloc serait inutilisable."""
        grille = [Creneau("MON", time(8, 0), time(9, 0))]

        resultat = generer(besoins=[self._besoin(seances=3)], grille=grille)

        self.assertEqual(len(resultat.placements), 1)
        self.assertEqual(len(resultat.echecs), 2)
        self.assertIn("non placée", resultat.echecs[0].motif)

    def test_l_enseignant_le_plus_contraint_est_servi_en_premier(self):
        """Sinon ses rares créneaux sont pris, et il ne reste rien pour lui.

        Deux enseignants, une seule case commune le mardi. Le premier ne peut
        que le mardi; le second peut partout. Servir le second d'abord
        condamnerait le premier.
        """
        grille = construire_la_grille(
            jours=["MON", "TUE"],
            debut=time(8, 0),
            fin=time(9, 0),
            duree_minutes=60,
        )
        lundi = Creneau("MON", time(8, 0), time(9, 0))

        besoins = [
            # `souple` est en tête de liste: sans le tri, il prendrait le
            # mardi et `contraint` n'aurait plus rien.
            self._besoin(assignment_id=2, teacher_id=20, classroom_id=200, subject_id=2, subject_name="Souple"),
            self._besoin(assignment_id=1, teacher_id=10, classroom_id=100, subject_id=1, subject_name="Contraint"),
        ]

        resultat = generer(
            besoins=besoins,
            grille=grille,
            disponibilites={10: [(lundi, "unavailable")]},
            autoriser_hors_disponibilite=False,
        )

        self.assertTrue(resultat.tout_place, msg=[e.motif for e in resultat.echecs])

    def test_sans_besoin_le_resultat_est_vide_et_reussi(self):
        resultat = generer(besoins=[], grille=self.grille)

        self.assertTrue(resultat.tout_place)
        self.assertEqual(resultat.placements, [])
