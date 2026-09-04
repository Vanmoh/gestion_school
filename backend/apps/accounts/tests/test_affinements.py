"""Les gestes qui echappent a la grille de la matrice.

Cinq regles ne tiennent pas dans une case: valider la paie au niveau 1 puis
au niveau 2, noter la conduite, lancer un export nominatif, appeler
l'attention dans la messagerie. Elles etaient ecrites a la main dans cinq
fichiers differents, invisibles depuis la matrice. Ce qui suit verrouille
leur reunion: qu'elles disent toujours la meme chose qu'avant, qu'un
affinement n'ouvre jamais un module ferme, et que le frontend les recoive
pour masquer un bouton au lieu de le refuser au clic.
"""

from django.test import SimpleTestCase

from apps.accounts import access


class AffinementsTests(SimpleTestCase):
    def test_les_exports_sensibles_restent_a_l_administration_et_aux_finances(self):
        for role in (access.SUPER_ADMIN, access.DIRECTOR, access.ACCOUNTANT):
            with self.subTest(role=role):
                self.assertTrue(access.affinement_autorise(role, "exports_sensibles"))

        for role in (
            access.PROMOTER,
            access.CENSOR,
            access.SUPERVISOR,
            access.TEACHER,
            access.PARENT,
            access.STUDENT,
        ):
            with self.subTest(role=role):
                self.assertFalse(access.affinement_autorise(role, "exports_sensibles"))

    def test_la_double_validation_de_la_paie_reste_partagee(self):
        """Le censeur au niveau 1, le comptable au niveau 2: ni l'un ni l'autre seul."""
        self.assertTrue(access.affinement_autorise(access.CENSOR, "validation_paie_niveau_1"))
        self.assertFalse(access.affinement_autorise(access.CENSOR, "validation_paie_niveau_2"))

        self.assertTrue(access.affinement_autorise(access.ACCOUNTANT, "validation_paie_niveau_2"))
        self.assertFalse(access.affinement_autorise(access.ACCOUNTANT, "validation_paie_niveau_1"))

        self.assertFalse(access.affinement_autorise(access.DIRECTOR, "validation_paie_niveau_1"))
        self.assertFalse(access.affinement_autorise(access.DIRECTOR, "validation_paie_niveau_2"))

    def test_aucun_signataire_ne_defait_sa_propre_signature(self):
        """Annuler une validation efface la trace de qui avait signe.

        Le censeur et le comptable signent, chacun a son niveau; ni l'un ni
        l'autre ne peut revenir en arriere, sinon la double validation ne
        prouve plus rien.
        """
        for cle in ("annulation_validation_paie", "annulation_validation_depense"):
            with self.subTest(affinement=cle):
                self.assertTrue(access.affinement_autorise(access.SUPER_ADMIN, cle))
                for role in (
                    access.DIRECTOR,
                    access.CENSOR,
                    access.ACCOUNTANT,
                    access.PROMOTER,
                ):
                    self.assertFalse(access.affinement_autorise(role, cle))

    def test_la_conduite_se_note_par_la_vie_scolaire(self):
        for role in (access.SUPER_ADMIN, access.CENSOR, access.SUPERVISOR):
            with self.subTest(role=role):
                self.assertTrue(access.affinement_autorise(role, "saisie_conduite"))

        for role in (access.DIRECTOR, access.TEACHER, access.ACCOUNTANT, access.PARENT):
            with self.subTest(role=role):
                self.assertFalse(access.affinement_autorise(role, "saisie_conduite"))

    def test_l_appel_d_attention_reste_au_personnel(self):
        """La famille garde le message ordinaire, qui attend qu'on le lise."""
        for role in (
            access.SUPER_ADMIN,
            access.PROMOTER,
            access.DIRECTOR,
            access.CENSOR,
            access.ACCOUNTANT,
            access.SUPERVISOR,
            access.TEACHER,
        ):
            with self.subTest(role=role):
                self.assertTrue(access.affinement_autorise(role, "appel_attention"))

        for role in (access.PARENT, access.STUDENT):
            with self.subTest(role=role):
                self.assertFalse(access.affinement_autorise(role, "appel_attention"))

    def test_un_affinement_n_ouvre_pas_un_module_ferme(self):
        """La regle du module reste la premiere porte.

        C'est ce qui empeche cette table de devenir une seconde matrice
        parallele: y inscrire un role ne lui donne rien s'il n'a pas deja le
        module.
        """
        for cle, regle in access.AFFINEMENTS.items():
            for role in regle["roles"]:
                with self.subTest(affinement=cle, role=role):
                    self.assertTrue(
                        access.can_read(role, regle["module"]),
                        f"{role} figure dans {cle} sans lire le module {regle['module']}",
                    )

    def test_le_payload_du_role_porte_ses_capacites(self):
        """Le frontend en a besoin avant d'afficher le bouton, pas apres."""
        comptable = access.role_payload(access.ACCOUNTANT)
        self.assertTrue(comptable["capabilities"]["exports_sensibles"])
        self.assertTrue(comptable["capabilities"]["validation_paie_niveau_2"])
        self.assertFalse(comptable["capabilities"]["saisie_conduite"])

        enseignant = access.role_payload(access.TEACHER)
        self.assertEqual(
            set(enseignant["capabilities"]),
            set(access.AFFINEMENTS),
            "toutes les capacites sont servies, y compris celles a False: le "
            "client doit distinguer « refuse » de « inconnu de cette version »",
        )
        self.assertFalse(enseignant["capabilities"]["exports_sensibles"])
        self.assertFalse(enseignant["capabilities"]["validation_paie_niveau_1"])
        self.assertFalse(enseignant["capabilities"]["saisie_conduite"])
