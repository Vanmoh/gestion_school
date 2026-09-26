"""Le calcul du montage, eprouve sans ffmpeg.

C'est la raison d'etre du decoupage: `plan_de_montage` ne touche a aucun outil
externe, donc il s'eprouve sur une machine qui n'a ni ffmpeg ni serveur X. Ce
qui reste a verifier au premier tournage est la recette ffmpeg elle-meme -- pas
la conversion des horodatages, ni le placement des encadres, ni la survie a une
prise interrompue.
"""

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import plan_de_montage as pm  # noqa: E402


def _evenement(genre, epoch_ms, **reste):
    ligne = {"type": genre, "epoch_ms": epoch_ms, "duree_ms": 4000}
    ligne.update(reste)
    return json.dumps(ligne, ensure_ascii=False)


class LectureDuJournalTests(unittest.TestCase):
    def test_il_relit_ce_que_la_prise_a_ecrit(self):
        contenu = "\n".join(
            [
                _evenement("chapitre", 1000, texte="DIRECTEUR", role="director"),
                _evenement("sousTitre", 5000, texte="La grille se génère."),
                _evenement("fin", 9000, duree_ms=0),
            ]
        )

        evenements = pm.lire_le_journal(contenu)

        self.assertEqual(len(evenements), 3)
        self.assertEqual(evenements[1]["texte"], "La grille se génère.")

    def test_une_ligne_tronquee_n_emporte_pas_le_reste(self):
        """Une prise coupee en pleine ecriture laisse une ligne incomplete."""
        contenu = (
            _evenement("chapitre", 1000, texte="DIRECTEUR", role="director")
            + '\n{"type":"sousTitre","epoch_ms":2000,"texte":"tronq\n'
            + _evenement("fin", 3000, duree_ms=0)
        )

        evenements = pm.lire_le_journal(contenu)

        self.assertEqual(len(evenements), 2)
        self.assertEqual(evenements[-1]["type"], "fin")

    def test_une_prise_close_est_complete(self):
        evenements = pm.lire_le_journal(
            "\n".join(
                [
                    _evenement("chapitre", 1000, texte="PARENT", role="parent"),
                    _evenement("fin", 2000, duree_ms=0),
                ]
            )
        )

        self.assertTrue(pm.prise_complete(evenements))

    def test_une_prise_sans_fin_est_incomplete(self):
        evenements = pm.lire_le_journal(
            _evenement("chapitre", 1000, texte="PARENT", role="parent")
        )

        self.assertFalse(pm.prise_complete(evenements))


class ConversionDesTempsTests(unittest.TestCase):
    def test_le_temps_absolu_devient_le_temps_de_la_video(self):
        """Le journal date en absolu; la video part de zero."""
        evenements = [
            {"type": "sousTitre", "epoch_ms": 105000, "duree_ms": 4000, "texte": "A"}
        ]

        annotations = pm.convertir_en_annotations(
            evenements, t0_ms=100000, decalage_vertical=0, duree_du_rush=60
        )

        self.assertAlmostEqual(annotations[0].debut, 5.0)
        self.assertAlmostEqual(annotations[0].fin, 9.0)

    def test_une_annotation_posee_avant_la_premiere_image_se_colle_au_debut(self):
        # x11grab met un instant a ecrire: un evenement journalise pendant ce
        # temps-la aurait un debut negatif.
        evenements = [
            {"type": "sousTitre", "epoch_ms": 99800, "duree_ms": 3000, "texte": "A"}
        ]

        annotations = pm.convertir_en_annotations(
            evenements, t0_ms=100000, decalage_vertical=0, duree_du_rush=60
        )

        self.assertEqual(annotations[0].debut, 0.0)

    def test_une_annotation_posterieure_au_rush_est_ecartee(self):
        """Elle decrirait un moment que la capture n'a pas enregistre."""
        evenements = [
            {"type": "sousTitre", "epoch_ms": 200000, "duree_ms": 3000, "texte": "A"}
        ]

        annotations = pm.convertir_en_annotations(
            evenements, t0_ms=100000, decalage_vertical=0, duree_du_rush=30
        )

        self.assertEqual(annotations, [])

    def test_une_annotation_qui_depasse_la_fin_est_raccourcie(self):
        evenements = [
            {"type": "sousTitre", "epoch_ms": 128000, "duree_ms": 6000, "texte": "A"}
        ]

        annotations = pm.convertir_en_annotations(
            evenements, t0_ms=100000, decalage_vertical=0, duree_du_rush=30
        )

        self.assertAlmostEqual(annotations[0].fin, 30.0)


class PlacementDesCadresTests(unittest.TestCase):
    def test_le_cadre_descend_du_decalage_mesure(self):
        """La barre de titre GTK est recadree: la vue ne commence pas a zero."""
        evenements = [
            {
                "type": "cadre",
                "epoch_ms": 105000,
                "duree_ms": 4000,
                "cadre": [312, 206, 420, 64],
            }
        ]

        annotations = pm.convertir_en_annotations(
            evenements, t0_ms=100000, decalage_vertical=18, duree_du_rush=60
        )

        self.assertEqual(annotations[0].cadre, (312, 224, 420, 64))

    def test_un_cadre_qui_depasse_l_image_est_rogne(self):
        # Une liste plus haute que l'ecran existe: `drawbox` accepterait, mais
        # tracerait un trait collé au bord qui ne designe rien.
        evenements = [
            {
                "type": "cadre",
                "epoch_ms": 105000,
                "duree_ms": 4000,
                "cadre": [1100, 600, 400, 300],
            }
        ]

        annotations = pm.convertir_en_annotations(
            evenements, t0_ms=100000, decalage_vertical=0, duree_du_rush=60
        )

        x, y, largeur, hauteur = annotations[0].cadre
        self.assertLessEqual(x + largeur, pm.LARGEUR)
        self.assertLessEqual(y + hauteur, pm.HAUTEUR)

    def test_un_cadre_entierement_hors_champ_est_ecarte(self):
        evenements = [
            {
                "type": "cadre",
                "epoch_ms": 105000,
                "duree_ms": 4000,
                "cadre": [1279, 719, 100, 100],
            }
        ]

        annotations = pm.convertir_en_annotations(
            evenements, t0_ms=100000, decalage_vertical=0, duree_du_rush=60
        )

        self.assertIsNone(annotations[0].cadre)

    def test_le_decalage_se_lit_dans_la_geometrie(self):
        geometrie = (
            "  Width: 1280\n  Height: 683\n  Depth: 24\ndecalage_vertical=37\n"
        )

        self.assertEqual(pm.lire_le_decalage(geometrie), 37.0)

    def test_une_geometrie_sans_decalage_vaut_zero(self):
        self.assertEqual(pm.lire_le_decalage("Width: 1280\n"), 0.0)


class SousTitresTests(unittest.TestCase):
    def test_l_horodatage_suit_le_format_attendu(self):
        self.assertEqual(pm.horodatage_srt(0), "00:00:00,000")
        self.assertEqual(pm.horodatage_srt(5.25), "00:00:05,250")
        self.assertEqual(pm.horodatage_srt(3725.5), "01:02:05,500")

    def test_un_instant_negatif_est_ramene_a_zero(self):
        self.assertEqual(pm.horodatage_srt(-3), "00:00:00,000")

    def test_le_srt_numerote_et_date_chaque_ligne(self):
        annotations = [
            pm.Annotation("sousTitre", 2.0, 6.0, "La grille se génère."),
            pm.Annotation("sousTitre", 8.0, 12.0, "Publier l'ouvre aux familles."),
        ]

        srt = pm.ecrire_le_srt(annotations)

        self.assertIn("1\n00:00:02,000 --> 00:00:06,000", srt)
        self.assertIn("2\n00:00:08,000 --> 00:00:12,000", srt)
        self.assertIn("La grille se génère.", srt)

    def test_les_accents_traversent_le_srt(self):
        """Ils sont brules dans l'image: un accent perdu se voit."""
        annotations = [
            pm.Annotation("sousTitre", 1.0, 4.0, "Élèves inscrits — « T1 »")
        ]

        srt = pm.ecrire_le_srt(annotations)

        self.assertIn("Élèves inscrits — « T1 »", srt)

    def test_un_cadre_ne_devient_pas_un_sous_titre(self):
        annotations = [
            pm.Annotation("cadre", 1.0, 4.0, "texte", (10, 10, 100, 50)),
            pm.Annotation("sousTitre", 2.0, 5.0, "phrase"),
        ]

        srt = pm.ecrire_le_srt(annotations)

        self.assertEqual(srt.count("-->"), 1)


class FiltresTests(unittest.TestCase):
    def test_chaque_cadre_donne_deux_passes(self):
        """Un contour net, puis un voile: c'est ce qui se lit a l'ecran."""
        annotations = [pm.Annotation("cadre", 2.0, 6.0, "", (10, 20, 100, 50))]

        filtre = pm.filtre_des_cadres(annotations)

        self.assertEqual(filtre.count("drawbox"), 2)
        self.assertIn("t=3", filtre)
        self.assertIn("t=fill", filtre)
        self.assertIn("between(t,2.00,6.00)", filtre)

    def test_un_cadre_ecarte_ne_produit_aucun_filtre(self):
        annotations = [pm.Annotation("cadre", 2.0, 6.0, "", None)]

        self.assertEqual(pm.filtre_des_cadres(annotations), "")


class PlanificationTests(unittest.TestCase):
    def setUp(self):
        self._dossier = tempfile.TemporaryDirectory()
        self.dossier = Path(self._dossier.name)
        self.addCleanup(self._dossier.cleanup)

    def _poser_une_prise(self, rang, *, complete=True, decalage=18):
        (self.dossier / f"brut_{rang}.mkv").write_bytes(b"x" * 2048)
        lignes = [
            _evenement("chapitre", 100000, texte="TITRE", role="r"),
            _evenement("sousTitre", 105000, texte="une phrase"),
            _evenement(
                "cadre", 108000, cadre=[100, 200, 300, 40], texte="un encadré"
            ),
        ]
        if complete:
            lignes.append(_evenement("fin", 120000, duree_ms=0))
        (self.dossier / f"journal_{rang}.jsonl").write_text(
            "\n".join(lignes), encoding="utf-8"
        )
        (self.dossier / f"t0_{rang}.txt").write_text("100000", encoding="utf-8")
        (self.dossier / f"geometrie_{rang}.txt").write_text(
            f"Height: 683\ndecalage_vertical={decalage}\n", encoding="utf-8"
        )
        (self.dossier / f"duree_{rang}.txt").write_text("60.0", encoding="utf-8")

    def test_le_plan_porte_les_neuf_chapitres(self):
        plan = pm.planifier(self.dossier)

        self.assertEqual(len(plan), 9)
        self.assertEqual([c.rang for c in plan], list(range(1, 10)))

    def test_un_chapitre_sans_rush_est_marque_manquant(self):
        """Il deviendra un carton honnete, pas un trou silencieux."""
        plan = pm.planifier(self.dossier)

        self.assertTrue(all(c.manquant for c in plan))
        self.assertEqual(plan[0].motif, "aucune image capturée")

    def test_une_prise_presente_porte_ses_annotations(self):
        self._poser_une_prise(3)

        plan = pm.planifier(self.dossier)
        chapitre = plan[2]

        self.assertFalse(chapitre.manquant)
        self.assertEqual(len(chapitre.sous_titres), 1)
        self.assertEqual(len(chapitre.cadres), 1)
        self.assertEqual(chapitre.cadres[0].cadre, (100, 218, 300, 40))

    def test_une_prise_interrompue_reste_exploitable(self):
        # Mieux vaut un chapitre partiel, signale, que trente-cinq minutes de
        # runner perdues.
        self._poser_une_prise(5, complete=False)

        chapitre = pm.planifier(self.dossier)[4]

        self.assertFalse(chapitre.manquant)
        self.assertEqual(chapitre.motif, "prise interrompue")
        self.assertEqual(len(chapitre.sous_titres), 1)


class SortiesTests(unittest.TestCase):
    def test_les_chapitres_partent_en_metadonnees(self):
        bornes = [("1. SUPER ADMIN", 0.0, 75.0), ("2. PROMOTEUR", 75.0, 115.0)]

        metadonnees = pm.metadonnees_de_chapitres(bornes)

        self.assertTrue(metadonnees.startswith(";FFMETADATA1"))
        self.assertEqual(metadonnees.count("[CHAPTER]"), 2)
        self.assertIn("START=75000", metadonnees)
        self.assertIn("title=2. PROMOTEUR", metadonnees)

    def test_le_corps_de_release_repete_les_minutages(self):
        """Les chapitres du conteneur ne se voient pas dans un fichier telecharge."""
        bornes = [("1. SUPER ADMIN", 0.0, 75.0), ("3. DIRECTEUR", 125.0, 215.0)]

        corps = pm.corps_de_release(bornes, poids_mo=42.0)

        self.assertIn("`00:00` 1. SUPER ADMIN", corps)
        self.assertIn("`02:05` 3. DIRECTEUR", corps)
        self.assertIn("42 Mo", corps)

    def test_le_corps_avertit_que_les_donnees_sont_fictives(self):
        corps = pm.corps_de_release([("1. A", 0.0, 1.0)], poids_mo=1.0)

        self.assertIn("fictives", corps)


if __name__ == "__main__":
    unittest.main()
