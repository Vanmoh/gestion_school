"""La collecte des disponibilites enseignantes, avant que le planning existe.

Le module etait inutilisable au-dela du premier repondant: l'unicite portait
sur (etablissement, jour, debut, fin) sans l'enseignant, si bien que le
premier a declarer « lundi 08:00-10:00 » en devenait proprietaire exclusif
pour toute son ecole. Ces tests tiennent la regle inverse -- une
disponibilite se partage -- et la boucle qui manquait: ce qui est declare
sert desormais a construire l'emploi du temps.
"""

from datetime import date, time, timedelta
from decimal import Decimal

from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    AvailabilityCampaign,
    AvailabilityKind,
    ClassRoom,
    Etablissement,
    Notification,
    Subject,
    Teacher,
    TeacherAssignment,
    TeacherAvailabilityResponse,
    TeacherAvailabilitySlot,
)


class _CollecteMixin:
    @classmethod
    def _decor(cls, nom="Etab Dispo"):
        cls.etablissement = Etablissement.objects.create(name=nom)
        cls.annee = AcademicYear.objects.create(
            name="2025-2026",
            start_date=date(2025, 9, 1),
            end_date=date(2026, 7, 31),
            is_active=True,
        )
        cls.classe = ClassRoom.objects.create(
            name="6A", academic_year=cls.annee, etablissement=cls.etablissement
        )
        cls.maths = Subject.objects.create(
            name="Mathematiques", code="MAT", coefficient=1, classroom=cls.classe
        )
        cls.direction = User.objects.create_user(
            username=f"dir_{nom.lower().replace(' ', '_')}",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=cls.etablissement,
        )

    @classmethod
    def _enseignant(cls, username, etablissement=None):
        etab = etablissement or cls.etablissement
        user = User.objects.create_user(
            username=username,
            password="Pass1234!",
            role=UserRole.TEACHER,
            etablissement=etab,
        )
        return Teacher.objects.create(
            user=user,
            employee_code=username.upper()[:20],
            hire_date=date(2025, 9, 1),
            hourly_rate=Decimal("1000.00"),
            etablissement=etab,
        )

    def _declarer(self, enseignant, debut="08:00", fin="10:00", jour="MON", **extra):
        charge = {
            "teacher": enseignant.id,
            "day_of_week": jour,
            "start_time": debut,
            "end_time": fin,
        }
        charge.update(extra)
        return self.client.post(
            "/api/teacher-availability-slots/",
            charge,
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )


class DisponibilitePartageeTests(_CollecteMixin, APITestCase):
    """Le bug qui rendait le module inutilisable au-dela du premier repondant."""

    @classmethod
    def setUpTestData(cls):
        cls._decor()
        cls.premier = cls._enseignant("prof_un")
        cls.second = cls._enseignant("prof_deux")

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.direction)

    def test_deux_enseignants_declarent_le_meme_creneau(self):
        """Dix enseignants sont disponibles le lundi a huit heures."""
        premier = self._declarer(self.premier)
        second = self._declarer(self.second)

        self.assertEqual(premier.status_code, status.HTTP_201_CREATED, premier.data)
        self.assertEqual(second.status_code, status.HTTP_201_CREATED, second.data)

    def test_dix_enseignants_sur_le_meme_creneau(self):
        for index in range(10):
            enseignant = self._enseignant(f"prof_masse_{index}")
            reponse = self._declarer(enseignant)
            self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)

        self.assertEqual(
            TeacherAvailabilitySlot.objects.filter(
                day_of_week="MON", start_time=time(8, 0)
            ).count(),
            10,
        )

    def test_un_enseignant_ne_se_declare_pas_deux_fois_sur_le_meme_creneau(self):
        self._declarer(self.premier)

        doublon = self._declarer(self.premier)

        self.assertEqual(doublon.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("déjà déclaré", str(doublon.data).lower().replace("dejà", "déjà"))

    def test_un_enseignant_ne_chevauche_pas_ses_propres_creneaux(self):
        self._declarer(self.premier, debut="08:00", fin="10:00")

        chevauchant = self._declarer(self.premier, debut="09:00", fin="11:00")

        self.assertEqual(chevauchant.status_code, status.HTTP_400_BAD_REQUEST)

    def test_le_chevauchement_d_un_collegue_ne_gene_pas(self):
        self._declarer(self.premier, debut="08:00", fin="10:00")

        voisin = self._declarer(self.second, debut="09:00", fin="11:00")

        self.assertEqual(voisin.status_code, status.HTTP_201_CREATED, voisin.data)

    def test_la_fin_avant_le_debut_reste_refusee(self):
        reponse = self._declarer(self.premier, debut="10:00", fin="08:00")

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)


class TroisEtatsTests(_CollecteMixin, APITestCase):
    """Preferee, possible, indisponible: la nuance qu'une collecte recueille."""

    @classmethod
    def setUpTestData(cls):
        cls._decor(nom="Etab Etats")
        cls.enseignant = cls._enseignant("prof_etats")

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.direction)

    def test_une_declaration_sans_precision_vaut_possible(self):
        reponse = self._declarer(self.enseignant)

        self.assertEqual(reponse.data["kind"], AvailabilityKind.POSSIBLE)

    def test_les_trois_etats_sont_acceptes(self):
        heures = {"preferred": "08:00", "possible": "10:00", "unavailable": "14:00"}
        for genre, debut in heures.items():
            with self.subTest(genre=genre):
                fin = f"{int(debut[:2]) + 1:02d}:00"
                reponse = self._declarer(
                    self.enseignant, debut=debut, fin=fin, kind=genre
                )
                self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)
                self.assertEqual(reponse.data["kind"], genre)

    def test_l_indisponibilite_porte_sa_raison(self):
        reponse = self._declarer(
            self.enseignant,
            kind=AvailabilityKind.UNAVAILABLE,
            note="Cours dans l'autre établissement",
        )

        self.assertEqual(reponse.data["note"], "Cours dans l'autre établissement")
        self.assertEqual(reponse.data["kind_label"], "Indisponible")

    def test_le_filtre_par_etat_isole_les_indisponibilites(self):
        self._declarer(self.enseignant, debut="08:00", fin="10:00")
        self._declarer(
            self.enseignant, debut="14:00", fin="16:00", kind=AvailabilityKind.UNAVAILABLE
        )

        lignes = self.client.get(
            "/api/teacher-availability-slots/",
            {"kind": AvailabilityKind.UNAVAILABLE},
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        ).data["results"]

        self.assertEqual(len(lignes), 1)
        self.assertEqual(lignes[0]["start_time"], "14:00:00")


class PourLePlanningTests(_CollecteMixin, APITestCase):
    """Ce qui est declare sert enfin a placer les cours."""

    @classmethod
    def setUpTestData(cls):
        cls._decor(nom="Etab Planning")
        cls.volontaire = cls._enseignant("prof_volontaire")
        cls.possible = cls._enseignant("prof_possible")
        cls.refusant = cls._enseignant("prof_refusant")
        cls.silencieux = cls._enseignant("prof_silencieux")

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.direction)
        for enseignant, genre in (
            (self.volontaire, AvailabilityKind.PREFERRED),
            (self.possible, AvailabilityKind.POSSIBLE),
            (self.refusant, AvailabilityKind.UNAVAILABLE),
        ):
            TeacherAvailabilitySlot.objects.create(
                teacher=enseignant,
                etablissement=self.etablissement,
                day_of_week="MON",
                start_time=time(8, 0),
                end_time=time(10, 0),
                kind=genre,
            )

    def _pour_le_planning(self, **params):
        charge = {"day": "MON", "start": "08:00", "end": "10:00"}
        charge.update(params)
        return self.client.get(
            "/api/teacher-availability-slots/for-planning/",
            charge,
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

    def test_les_enseignants_sont_classes_par_disponibilite(self):
        data = self._pour_le_planning().data

        self.assertEqual([l["teacher"] for l in data["preferred"]], [self.volontaire.id])
        self.assertEqual([l["teacher"] for l in data["possible"]], [self.possible.id])
        self.assertEqual([l["teacher"] for l in data["unavailable"]], [self.refusant.id])

    def test_celui_qui_n_a_rien_dit_a_son_propre_groupe(self):
        """Ni disponible ni indisponible: c'est une information a part entiere."""
        data = self._pour_le_planning().data

        self.assertEqual([l["teacher"] for l in data["undeclared"]], [self.silencieux.id])

    def test_une_declaration_trop_courte_ne_couvre_pas_le_cours(self):
        """Une heure declaree ne couvre pas un cours de deux heures."""
        data = self._pour_le_planning(start="08:00", end="12:00").data

        identifiants = [l["teacher"] for l in data["undeclared"]]
        self.assertIn(self.volontaire.id, identifiants)
        self.assertEqual(data["preferred"], [])

    def test_un_jour_illisible_est_refuse(self):
        self.assertEqual(
            self._pour_le_planning(day="LUNDI").status_code,
            status.HTTP_400_BAD_REQUEST,
        )

    def test_une_heure_illisible_est_refusee(self):
        self.assertEqual(
            self._pour_le_planning(start="huit heures").status_code,
            status.HTTP_400_BAD_REQUEST,
        )


class PlacementHorsDisponibiliteTests(_CollecteMixin, APITestCase):
    """Placer un cours hors declaration reste possible, mais se justifie."""

    @classmethod
    def setUpTestData(cls):
        cls._decor(nom="Etab Placement")
        cls.enseignant = cls._enseignant("prof_place")
        cls.affectation = TeacherAssignment.objects.create(
            teacher=cls.enseignant, subject=cls.maths, classroom=cls.classe
        )
        cls.muet = cls._enseignant("prof_muet")
        cls.affectation_muet = TeacherAssignment.objects.create(
            teacher=cls.muet, subject=cls.maths, classroom=cls.classe
        )

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.direction)
        TeacherAvailabilitySlot.objects.create(
            teacher=self.enseignant,
            etablissement=self.etablissement,
            day_of_week="MON",
            start_time=time(8, 0),
            end_time=time(10, 0),
            kind=AvailabilityKind.POSSIBLE,
        )

    def _placer(self, affectation, debut="08:00", fin="10:00", jour="MON", **extra):
        charge = {
            "assignment": affectation.id,
            "day_of_week": jour,
            "start_time": debut,
            "end_time": fin,
        }
        charge.update(extra)
        return self.client.post(
            "/api/teacher-schedule-slots/",
            charge,
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

    def test_un_cours_sur_une_disponibilite_declaree_passe(self):
        reponse = self._placer(self.affectation)

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)

    def test_un_cours_hors_declaration_exige_un_motif(self):
        reponse = self._placer(self.affectation, debut="14:00", fin="16:00")

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("off_availability_reason", reponse.data)

    def test_le_motif_donne_autorise_le_placement(self):
        reponse = self._placer(
            self.affectation,
            debut="14:00",
            fin="16:00",
            off_availability_reason="Seul professeur de la matière",
        )

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)
        self.assertEqual(
            reponse.data["off_availability_reason"], "Seul professeur de la matière"
        )

    def test_une_indisponibilite_declaree_est_nommee_dans_le_refus(self):
        TeacherAvailabilitySlot.objects.create(
            teacher=self.enseignant,
            etablissement=self.etablissement,
            day_of_week="TUE",
            start_time=time(8, 0),
            end_time=time(12, 0),
            kind=AvailabilityKind.UNAVAILABLE,
            note="Autre établissement",
        )

        reponse = self._placer(self.affectation, jour="TUE", debut="08:00", fin="10:00")

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("indisponible", str(reponse.data).lower())
        self.assertIn("Autre établissement", str(reponse.data))

    def test_un_enseignant_qui_n_a_rien_declare_ne_bloque_pas_le_planning(self):
        """Sinon aucune ecole ne pourrait saisir son planning avant la collecte."""
        reponse = self._placer(self.affectation_muet, debut="14:00", fin="16:00")

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)

    def test_un_cours_deborde_de_la_plage_declaree(self):
        """Declarer 08:00-10:00 ne vaut pas accord pour 08:00-12:00."""
        reponse = self._placer(self.affectation, debut="08:00", fin="12:00")

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)


class CampagneTests(_CollecteMixin, APITestCase):
    """La collecte a desormais un debut, une fin, et un compte de repondants."""

    @classmethod
    def setUpTestData(cls):
        cls._decor(nom="Etab Campagne")
        cls.repondant = cls._enseignant("prof_repondant")
        cls.retardataire = cls._enseignant("prof_retardataire")

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.direction)
        aujourd_hui = timezone.localdate()
        self.campagne = AvailabilityCampaign.objects.create(
            etablissement=self.etablissement,
            academic_year=self.annee,
            label="Rentrée 2025-2026",
            opens_on=aujourd_hui - timedelta(days=3),
            closes_on=aujourd_hui + timedelta(days=10),
            status=AvailabilityCampaign.Status.OPEN,
        )

    def test_la_campagne_ouverte_se_reconnait(self):
        reponse = self.client.get(
            f"/api/availability-campaigns/{self.campagne.id}/",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertTrue(reponse.data["is_open"])
        self.assertEqual(reponse.data["teachers_total"], 2)
        self.assertEqual(reponse.data["teachers_answered"], 0)

    def test_une_campagne_close_n_est_pas_ouverte(self):
        self.campagne.status = AvailabilityCampaign.Status.CLOSED
        self.campagne.save(update_fields=["status"])

        reponse = self.client.get(
            f"/api/availability-campaigns/{self.campagne.id}/",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertFalse(reponse.data["is_open"])

    def test_la_declaration_se_rattache_a_la_campagne_en_cours(self):
        reponse = self._declarer(self.repondant)

        self.assertEqual(reponse.data["campaign"], self.campagne.id)

    def test_l_enseignant_rend_ses_disponibilites(self):
        self.client.force_authenticate(self.repondant.user)
        self._declarer(self.repondant)

        reponse = self.client.post(
            f"/api/availability-campaigns/{self.campagne.id}/submit/",
            {},
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_200_OK, reponse.data)
        self.assertEqual(reponse.data["slots_declared"], 1)
        self.assertTrue(
            TeacherAvailabilityResponse.objects.get(
                campaign=self.campagne, teacher=self.repondant
            ).est_rendue
        )

    def test_le_suivi_separe_les_repondants_des_manquants(self):
        TeacherAvailabilityResponse.objects.create(
            campaign=self.campagne,
            teacher=self.repondant,
            submitted_at=timezone.now(),
        )

        data = self.client.get(
            f"/api/availability-campaigns/{self.campagne.id}/responses/",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        ).data

        self.assertEqual(data["teachers_total"], 2)
        self.assertEqual(data["teachers_answered"], 1)
        self.assertEqual(data["teachers_missing"], 1)
        # Les manquants d'abord: c'est la liste qui sert a relancer.
        self.assertFalse(data["results"][0]["is_submitted"])

    def test_la_relance_ne_touche_que_les_manquants(self):
        TeacherAvailabilityResponse.objects.create(
            campaign=self.campagne,
            teacher=self.repondant,
            submitted_at=timezone.now(),
        )

        reponse = self.client.post(
            f"/api/availability-campaigns/{self.campagne.id}/remind/",
            {},
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(reponse.data["reminded"], 1)
        destinataires = set(
            Notification.objects.filter(title="Disponibilités attendues").values_list(
                "recipient_id", flat=True
            )
        )
        self.assertEqual(destinataires, {self.retardataire.user_id})

    def test_un_enseignant_ne_relance_pas_ses_collegues(self):
        self.client.force_authenticate(self.retardataire.user)

        reponse = self.client.post(
            f"/api/availability-campaigns/{self.campagne.id}/remind/", {}, format="json"
        )

        self.assertEqual(reponse.status_code, status.HTTP_403_FORBIDDEN)

    def test_l_enseignant_ne_declare_pas_hors_collecte(self):
        self.campagne.status = AvailabilityCampaign.Status.CLOSED
        self.campagne.save(update_fields=["status"])
        self.client.force_authenticate(self.repondant.user)

        reponse = self.client.post(
            "/api/teacher-availability-slots/",
            {"day_of_week": "MON", "start_time": "08:00", "end_time": "10:00"},
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_l_administration_corrige_meme_apres_la_cloture(self):
        """C'est son travail d'arbitre; l'en priver la renverrait vers la base."""
        self.campagne.status = AvailabilityCampaign.Status.CLOSED
        self.campagne.save(update_fields=["status"])

        reponse = self._declarer(self.repondant)

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)

    def test_une_ecole_sans_campagne_declare_comme_avant(self):
        """La nouveaute ne doit pas bloquer qui ne l'a pas encore adoptee."""
        autre = Etablissement.objects.create(name="Ecole sans campagne")
        enseignant = self._enseignant("prof_sans_campagne", etablissement=autre)
        self.client.force_authenticate(enseignant.user)

        reponse = self.client.post(
            "/api/teacher-availability-slots/",
            {"day_of_week": "MON", "start_time": "08:00", "end_time": "10:00"},
            format="json",
        )

        self.assertEqual(reponse.status_code, status.HTTP_201_CREATED, reponse.data)
        self.assertIsNone(reponse.data["campaign"])

    def test_deux_campagnes_sur_la_meme_annee_sont_refusees(self):
        doublon = self.client.post(
            "/api/availability-campaigns/",
            {
                "academic_year": self.annee.id,
                "label": "Seconde collecte",
                "opens_on": timezone.localdate().isoformat(),
                "closes_on": (timezone.localdate() + timedelta(days=5)).isoformat(),
            },
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertIn(
            doublon.status_code,
            (status.HTTP_400_BAD_REQUEST, status.HTTP_409_CONFLICT),
        )

    def test_une_fermeture_avant_l_ouverture_est_refusee(self):
        reponse = self.client.post(
            "/api/availability-campaigns/",
            {
                "academic_year": AcademicYear.objects.create(
                    name="2026-2027",
                    start_date=date(2026, 9, 1),
                    end_date=date(2027, 7, 31),
                ).id,
                "label": "Rentrée suivante",
                "opens_on": "2026-09-10",
                "closes_on": "2026-09-01",
            },
            format="json",
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

        self.assertEqual(reponse.status_code, status.HTTP_400_BAD_REQUEST)

    def test_une_autre_ecole_ne_voit_pas_la_campagne(self):
        autre = Etablissement.objects.create(name="Ecole voisine")
        etranger = User.objects.create_user(
            username="dir_voisin",
            password="Pass1234!",
            role=UserRole.DIRECTOR,
            etablissement=autre,
        )
        self.client.force_authenticate(etranger)

        lignes = self.client.get("/api/availability-campaigns/").data["results"]

        self.assertEqual(lignes, [])


class GrilleTests(_CollecteMixin, APITestCase):
    """La grille compte les disponibles au lieu de nommer un proprietaire.

    Elle rendait « disponible » ou « indisponible » pour l'etablissement
    entier et nommait celui qui avait « reserve » la case: elle decrivait la
    reservation exclusive que ce module n'aurait jamais du etre.
    """

    @classmethod
    def setUpTestData(cls):
        cls._decor(nom="Etab Grille")
        cls.volontaire = cls._enseignant("prof_grille_un")
        cls.possible = cls._enseignant("prof_grille_deux")
        cls.refusant = cls._enseignant("prof_grille_trois")

    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.direction)
        for enseignant, genre in (
            (self.volontaire, AvailabilityKind.PREFERRED),
            (self.possible, AvailabilityKind.POSSIBLE),
            (self.refusant, AvailabilityKind.UNAVAILABLE),
        ):
            TeacherAvailabilitySlot.objects.create(
                teacher=enseignant,
                etablissement=self.etablissement,
                day_of_week="MON",
                start_time=time(8, 0),
                end_time=time(9, 0),
                kind=genre,
            )

    def _grille(self, **params):
        return self.client.get(
            "/api/teacher-availability-slots/grid/",
            {"start_hour": 8, "end_hour": 10, "slot_minutes": 60, **params},
            HTTP_X_ETABLISSEMENT_ID=str(self.etablissement.id),
        )

    def _case(self, data, jour="MON", index=0):
        jours = {ligne["day_of_week"]: ligne for ligne in data["days"]}
        return jours[jour]["cells"][index]

    def test_chaque_case_compte_les_trois_etats(self):
        case = self._case(self._grille().data)

        self.assertEqual(case["preferred_count"], 1)
        self.assertEqual(case["possible_count"], 1)
        self.assertEqual(case["unavailable_count"], 1)

    def test_une_case_sans_declaration_reste_a_zero(self):
        case = self._case(self._grille().data, index=1)

        self.assertEqual(case["preferred_count"], 0)
        self.assertEqual(case["possible_count"], 0)

    def test_la_case_nomme_les_declarants(self):
        case = self._case(self._grille().data)

        noms = {ligne["teacher"] for ligne in case["teachers"]}
        self.assertEqual(
            noms, {self.volontaire.id, self.possible.id, self.refusant.id}
        )

    def test_l_enseignant_vise_retrouve_sa_propre_declaration(self):
        case = self._case(self._grille(teacher=self.volontaire.id).data)

        self.assertEqual(case["mine"], AvailabilityKind.PREFERRED)
        self.assertTrue(case["mine_exact"])

    def test_sans_enseignant_vise_la_case_n_a_pas_de_mienne(self):
        case = self._case(self._grille().data)

        self.assertIsNone(case["mine"])

    def test_le_filtre_par_enseignant_ne_masque_pas_les_collegues(self):
        """Les compteurs restent ceux de l'etablissement, filtre ou non.

        L'ancienne grille affichait « Disponible » aux cases prises par
        d'autres des qu'on filtrait, et l'echec n'arrivait qu'au moment
        d'enregistrer.
        """
        case = self._case(self._grille(teacher=self.volontaire.id).data)

        self.assertEqual(case["possible_count"], 1)
        self.assertEqual(case["unavailable_count"], 1)

    def test_une_declaration_d_une_heure_ne_remplit_pas_deux_heures(self):
        data = self._grille(slot_minutes=120).data
        case = self._case(data)

        self.assertEqual(case["preferred_count"], 0)

    def test_une_plage_horaire_absurde_est_refusee(self):
        self.assertEqual(
            self._grille(start_hour=18, end_hour=8).status_code,
            status.HTTP_400_BAD_REQUEST,
        )
