"""L'envoi des bulletins aux familles par WhatsApp.

Ces tests tiennent surtout les refus. Preparer un envoi est facile; ce qui
protege l'ecole, c'est qu'aucun bulletin ne parte sans destinataire connu,
sans accord de la famille, sans note a l'interieur, ni deux fois de suite --
et qu'un lien recu par un tiers n'ouvre rien.
"""

from datetime import date, timedelta

from django.test import override_settings
from django.test.utils import CaptureQueriesContext
from django.db import connection
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from apps.accounts.models import User, UserRole
from apps.reports.bulletin_delivery import horodatage_d_expiration, signer
from apps.school.models import (
    AcademicYear,
    BulletinDelivery,
    BulletinDeliveryStatus,
    BulletinPublication,
    ClassRoom,
    Etablissement,
    Grade,
    ParentProfile,
    Student,
    Subject,
)


@override_settings(DEFAULT_PHONE_COUNTRY_CODE="223", NATIONAL_PHONE_LENGTH=8)
class BulletinWhatsAppApiTests(APITestCase):
    def setUp(self):
        self.etablissement = Etablissement.objects.create(
            name="Etab Bulletins",
            address="Bamako",
            phone="20202020",
            email="bulletins@example.com",
        )
        self.annee = AcademicYear.objects.create(
            etablissement=self.etablissement,
            name="2025-2026",
            start_date=date(2025, 10, 1),
            end_date=date(2026, 6, 30),
            is_active=True,
        )
        self.classe = ClassRoom.objects.create(
            name="6eme A",
            academic_year=self.annee,
            etablissement=self.etablissement,
        )
        self.matiere = Subject.objects.create(name="Mathématiques", code="MATH", classroom=self.classe)

        self.directeur = User.objects.create_user(
            username="directeur_bulletins",
            password="pass12345",
            role=UserRole.DIRECTOR,
            etablissement=self.etablissement,
        )
        self.enseignant = User.objects.create_user(
            username="enseignant_bulletins",
            password="pass12345",
            role=UserRole.TEACHER,
            etablissement=self.etablissement,
        )

        # Les bulletins ne partent que d'une periode arretee: les tests qui
        # ne portent pas sur cette regle la satisfont d'entree.
        self.publication = BulletinPublication.objects.create(
            classroom=self.classe,
            academic_year=self.annee,
            term="T1",
            is_published=True,
        )

        self.eleve = self._creer_eleve("Awa", "Traoré", "awa")
        self._noter(self.eleve, 15)

    # --- fabriques -------------------------------------------------------

    def _creer_eleve(self, prenom, nom, identifiant, *, avec_parent=True, consent=True, numero="+22376123456"):
        user_eleve = User.objects.create_user(
            username=f"eleve_{identifiant}",
            password="pass12345",
            role=UserRole.STUDENT,
            first_name=prenom,
            last_name=nom,
            etablissement=self.etablissement,
        )
        parent = None
        if avec_parent:
            user_parent = User.objects.create_user(
                username=f"parent_{identifiant}",
                password="pass12345",
                role=UserRole.PARENT,
                first_name="Parent",
                last_name=nom,
                etablissement=self.etablissement,
            )
            parent = ParentProfile.objects.create(
                user=user_parent,
                etablissement=self.etablissement,
                whatsapp_phone=numero,
                whatsapp_consent=consent,
            )
        return Student.objects.create(
            user=user_eleve,
            classroom=self.classe,
            parent=parent,
            etablissement=self.etablissement,
            gender=Student.Gender.FEMALE,
        )

    def _noter(self, eleve, valeur, term="T1"):
        return Grade.objects.create(
            student=eleve,
            subject=self.matiere,
            classroom=self.classe,
            academic_year=self.annee,
            term=term,
            value=valeur,
        )

    def _url(self, eleve, term="T1"):
        return f"/api/reports/bulletin/{eleve.id}/{self.annee.id}/{term}/whatsapp/"

    # --- preparation d'un envoi -----------------------------------------

    def test_la_direction_prepare_un_envoi(self):
        """Le cas nominal: un lien pret a ouvrir, et une trace en base."""
        self.client.force_authenticate(self.directeur)
        response = self.client.post(self._url(self.eleve))

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data["phone"], "+22376123456")
        # wa.me n'accepte pas le « + » de la forme E.164.
        self.assertIn("https://wa.me/22376123456?", response.data["whatsapp_url"])
        self.assertIn("Awa", response.data["message"])
        self.assertIn("/api/reports/bulletin-partage/", response.data["download_url"])

        livraison = BulletinDelivery.objects.get(id=response.data["delivery_id"])
        self.assertEqual(livraison.status, BulletinDeliveryStatus.PREPARED)
        self.assertEqual(livraison.phone, "+22376123456")
        self.assertEqual(livraison.prepared_by, self.directeur)

    def test_le_message_nomme_l_eleve_avant_le_lien(self):
        """Un message qui s'ouvre sur une URL se fait prendre pour une arnaque."""
        self.client.force_authenticate(self.directeur)
        message = self.client.post(self._url(self.eleve)).data["message"]

        self.assertLess(message.index("Awa"), message.index("http"))
        self.assertIn("Etab Bulletins", message)
        self.assertIn("2025-2026", message)

    def test_sans_accord_du_parent_rien_ne_part(self):
        eleve = self._creer_eleve("Moussa", "Diallo", "moussa", consent=False)
        self._noter(eleve, 12)

        self.client.force_authenticate(self.directeur)
        response = self.client.post(self._url(eleve))

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("accord", str(response.data["detail"]).lower())
        self.assertFalse(BulletinDelivery.objects.filter(student=eleve).exists())

    def test_sans_numero_rien_ne_part(self):
        eleve = self._creer_eleve("Fanta", "Keita", "fanta", numero="")
        self._noter(eleve, 12)

        self.client.force_authenticate(self.directeur)
        response = self.client.post(self._url(eleve))

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("numéro", str(response.data["detail"]).lower())

    def test_sans_parent_rattache_rien_ne_part(self):
        eleve = self._creer_eleve("Ibrahim", "Cissé", "ibrahim", avec_parent=False)
        self._noter(eleve, 12)

        self.client.force_authenticate(self.directeur)
        response = self.client.post(self._url(eleve))

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("parent", str(response.data["detail"]).lower())

    def test_un_bulletin_sans_note_ne_part_pas(self):
        """Une feuille vide a en-tete coute plus qu'elle ne rapporte."""
        eleve = self._creer_eleve("Salif", "Coulibaly", "salif")

        self.client.force_authenticate(self.directeur)
        response = self.client.post(self._url(eleve))

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("vide", str(response.data["detail"]).lower())

    def test_le_second_envoi_demande_confirmation(self):
        """Reprendre une classe le lendemain ne doit pas tout renvoyer."""
        self.client.force_authenticate(self.directeur)
        premiere = self.client.post(self._url(self.eleve))
        BulletinDelivery.objects.get(id=premiere.data["delivery_id"]).marquer_envoye()

        refus = self.client.post(self._url(self.eleve))
        self.assertEqual(refus.status_code, status.HTTP_409_CONFLICT)
        self.assertTrue(refus.data["already_sent"])
        self.assertEqual(BulletinDelivery.objects.filter(student=self.eleve).count(), 1)

        confirme = self.client.post(self._url(self.eleve), {"force": True}, format="json")
        self.assertEqual(confirme.status_code, status.HTTP_201_CREATED)
        self.assertEqual(BulletinDelivery.objects.filter(student=self.eleve).count(), 2)

    def test_l_etat_ne_cree_aucune_trace(self):
        """Regarder un ecran n'est pas envoyer."""
        self.client.force_authenticate(self.directeur)
        response = self.client.get(self._url(self.eleve))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data["can_send"])
        self.assertEqual(response.data["blocked_reason"], "")
        self.assertFalse(BulletinDelivery.objects.exists())

    def test_une_periode_inconnue_est_refusee(self):
        self.client.force_authenticate(self.directeur)
        response = self.client.post(self._url(self.eleve, term="T9"))
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_une_periode_non_validee_retient_tous_les_bulletins(self):
        """Un envoi ne se rappelle pas: la periode s'arrete avant de partir."""
        self.publication.annuler()

        self.client.force_authenticate(self.directeur)
        response = self.client.post(self._url(self.eleve))

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("ne sont pas encore validés", str(response.data["detail"]))
        self.assertFalse(BulletinDelivery.objects.exists())

    def test_la_periode_prime_sur_les_contacts_manquants(self):
        """Le motif affiche est celui qu'il faut corriger en premier.

        Courir apres les numeros d'une classe pour decouvrir ensuite que rien
        ne pouvait partir est le scenario que cet ordre evite.
        """
        self.publication.annuler()
        eleve = self._creer_eleve("Moussa", "Diallo", "moussa", consent=False)
        self._noter(eleve, 12)

        self.client.force_authenticate(self.directeur)
        response = self.client.get(self._url(eleve))

        self.assertIn("ne sont pas encore validés", response.data["blocked_reason"])

    def test_une_periode_jamais_validee_ne_laisse_rien_partir(self):
        """Le defaut est « non validee », y compris sans ligne en base.

        L'inverse aurait fait partir d'un coup tous les bulletins des annees
        deja saisies au premier deploiement.
        """
        self.publication.delete()

        self.client.force_authenticate(self.directeur)
        response = self.client.post(self._url(self.eleve))

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_l_etat_d_une_classe_porte_la_validation(self):
        """L'ecran doit pouvoir le dire une fois, pas soixante."""
        self.publication.valider(par=self.directeur, notes="Conseil du 12")

        self.client.force_authenticate(self.directeur)
        response = self.client.get(
            f"/api/reports/bulletins/class/{self.classe.id}/{self.annee.id}/T1/whatsapp/"
        )

        self.assertTrue(response.data["period_published"])
        self.assertIsNotNone(response.data["period_published_at"])

        self.publication.annuler()
        rouverte = self.client.get(
            f"/api/reports/bulletins/class/{self.classe.id}/{self.annee.id}/T1/whatsapp/"
        )
        self.assertFalse(rouverte.data["period_published"])
        self.assertEqual(rouverte.data["ready_count"], 0)

    def test_une_classe_validee_n_ouvre_pas_les_autres(self):
        """La validation vaut pour une classe et une periode, pas au-dela."""
        autre_classe = ClassRoom.objects.create(
            name="6eme B",
            academic_year=self.annee,
            etablissement=self.etablissement,
        )
        voisin = self._creer_eleve("Salif", "Coulibaly", "salif")
        voisin.classroom = autre_classe
        voisin.save()
        self._noter(voisin, 13)

        self.client.force_authenticate(self.directeur)
        response = self.client.post(self._url(voisin))

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("ne sont pas encore validés", str(response.data["detail"]))

    def test_un_autre_trimestre_reste_ferme(self):
        eleve = self.eleve
        self._noter(eleve, 14, term="T2")

        self.client.force_authenticate(self.directeur)
        response = self.client.post(self._url(eleve, term="T2"))

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("T2", str(response.data["detail"]))

    def test_un_eleve_sans_classe_ne_recoit_pas_de_bulletin(self):
        orphelin = self._creer_eleve("Kadia", "Sangaré", "kadia")
        self._noter(orphelin, 12)
        orphelin.classroom = None
        orphelin.save()

        self.client.force_authenticate(self.directeur)
        response = self.client.post(self._url(orphelin))

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("aucune classe", str(response.data["detail"]).lower())

    # --- droits ----------------------------------------------------------

    def test_l_enseignant_lit_les_bulletins_mais_ne_les_diffuse_pas(self):
        """La consultation d'un bulletin n'emporte pas le droit de l'envoyer."""
        self.client.force_authenticate(self.enseignant)
        self.assertEqual(
            self.client.post(self._url(self.eleve)).status_code,
            status.HTTP_403_FORBIDDEN,
        )
        self.assertEqual(
            self.client.get(self._url(self.eleve)).status_code,
            status.HTTP_403_FORBIDDEN,
        )

    def test_le_parent_ne_declenche_pas_ses_propres_envois(self):
        parent = self.eleve.parent.user
        self.client.force_authenticate(parent)
        self.assertEqual(
            self.client.post(self._url(self.eleve)).status_code,
            status.HTTP_403_FORBIDDEN,
        )

    def test_une_autre_ecole_n_atteint_pas_cet_eleve(self):
        autre = Etablissement.objects.create(name="Autre ecole", address="Segou", email="autre@example.com")
        directeur_autre = User.objects.create_user(
            username="directeur_autre",
            password="pass12345",
            role=UserRole.DIRECTOR,
            etablissement=autre,
        )
        self.client.force_authenticate(directeur_autre)
        self.assertEqual(
            self.client.post(self._url(self.eleve)).status_code,
            status.HTTP_403_FORBIDDEN,
        )

    # --- lien recu par la famille ---------------------------------------

    def test_le_lien_signe_sert_le_bulletin_et_note_la_consultation(self):
        self.client.force_authenticate(self.directeur)
        preparation = self.client.post(self._url(self.eleve))
        livraison = BulletinDelivery.objects.get(id=preparation.data["delivery_id"])
        livraison.marquer_envoye()

        chemin = preparation.data["download_url"]
        chemin = chemin[chemin.index("/api/") :]

        # La famille n'a pas de compte: le lien doit repondre sans session.
        self.client.force_authenticate(user=None)
        response = self.client.get(chemin)

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response["Content-Type"], "application/pdf")
        self.assertTrue(response["Content-Disposition"].startswith("inline;"))
        self.assertIn("noindex", response["X-Robots-Tag"])

        livraison.refresh_from_db()
        self.assertEqual(livraison.status, BulletinDeliveryStatus.READ)
        self.assertIsNotNone(livraison.read_at)

    def test_une_signature_falsifiee_n_ouvre_rien(self):
        expire = horodatage_d_expiration()
        chemin = (
            f"/api/reports/bulletin-partage/{self.eleve.id}/{self.annee.id}/T1/{expire}/"
            f"{'0' * 32}/"
        )
        response = self.client.get(chemin)

        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)
        self.assertNotIn("application/pdf", response["Content-Type"])
        # La page d'erreur ne nomme aucun eleve: un lien ramasse par un
        # inconnu ne doit rien apprendre.
        self.assertNotIn("Awa", response.content.decode("utf-8"))

    def test_un_lien_perime_ne_sert_plus_le_bulletin(self):
        expire = int((timezone.now() - timedelta(hours=1)).timestamp())
        signature = signer(self.eleve.id, self.annee.id, "T1", expire)
        chemin = (
            f"/api/reports/bulletin-partage/{self.eleve.id}/{self.annee.id}/T1/{expire}/{signature}/"
        )
        response = self.client.get(chemin)

        self.assertEqual(response.status_code, status.HTTP_410_GONE)

    def test_la_signature_ne_vaut_que_pour_son_eleve(self):
        """Changer l'identifiant dans l'URL ne donne pas le bulletin du voisin."""
        voisin = self._creer_eleve("Oumar", "Sidibé", "oumar")
        self._noter(voisin, 9)

        expire = horodatage_d_expiration()
        signature = signer(self.eleve.id, self.annee.id, "T1", expire)
        chemin = f"/api/reports/bulletin-partage/{voisin.id}/{self.annee.id}/T1/{expire}/{signature}/"

        self.assertEqual(self.client.get(chemin).status_code, status.HTTP_404_NOT_FOUND)

    # --- classe entiere --------------------------------------------------

    def test_la_classe_prepare_les_envois_possibles_et_explique_les_autres(self):
        """Une classe se traite en une fois, pas eleve par eleve."""
        sans_accord = self._creer_eleve("Aminata", "Sow", "aminata", consent=False)
        self._noter(sans_accord, 11)
        sans_note = self._creer_eleve("Bakary", "Kone", "bakary")

        self.client.force_authenticate(self.directeur)
        response = self.client.post(
            f"/api/reports/bulletins/class/{self.classe.id}/{self.annee.id}/T1/whatsapp/"
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        prets = {ligne["student_id"] for ligne in response.data["prepared"]}
        self.assertEqual(prets, {self.eleve.id})

        motifs = {ligne["student_id"]: ligne["reason"] for ligne in response.data["skipped"]}
        self.assertIn("accord", motifs[sans_accord.id].lower())
        self.assertIn("vide", motifs[sans_note.id].lower())

    def test_l_etat_d_une_classe_compte_les_joignables(self):
        self._creer_eleve("Aminata", "Sow", "aminata", consent=False)

        self.client.force_authenticate(self.directeur)
        response = self.client.get(
            f"/api/reports/bulletins/class/{self.classe.id}/{self.annee.id}/T1/whatsapp/"
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["ready_count"], 1)
        self.assertEqual(response.data["blocked_count"], 1)
        self.assertFalse(BulletinDelivery.objects.exists())

    def test_la_classe_peut_etre_restreinte_a_quelques_eleves(self):
        autre = self._creer_eleve("Kadiatou", "Bah", "kadiatou")
        self._noter(autre, 14)

        self.client.force_authenticate(self.directeur)
        response = self.client.post(
            f"/api/reports/bulletins/class/{self.classe.id}/{self.annee.id}/T1/whatsapp/",
            {"student_ids": [autre.id]},
            format="json",
        )

        self.assertEqual(
            {ligne["student_id"] for ligne in response.data["prepared"]},
            {autre.id},
        )

    def test_l_etat_d_une_classe_ne_coute_pas_une_requete_par_eleve(self):
        """Le cout d'affichage ne doit pas suivre l'effectif de la classe.

        L'etat d'un eleve demande deux lectures -- « a-t-il des notes »,
        « a-t-il deja recu ». Prises eleve par eleve, une classe de soixante
        en faisait cent vingt, sur les 0,1 CPU du plan d'hebergement.

        Le test compare deux classes de tailles differentes plutot que de
        figer un nombre: un chiffre en dur se fait ajuster a la premiere
        requete ajoutee ailleurs, et ne protege plus de rien.
        """
        url = f"/api/reports/bulletins/class/{self.classe.id}/{self.annee.id}/T1/whatsapp/"
        self.client.force_authenticate(self.directeur)

        # Un appel a vide d'abord: le premier de la session porte des lectures
        # qui ne se rejouent pas (compte, droits), et les compter fausserait
        # la comparaison au point de la rendre ininterpretable.
        self.client.get(url)

        with CaptureQueriesContext(connection) as petite_classe:
            self.assertEqual(self.client.get(url).status_code, status.HTTP_200_OK)

        for index in range(6):
            eleve = self._creer_eleve("Eleve", f"Numero{index}", f"n{index}")
            self._noter(eleve, 10 + index)

        with CaptureQueriesContext(connection) as grande_classe:
            reponse = self.client.get(url)

        self.assertEqual(reponse.status_code, status.HTTP_200_OK)
        self.assertEqual(len(reponse.data["students"]), 7)
        self.assertEqual(len(grande_classe.captured_queries), len(petite_classe.captured_queries))

        # --- suivi -----------------------------------------------------------

    def test_l_ecole_declare_l_envoi_effectue(self):
        """Sur le canal assiste, c'est un humain qui appuie sur envoyer."""
        self.client.force_authenticate(self.directeur)
        preparation = self.client.post(self._url(self.eleve))
        identifiant = preparation.data["delivery_id"]

        response = self.client.post(f"/api/reports/bulletin-deliveries/{identifiant}/sent/")

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["status"], BulletinDeliveryStatus.SENT)
        self.assertIsNotNone(response.data["sent_at"])

    def test_un_envoi_qui_echoue_garde_son_motif(self):
        self.client.force_authenticate(self.directeur)
        preparation = self.client.post(self._url(self.eleve))
        identifiant = preparation.data["delivery_id"]

        response = self.client.post(
            f"/api/reports/bulletin-deliveries/{identifiant}/sent/",
            {"failure_reason": "Numéro plus attribué"},
            format="json",
        )

        self.assertEqual(response.data["status"], BulletinDeliveryStatus.FAILED)
        self.assertEqual(response.data["failure_reason"], "Numéro plus attribué")

    def test_le_numero_reste_celui_du_jour_de_l_envoi(self):
        """Un numero corrige en janvier ne reecrit pas ce qui est parti en decembre."""
        self.client.force_authenticate(self.directeur)
        preparation = self.client.post(self._url(self.eleve))

        parent = self.eleve.parent
        parent.whatsapp_phone = "+22366742232"
        parent.save()

        livraison = BulletinDelivery.objects.get(id=preparation.data["delivery_id"])
        self.assertEqual(livraison.phone, "+22376123456")
