"""Le moteur de passation: simuler, executer, archiver.

C'est l'operation la plus irreversible du produit -- elle reaffecte les
eleves, ecrit leur historique de scolarite et archive les sortants -- et
elle n'avait aucun test. Un ecart ici ne se voit qu'a la rentree, quand les
classes sont deja constituees.
"""

from datetime import date
from decimal import Decimal

from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    Grade,
    PromotionDecision,
    PromotionRun,
    Student,
    StudentAcademicHistory,
    Subject,
)


class PromotionApiTests(APITestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(name="Lycee Central")
        self.autre_etablissement = Etablissement.objects.create(name="Lycee Voisin")

        self.directeur = User.objects.create_user(
            username="directeur_promo",
            password="directeur12345",
            role=UserRole.DIRECTOR,
            first_name="Le",
            last_name="Directeur",
            etablissement=self.etablissement,
        )
        self.censeur = User.objects.create_user(
            username="censeur_promo",
            password="censeur12345",
            role=UserRole.CENSOR,
            etablissement=self.etablissement,
        )

        self.annee_source = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 6, 30),
            is_active=True,
        )
        self.annee_cible = AcademicYear.objects.create(
            name="2026-2027",
            start_date=date(2026, 9, 1),
            end_date=date(2027, 6, 30),
            is_active=False,
        )

        self.sixieme = ClassRoom.objects.create(
            name="6A",
            academic_year=self.annee_source,
            etablissement=self.etablissement,
        )
        self.cinquieme = ClassRoom.objects.create(
            name="5A",
            academic_year=self.annee_cible,
            etablissement=self.etablissement,
        )

        # Coefficients differents: une moyenne ponderee ne se confond pas
        # avec une moyenne simple, et c'est la ponderation qui decide du
        # passage.
        self.maths = Subject.objects.create(name="Maths", coefficient=Decimal("4"))
        self.sport = Subject.objects.create(name="Sport", coefficient=Decimal("1"))

    # ----- utilitaires -------------------------------------------------

    def _eleve(self, matricule, nom, classroom=None, conduite="18"):
        user = User.objects.create_user(
            username=f"eleve_{matricule}",
            password="eleve12345",
            role=UserRole.STUDENT,
            first_name=nom,
            last_name="Test",
            etablissement=self.etablissement,
        )
        return Student.objects.create(
            user=user,
            matricule=matricule,
            classroom=classroom or self.sixieme,
            etablissement=self.etablissement,
            conduite=Decimal(conduite),
        )

    def _note(self, eleve, matiere, valeur, classroom=None):
        return Grade.objects.create(
            student=eleve,
            subject=matiere,
            classroom=classroom or self.sixieme,
            academic_year=self.annee_source,
            term="T1",
            value=Decimal(str(valeur)),
        )

    def _charge(self, **extra):
        charge = {
            "source_academic_year": self.annee_source.id,
            "target_academic_year": self.annee_cible.id,
            "source_classrooms": [self.sixieme.id],
            "classroom_mapping": [
                {
                    "source_classroom": self.sixieme.id,
                    "target_classroom": self.cinquieme.id,
                }
            ],
        }
        charge.update(extra)
        return charge

    def _decision(self, run_id, eleve):
        return PromotionDecision.objects.get(run_id=run_id, student=eleve)

    # ----- simulation --------------------------------------------------

    def test_simulate_decides_without_touching_a_single_student(self):
        """Une simulation qui deplacerait un eleve ne serait plus une simulation.

        C'est la garantie qui rend l'ecran utilisable: on regarde le
        resultat avant de s'engager.
        """
        eleve = self._eleve("M001", "Awa")
        self._note(eleve, self.maths, 15)

        self.client.force_authenticate(self.directeur)
        reponse = self.client.post(
            "/api/promotion-runs/simulate/", self._charge(), format="json"
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertEqual(reponse.data["status"], "simulated")
        self.assertEqual(reponse.data["total_students"], 1)
        self.assertEqual(reponse.data["promoted_count"], 1)

        eleve.refresh_from_db()
        self.assertEqual(eleve.classroom_id, self.sixieme.id)
        self.assertFalse(eleve.is_archived)
        self.assertFalse(StudentAcademicHistory.objects.filter(student=eleve).exists())

        # La decision est bien enregistree: c'est ce que l'ecran affiche.
        decision = self._decision(reponse.data["id"], eleve)
        self.assertEqual(decision.decision, "promoted")
        self.assertEqual(decision.target_classroom_id, self.cinquieme.id)

    # ----- execution ---------------------------------------------------

    def test_execute_promotes_repeats_and_writes_history(self):
        promu = self._eleve("M001", "Awa")
        self._note(promu, self.maths, 15)

        redoublant = self._eleve("M002", "Bala")
        self._note(redoublant, self.maths, 6)

        self.client.force_authenticate(self.directeur)
        reponse = self.client.post(
            "/api/promotion-runs/execute/", self._charge(), format="json"
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertEqual(reponse.data["status"], "executed")
        self.assertEqual(reponse.data["promoted_count"], 1)
        self.assertEqual(reponse.data["repeated_count"], 1)

        promu.refresh_from_db()
        self.assertEqual(promu.classroom_id, self.cinquieme.id)
        self.assertFalse(promu.is_archived)

        redoublant.refresh_from_db()
        self.assertEqual(redoublant.classroom_id, self.sixieme.id)
        self.assertFalse(redoublant.is_archived)

        # L'historique fige l'annee ecoulee pour les deux: le redoublant a
        # bien fait cette annee-la, meme s'il la refait.
        for eleve in (promu, redoublant):
            historique = StudentAcademicHistory.objects.get(
                student=eleve,
                academic_year=self.annee_source,
                classroom=self.sixieme,
            )
            self.assertGreater(historique.rank, 0)

        motif = self._decision(reponse.data["id"], redoublant).reason
        self.assertEqual(motif, "Moyenne insuffisante.")

    def test_execute_archives_students_of_a_terminal_class(self):
        """Sans classe cible, l'eleve sort de l'ecole plutot que de rester.

        C'est le cas de la classe terminale: la laisser en place aurait
        garde des sortants dans les effectifs de la rentree suivante.
        """
        sortant = self._eleve("M001", "Awa")
        self._note(sortant, self.maths, 16)

        self.client.force_authenticate(self.directeur)
        reponse = self.client.post(
            "/api/promotion-runs/execute/",
            self._charge(
                classroom_mapping=[
                    {"source_classroom": self.sixieme.id, "target_classroom": None}
                ]
            ),
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertEqual(reponse.data["archived_count"], 1)

        sortant.refresh_from_db()
        self.assertIsNone(sortant.classroom_id)
        self.assertTrue(sortant.is_archived)

        decision = self._decision(reponse.data["id"], sortant)
        self.assertEqual(decision.decision, "archived")
        self.assertEqual(
            decision.reason,
            "Classe terminale sans classe cible: archivage automatique.",
        )

    def test_an_archived_student_is_left_out_of_the_run(self):
        actif = self._eleve("M001", "Awa")
        self._note(actif, self.maths, 15)
        sorti = self._eleve("M002", "Bala")
        sorti.is_archived = True
        sorti.save(update_fields=["is_archived"])

        self.client.force_authenticate(self.directeur)
        reponse = self.client.post(
            "/api/promotion-runs/execute/", self._charge(), format="json"
        )

        self.assertEqual(reponse.data["total_students"], 1)
        self.assertFalse(
            PromotionDecision.objects.filter(
                run_id=reponse.data["id"], student=sorti
            ).exists()
        )

    # ----- calcul ------------------------------------------------------

    def test_average_is_weighted_by_subject_coefficient(self):
        """La moyenne simple et la moyenne ponderee ne decident pas pareil.

        18 en sport (coef 1) et 8 en maths (coef 4) font 13 en simple et
        10 en ponderee: sur un seuil a 10, un eleve passe dans un cas et
        pas dans l'autre.
        """
        eleve = self._eleve("M001", "Awa")
        self._note(eleve, self.maths, 8)
        self._note(eleve, self.sport, 18)

        self.client.force_authenticate(self.directeur)
        reponse = self.client.post(
            "/api/promotion-runs/simulate/", self._charge(), format="json"
        )

        decision = self._decision(reponse.data["id"], eleve)
        self.assertEqual(decision.average, Decimal("10.00"))

    def test_average_falls_back_to_the_recorded_history(self):
        """Une annee reprise d'un autre logiciel n'a pas de notes en base.

        Sans ce repli, ces eleves auraient tous ete comptes a zero et
        renvoyes en redoublement.
        """
        eleve = self._eleve("M001", "Awa")
        StudentAcademicHistory.objects.create(
            student=eleve,
            academic_year=self.annee_source,
            classroom=self.sixieme,
            average=Decimal("14.50"),
            rank=1,
        )

        self.client.force_authenticate(self.directeur)
        reponse = self.client.post(
            "/api/promotion-runs/simulate/", self._charge(), format="json"
        )

        decision = self._decision(reponse.data["id"], eleve)
        self.assertEqual(decision.average, Decimal("14.50"))
        self.assertEqual(decision.decision, "promoted")

    def test_rank_follows_the_average_inside_the_class(self):
        premier = self._eleve("M001", "Awa")
        self._note(premier, self.maths, 18)
        second = self._eleve("M002", "Bala")
        self._note(second, self.maths, 15)
        troisieme = self._eleve("M003", "Cheick")
        self._note(troisieme, self.maths, 11)

        self.client.force_authenticate(self.directeur)
        reponse = self.client.post(
            "/api/promotion-runs/simulate/", self._charge(), format="json"
        )

        run_id = reponse.data["id"]
        self.assertEqual(self._decision(run_id, premier).rank, 1)
        self.assertEqual(self._decision(run_id, second).rank, 2)
        self.assertEqual(self._decision(run_id, troisieme).rank, 3)

    def test_conduite_below_threshold_blocks_an_otherwise_good_average(self):
        eleve = self._eleve("M001", "Awa", conduite="6")
        self._note(eleve, self.maths, 17)

        self.client.force_authenticate(self.directeur)
        reponse = self.client.post(
            "/api/promotion-runs/simulate/",
            self._charge(min_conduite="10"),
            format="json",
        )

        decision = self._decision(reponse.data["id"], eleve)
        self.assertEqual(decision.decision, "repeated")
        self.assertEqual(decision.reason, "Conduite insuffisante.")

    def test_mapping_a_class_onto_itself_is_refused_upstream(self):
        """Viser sa propre classe est rejete avant meme d'etre une decision.

        Une classe source appartient a l'annee source, et le mapping
        n'accepte que des classes de l'annee cible: le cas est ecarte a la
        validation. Le garde-fou « classe cible identique » qui suit, dans
        le calcul des decisions, ne peut donc jamais se declencher -- il est
        conserve tel quel ici, ce test documente ou la question se tranche
        reellement.
        """
        eleve = self._eleve("M001", "Awa")
        self._note(eleve, self.maths, 16)

        self.client.force_authenticate(self.directeur)
        reponse = self.client.post(
            "/api/promotion-runs/simulate/",
            self._charge(
                classroom_mapping=[
                    {
                        "source_classroom": self.sixieme.id,
                        "target_classroom": self.sixieme.id,
                    }
                ]
            ),
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("classroom_mapping", reponse.data)
        self.assertFalse(PromotionDecision.objects.filter(student=eleve).exists())

    def test_without_mapping_students_fall_back_to_an_arbitrary_class(self):
        """Comportement actuel du mapping automatique, a trancher.

        Sans correspondance explicite, le moteur cherche une classe cible
        de meme nom, puis se rabat sur la premiere classe de la liste par
        ordre alphabetique. Une terminale sans equivalent envoie donc ses
        eleves dans la premiere classe venue -- une sixieme, le cas
        echeant. Ce test fige le comportement observe pour qu'un
        changement de regle soit un choix, pas une surprise.
        """
        eleve = self._eleve("M001", "Awa")
        self._note(eleve, self.maths, 16)
        # Deux cibles possibles, aucune ne porte le nom de la source.
        premiere_alphabetiquement = ClassRoom.objects.create(
            name="1ereA",
            academic_year=self.annee_cible,
            etablissement=self.etablissement,
        )

        self.client.force_authenticate(self.directeur)
        reponse = self.client.post(
            "/api/promotion-runs/simulate/",
            self._charge(classroom_mapping=[]),
            format="json",
        )

        decision = self._decision(reponse.data["id"], eleve)
        self.assertEqual(decision.decision, "promoted")
        self.assertEqual(decision.target_classroom_id, premiere_alphabetiquement.id)

    # ----- garde-fous --------------------------------------------------

    def test_the_target_year_is_required_and_must_differ_from_the_source(self):
        self._eleve("M001", "Awa")
        self.client.force_authenticate(self.directeur)

        sans_cible = self.client.post(
            "/api/promotion-runs/execute/",
            self._charge(target_academic_year=None),
            format="json",
        )
        self.assertEqual(sans_cible.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("target_academic_year", sans_cible.data)

        meme_annee = self.client.post(
            "/api/promotion-runs/execute/",
            self._charge(target_academic_year=self.annee_source.id),
            format="json",
        )
        self.assertEqual(meme_annee.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("target_academic_year", meme_annee.data)

    def test_thresholds_outside_zero_twenty_are_refused(self):
        self._eleve("M001", "Awa")
        self.client.force_authenticate(self.directeur)

        for champ, valeur in (("min_average", "21"), ("min_conduite", "-1")):
            reponse = self.client.post(
                "/api/promotion-runs/execute/",
                self._charge(**{champ: valeur}),
                format="json",
            )
            self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
            self.assertIn(champ, reponse.data)

    def test_a_target_class_of_another_school_is_refused(self):
        """La passation ne doit pas pouvoir deverser des eleves ailleurs."""
        self._eleve("M001", "Awa")
        classe_voisine = ClassRoom.objects.create(
            name="5A",
            academic_year=self.annee_cible,
            etablissement=self.autre_etablissement,
        )

        self.client.force_authenticate(self.directeur)
        reponse = self.client.post(
            "/api/promotion-runs/execute/",
            self._charge(
                classroom_mapping=[
                    {
                        "source_classroom": self.sixieme.id,
                        "target_classroom": classe_voisine.id,
                    }
                ]
            ),
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("classroom_mapping", reponse.data)

    def test_a_source_class_of_another_school_is_refused(self):
        classe_voisine = ClassRoom.objects.create(
            name="6B",
            academic_year=self.annee_source,
            etablissement=self.autre_etablissement,
        )

        self.client.force_authenticate(self.directeur)
        reponse = self.client.post(
            "/api/promotion-runs/execute/",
            self._charge(source_classrooms=[self.sixieme.id, classe_voisine.id]),
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("source_classrooms", reponse.data)

    def test_a_run_without_any_source_class_is_refused(self):
        vide = AcademicYear.objects.create(
            name="2027-2028",
            start_date=date(2027, 9, 1),
            end_date=date(2028, 6, 30),
        )

        self.client.force_authenticate(self.directeur)
        reponse = self.client.post(
            "/api/promotion-runs/execute/",
            self._charge(source_academic_year=vide.id, source_classrooms=[]),
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("source_classrooms", reponse.data)

    def test_nothing_is_written_when_the_run_is_refused(self):
        """Un refus ne doit rien laisser derriere lui.

        Les decisions sont ecrites avant l'application des changements: un
        echec a mi-parcours laisserait un historique de passation qui n'a
        jamais eu lieu.
        """
        eleve = self._eleve("M001", "Awa")
        self._note(eleve, self.maths, 15)

        self.client.force_authenticate(self.directeur)
        self.client.post(
            "/api/promotion-runs/execute/",
            self._charge(min_average="25"),
            format="json",
        )

        self.assertFalse(PromotionRun.objects.exists())
        self.assertFalse(PromotionDecision.objects.exists())
        eleve.refresh_from_db()
        self.assertEqual(eleve.classroom_id, self.sixieme.id)

    # ----- droits et perimetre ----------------------------------------

    def test_a_censor_may_read_the_runs_but_not_start_one(self):
        """La matrice donne « L » au censeur sur la passation.

        Il consulte ce que la direction a decide; declencher une passation
        n'est pas de son ressort.
        """
        self._eleve("M001", "Awa")

        self.client.force_authenticate(self.censeur)
        refus = self.client.post(
            "/api/promotion-runs/simulate/", self._charge(), format="json"
        )
        self.assertEqual(refus.status_code, status.HTTP_403_FORBIDDEN)

        lecture = self.client.get("/api/promotion-runs/")
        self.assertEqual(lecture.status_code, status.HTTP_200_OK)

    def test_a_teacher_has_no_access_at_all(self):
        enseignant = User.objects.create_user(
            username="enseignant_promo",
            password="enseignant12345",
            role=UserRole.TEACHER,
            etablissement=self.etablissement,
        )

        self.client.force_authenticate(enseignant)
        self.assertEqual(
            self.client.get("/api/promotion-runs/").status_code,
            status.HTTP_403_FORBIDDEN,
        )

    def test_a_run_is_only_visible_inside_its_own_school(self):
        eleve = self._eleve("M001", "Awa")
        self._note(eleve, self.maths, 15)

        self.client.force_authenticate(self.directeur)
        self.client.post("/api/promotion-runs/execute/", self._charge(), format="json")

        directeur_voisin = User.objects.create_user(
            username="directeur_voisin",
            password="directeur12345",
            role=UserRole.DIRECTOR,
            etablissement=self.autre_etablissement,
        )
        self.client.force_authenticate(directeur_voisin)
        reponse = self.client.get("/api/promotion-runs/")

        resultats = reponse.data
        if isinstance(resultats, dict) and "results" in resultats:
            resultats = resultats["results"]
        self.assertEqual(resultats, [])
