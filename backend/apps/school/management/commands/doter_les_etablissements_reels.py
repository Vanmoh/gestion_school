"""Peupler les quatre etablissements reels de bout en bout.

Le depot savait creer des classes (`insert_classes`), des matieres pour deux
ecoles (`assign_subjects_to_classes`), des eleves pour une seule
(`seed_ltob_data`), et des notes a la demande (`seed_term_scores`). Aucune
commande ne montait une ecole entiere, et aucune ne montait les quatre.

Celle-ci le fait, dans l'ordre ou une ecole se monte:

1. l'annee scolaire, si elle manque;
2. les classes de l'etablissement, lues dans `insert_classes`;
3. les matieres de chaque classe, selon sa filiere -- le nom de la classe la
   porte (« 11eme CG » gestion, « 2eme Annee EM1 » electromecanique);
4. trente eleves par classe, noms et prenoms maliens;
5. les enseignants qu'il faut, et leurs affectations: un enseignant tient une
   matiere, et la tient dans toutes les classes ou elle s'enseigne;
6. les volumes horaires, puis l'emploi du temps -- chaque enseignant a des
   heures a hauteur de ce qu'il enseigne;
7. les notes des trois trimestres, pour toutes les matieres et tous les
   eleves: trois devoirs et une composition, entre 9 et 19;
8. les frais: l'inscription reglee par tous, la scolarite soldee par trois
   eleves sur quatre.

Trois proprietes qu'il ne faut pas lui retirer:

- **idempotente**: `get_or_create` partout, et l'alea derive de l'identite des
  objets, jamais d'un compteur d'iteration. Relancee, elle ne double rien;
- **deterministe**: meme graine, meme ecole -- jusqu'aux notes;
- **refus hors developpement**: elle cree des comptes a mot de passe connu et
  des ecritures comptables. `--forcer` existe pour les bases jetables.
"""

import random
import re
from datetime import date, datetime, time, timedelta
from decimal import Decimal

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.utils import timezone

from apps.accounts.models import User, UserRole
from apps.chat.models import ChatMessage, Conversation, ConversationParticipant
from apps.school.models import (
    AcademicYear,
    Announcement,
    Attendance,
    AttendanceSheetValidation,
    AvailabilityCampaign,
    Book,
    Borrow,
    BulletinDelivery,
    BulletinPublication,
    CanteenMenu,
    CanteenService,
    CanteenSubscription,
    ClassRoom,
    Etablissement,
    ExamInvigilation,
    ExamPlanning,
    ExamResult,
    ExamSession,
    DisciplineIncident,
    Expense,
    FeeSchedule,
    FeeType,
    GradeValidation,
    Grade,
    LibraryCategory,
    LibraryCollection,
    LibraryDocument,
    Notification,
    PromotionDecision,
    PromotionDecisionType,
    PromotionRun,
    PromotionRunStatus,
    ParentProfile,
    Payment,
    StockItem,
    StockMovement,
    StockMovementType,
    SmsProviderConfig,
    Student,
    StudentAcademicHistory,
    StudentFee,
    Supplier,
    Subject,
    Teacher,
    TeacherAssignment,
    TeacherAttendance,
    TeacherAvailabilitySlot,
    TeacherPayroll,
    TeacherScheduleSlot,
    TeacherTimeEntry,
    TimetablePublication,
    recalculate_term_ranking,
)

# --------------------------------------------------------------------- noms

PRENOMS_GARCONS = (
    "Amadou", "Boubacar", "Cheick", "Daouda", "Drissa", "Ibrahim", "Issa",
    "Lassine", "Mamadou", "Modibo", "Moussa", "Oumar", "Ousmane", "Salif",
    "Seydou", "Sekou", "Souleymane", "Adama", "Bakary", "Bourama", "Fousseyni",
    "Hamidou", "Karim", "Madou", "Mahamadou", "Nouhoum", "Sidiki", "Yacouba",
    "Youssouf", "Abdoulaye", "Alassane", "Bandiougou", "Broulaye", "Dramane",
)
PRENOMS_FILLES = (
    "Aminata", "Assitan", "Awa", "Bintou", "Coumba", "Djeneba", "Fanta",
    "Fatoumata", "Hawa", "Kadiatou", "Kadidia", "Korotoumou", "Mariam",
    "Nana", "Oumou", "Ramata", "Rokia", "Safiatou", "Salimata", "Sanata",
    "Tenin", "Aissata", "Alima", "Batoma", "Diahara", "Fadima", "Hapsatou",
    "Maimouna", "Naba", "Sitan", "Djelika", "Fatim", "Kanto", "Massitan",
)
NOMS = (
    "Traore", "Diallo", "Keita", "Coulibaly", "Sangare", "Toure", "Konate",
    "Sidibe", "Dembele", "Maiga", "Cisse", "Doumbia", "Camara", "Fofana",
    "Kone", "Sow", "Sylla", "Bah", "Barry", "Conde", "Bamba", "Ouattara",
    "Haidara", "Tall", "Niang", "Diakite", "Samake", "Togola", "Berthe",
    "Dicko", "Sacko", "Diarra", "Kanoute", "Tangara", "Sissoko", "Bagayoko",
)

# --------------------------------------------------------------- curriculum

# Le tronc commun, present dans toute classe du secondaire.
TRONC_COMMUN = (
    ("Français", "FR", 3),
    ("Anglais", "AN", 2),
    ("Mathématiques", "MA", 4),
    ("Histoire-Géographie", "HG", 2),
    ("Éducation Civique et Morale", "ECM", 1),
    ("Éducation Physique et Sportive", "EPS", 1),
)

# Les matieres de specialite, reconnues au sigle que porte le nom de la classe.
#
# L'ordre compte: « TSECO » doit etre essaye avant « TS », et « BD » avant
# « DB » ne changerait rien mais « CG1 » doit tomber sur « CG ».
SPECIALITES = (
    ("TSEXP", (("Sciences Physiques", "PH", 4), ("Sciences Naturelles", "SN", 4),
               ("Biologie", "BIO", 3), ("Informatique", "INFO", 2))),
    ("TSECO", (("Économie", "ECO", 4), ("Comptabilité", "CPT", 4),
               ("Statistiques", "STA", 3), ("Informatique", "INFO", 2))),
    ("TSS", (("Sciences Sociales", "SS", 4), ("Philosophie", "PHILO", 3),
             ("Économie", "ECO", 2), ("Informatique", "INFO", 2))),
    ("TSE", (("Sciences Physiques", "PH", 4), ("Sciences Naturelles", "SN", 3),
             ("Informatique", "INFO", 2))),
    ("TLL", (("Philosophie", "PHILO", 4), ("Littérature", "LIT", 4),
             ("Langue Vivante 2", "LV2", 2))),
    ("SES", (("Économie", "ECO", 4), ("Sciences Sociales", "SS", 3),
             ("Statistiques", "STA", 2), ("Informatique", "INFO", 2))),
    ("CG", (("Comptabilité", "CPT", 4), ("Droit Commercial", "DRC", 2),
            ("Économie", "ECO", 2), ("Gestion", "GES", 3),
            ("Informatique", "INFO", 2))),
    ("GM", (("Sciences Mécaniques", "MEC", 4), ("Dessin Technique", "DT", 3),
            ("Technologie", "TEC", 3), ("Atelier", "ATL", 3))),
    ("EM", (("Électricité", "ELE", 4), ("Dessin Technique", "DT", 3),
            ("Technologie", "TEC", 3), ("Travaux Pratiques", "TP", 4))),
    ("DB", (("Dessin Bâtiment", "DB", 4), ("Béton Armé", "BA", 3),
            ("Topographie", "TOP", 3), ("Technologie", "TEC", 2))),
    ("BD", (("Dessin Bâtiment", "DB", 4), ("Béton Armé", "BA", 3),
            ("Topographie", "TOP", 3), ("Technologie", "TEC", 2))),
    ("TC", (("Sciences Physiques", "PH", 3), ("Technologie", "TEC", 3),
            ("Dessin Technique", "DT", 2), ("Informatique", "INFO", 2))),
    ("CT", (("Sciences Physiques", "PH", 3), ("Sciences Naturelles", "SN", 3),
            ("Informatique", "INFO", 2))),
    ("S", (("Sciences Physiques", "PH", 4), ("Sciences Naturelles", "SN", 3),
           ("Informatique", "INFO", 2))),
)

# Le fondamental: une classe numerotee sans sigle de filiere.
FONDAMENTAL = (
    ("Français", "FR", 4),
    ("Mathématiques", "MA", 4),
    ("Éveil Scientifique", "EVS", 2),
    ("Histoire-Géographie", "HG", 2),
    ("Éducation Civique et Morale", "ECM", 1),
    ("Anglais", "AN", 2),
    ("Éducation Physique et Sportive", "EPS", 1),
)

# ----------------------------------------------------------------- horaires

# Une journee de cours, heure par heure.
#
# Trois blocs de deux heures ne donnaient que dix-huit places par classe, pour
# une trentaine d'heures a placer: la moitie des seances tombait, et huit
# professeurs sur dix-sept se retrouvaient sans une seule heure. Six creneaux
# d'une heure sur six jours en donnent trente-six, ce qui suffit -- et
# ressemble davantage a l'emploi du temps d'un lycee.
CRENEAUX = (
    (time(8, 0), time(9, 0)),
    (time(9, 0), time(10, 0)),
    (time(10, 15), time(11, 15)),
    (time(11, 15), time(12, 15)),
    (time(15, 0), time(16, 0)),
    (time(16, 0), time(17, 0)),
)

# Les compositions durent deux heures: elles ne suivent pas la grille des
# cours.
CRENEAUX_DE_COMPOSITION = (
    (time(8, 0), time(10, 0)),
    (time(10, 15), time(12, 15)),
    (time(15, 0), time(17, 0)),
)
JOURS = ("MON", "TUE", "WED", "THU", "FRI", "SAT")

TRIMESTRES = ("T1", "T2", "T3")

MOTIFS = (
    "Maladie",
    "Transport en panne",
    "Raison familiale",
    "Convocation administrative",
)

MOTIFS_DE_DISCIPLINE = (
    ("retard", "low", "Arrivée après la sonnerie, sans justificatif."),
    ("tenue", "low", "Tenue non conforme au règlement intérieur."),
    ("indiscipline", "medium", "Bavardages répétés malgré les rappels."),
    ("insolence", "medium", "Propos irrespectueux envers un surveillant."),
    ("absence_injustifiee", "medium", "Absence non justifiée en cours."),
    ("triche", "high", "Documents non autorisés pendant une composition."),
    ("degradation", "high", "Matériel de classe détérioré."),
    ("violence", "high", "Altercation dans la cour de récréation."),
)

# Ce qu'une annee coute, et comment elle se paie.
FRAIS_INSCRIPTION = Decimal("25000")
FRAIS_MENSUEL = Decimal("15000")
MOIS_DE_SCOLARITE = 9


class Command(BaseCommand):
    help = (
        "Monte les quatre etablissements reels de bout en bout: classes, "
        "matieres, eleves, enseignants, emploi du temps, notes et frais."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--etablissement",
            default="",
            help="N'en monter qu'un seul, par son nom. Vide = les quatre.",
        )
        parser.add_argument(
            "--annee",
            default="",
            help="Nom de l'annee scolaire (defaut: celle en cours, ou 2025-2026).",
        )
        parser.add_argument(
            "--eleves-par-classe",
            type=int,
            default=30,
            help="Effectif vise par classe (defaut 30).",
        )
        parser.add_argument(
            "--part-non-soldee",
            type=int,
            default=25,
            help="Pourcentage d'eleves dont la scolarite reste due (defaut 25).",
        )
        parser.add_argument(
            "--frais-inscription",
            type=int,
            default=int(FRAIS_INSCRIPTION),
            help=(
                "Montant de l'inscription, pose dans le bareme de chaque "
                "classe. Modifiable ensuite depuis l'ecran des finances."
            ),
        )
        parser.add_argument(
            "--frais-mensuel",
            type=int,
            default=int(FRAIS_MENSUEL),
            help="Montant d'une mensualite de scolarite.",
        )
        parser.add_argument(
            "--mensualites",
            type=int,
            default=MOIS_DE_SCOLARITE,
            help=f"Nombre de versements de scolarite (defaut {MOIS_DE_SCOLARITE}).",
        )
        parser.add_argument(
            "--graine",
            type=int,
            default=2026,
            help="Graine d'alea: meme graine, meme ecole.",
        )
        parser.add_argument(
            "--sans-notes",
            action="store_true",
            help="Monter l'ecole sans saisir les notes des trois trimestres.",
        )
        parser.add_argument(
            "--forcer",
            action="store_true",
            help="Passe outre le refus hors developpement. Base jetable seulement.",
        )

    # ------------------------------------------------------------------ tour

    def handle(self, *args, **options):
        if not options["forcer"] and not settings.DEBUG:
            raise CommandError(
                "Refus: DEBUG est faux. Cette commande cree des comptes a mot "
                "de passe connu et des ecritures comptables. Utilisez --forcer "
                "sur une base jetable."
            )

        listes = self._classes_par_etablissement()
        vise = options["etablissement"].strip()

        ecoles = []
        for etablissement in Etablissement.objects.order_by("id"):
            if vise and etablissement.name != vise:
                continue
            classes = self._classes_de(etablissement, listes)
            if classes is None:
                self.stdout.write(
                    self.style.WARNING(
                        f"  « {etablissement.name} »: aucune liste de classes "
                        "connue, ecole ignoree."
                    )
                )
                continue
            ecoles.append((etablissement, classes))

        if not ecoles:
            raise CommandError(
                "Aucun etablissement a monter. Verifiez le nom, ou lancez "
                "d'abord les migrations qui inserent les etablissements."
            )

        for etablissement, classes in ecoles:
            self.stdout.write("")
            self.stdout.write(
                self.style.SUCCESS(f"=== {etablissement.name} ===")
            )
            with transaction.atomic():
                self._monter_une_ecole(etablissement, classes, options)

    def _classes_par_etablissement(self):
        from apps.school.management.commands.insert_classes import (
            ESTABLISSEMENT_CLASSES,
        )

        return ESTABLISSEMENT_CLASSES

    def _classes_de(self, etablissement, listes):
        """Les classes prevues pour cette ecole, par son sigle puis par son nom.

        Le sigle d'abord, et c'est tout l'enjeu: « Lycee Technique Oumar Bah
        (LTOB) » et « Lycee Technique Oumar Bah (LOBK) » ne different que par
        lui. Une comparaison par inclusion donnait les cinq classes du premier
        au second, qui en compte treize -- deux ecoles distinctes se
        retrouvaient avec le meme programme.
        """
        nom = etablissement.name.strip().lower()
        sigles = {s.strip().lower() for s in re.findall(r"\(([^)]+)\)", nom)}
        code = (etablissement.code or "").strip().lower()
        if code:
            sigles.add(code)

        # 1. Le sigle, qui distingue deux ecoles homonymes.
        for cle, valeur in listes.items():
            candidats = {cle.strip().lower()} | {
                a.strip().lower() for a in valeur.get("aliases", [])
            }
            if sigles & candidats:
                return valeur["classes"]

        # 2. L'egalite stricte du nom ou d'un alias.
        for cle, valeur in listes.items():
            candidats = {cle.strip().lower()} | {
                a.strip().lower() for a in valeur.get("aliases", [])
            }
            if nom in candidats:
                return valeur["classes"]

        # 3. A defaut seulement, l'inclusion -- et uniquement si une seule
        #    ecole repond, sans quoi on ne sait pas laquelle on designe.
        proches = [
            valeur["classes"]
            for cle, valeur in listes.items()
            if any(
                candidat.strip().lower() in nom
                for candidat in [cle] + list(valeur.get("aliases", []))
            )
        ]
        return proches[0] if len(proches) == 1 else None

    # ------------------------------------------------------------ une ecole

    def _monter_une_ecole(self, etablissement, noms_de_classes, options):
        graine = options["graine"]
        annee = self._annee_scolaire(etablissement, options["annee"])
        classes = self._creer_les_classes(etablissement, annee, noms_de_classes)
        matieres = self._creer_les_matieres(classes)
        eleves = self._inscrire_les_eleves(
            etablissement, classes, options["eleves_par_classe"], graine
        )
        enseignants = self._recruter_les_enseignants(
            etablissement, matieres, graine
        )
        creneaux = self._composer_l_emploi_du_temps(classes, matieres, graine)
        self._publier_les_emplois_du_temps(classes)

        calendrier = self._dresser_le_calendrier_des_compositions(
            annee, classes, matieres
        )

        notes = 0
        if not options["sans_notes"]:
            notes = self._saisir_les_notes(
                annee, classes, matieres, eleves, graine, calendrier
            )

        encadrement = self._nommer_l_encadrement(etablissement, graine)
        familles = self._rattacher_les_familles(etablissement, eleves, graine)
        baremes = self._poser_les_baremes(etablissement, annee, classes, options)
        frais = self._facturer_la_scolarite(
            etablissement, annee, eleves, options["part_non_soldee"], graine
        )
        appels = self._faire_l_appel(annee, classes, eleves, graine)
        pointages = self._pointer_les_enseignants(annee, enseignants, graine)
        incidents = self._consigner_la_discipline(annee, eleves, graine)
        bulletins = self._arreter_les_bulletins(annee, classes)
        surveillances = self._affecter_les_surveillants(classes, enseignants, graine)
        dispos = self._ouvrir_les_disponibilites(
            etablissement, annee, enseignants, graine
        )
        paies = self._preparer_la_paie(etablissement, annee, enseignants)
        depenses = self._engager_des_depenses(etablissement, annee)
        vie = self._animer_la_vie_scolaire(etablissement, eleves, graine)
        mots = self._ouvrir_la_communication(etablissement, enseignants, eleves)
        bilans = self._archiver_les_bilans(annee, classes)
        emargements = self._emarger_les_arrivees(
            etablissement, enseignants, graine
        )
        remises = self._remettre_les_bulletins(etablissement, annee, eleves, graine)
        abonnes = self._abonner_a_la_cantine(annee, eleves)
        numerique = self._ouvrir_la_bibliotheque_numerique(etablissement)
        passage = self._simuler_le_passage(etablissement, annee, classes)

        self.stdout.write(f"  classes              {len(classes)}")
        self.stdout.write(f"  matieres             {len(matieres)}")
        self.stdout.write(f"  eleves               {len(eleves)}")
        self.stdout.write(f"  enseignants          {len(enseignants)}")
        self.stdout.write(f"  creneaux d'horaire   {creneaux}")
        self.stdout.write(f"  notes saisies        {notes}")
        self.stdout.write(f"  encadrement          {encadrement}")
        self.stdout.write(f"  familles             {familles}")
        self.stdout.write(f"  baremes de frais     {baremes}")
        self.stdout.write(f"  frais emis           {frais}")
        self.stdout.write(f"  journees d'appel     {appels}")
        self.stdout.write(f"  pointages enseignants {pointages}")
        self.stdout.write(f"  incidents            {incidents}")
        self.stdout.write(f"  bulletins arretes    {bulletins}")
        self.stdout.write(f"  surveillances        {surveillances}")
        self.stdout.write(f"  creneaux de dispo    {dispos}")
        self.stdout.write(f"  fiches de paie       {paies}")
        self.stdout.write(f"  depenses             {depenses}")
        self.stdout.write(f"  vie scolaire         {vie}")
        self.stdout.write(f"  communication        {mots}")
        self.stdout.write(f"  bilans archives      {bilans}")
        self.stdout.write(f"  emargements          {emargements}")
        self.stdout.write(f"  bulletins remis      {remises}")
        self.stdout.write(f"  abonnes cantine      {abonnes}")
        self.stdout.write(f"  fonds numerique      {numerique}")
        self.stdout.write(f"  passage simule       {passage}")

    # ------------------------------------------------------------- structure

    def _annee_scolaire(self, etablissement, nom_voulu):
        annee = AcademicYear.objects.filter(
            etablissement=etablissement, is_active=True
        ).first()
        if annee is not None and not nom_voulu:
            return annee

        nom = nom_voulu or (annee.name if annee else self._annee_en_cours())
        debut, fin = self._bornes_de(nom)
        annee, _ = AcademicYear.objects.get_or_create(
            name=nom,
            etablissement=etablissement,
            defaults={"start_date": debut, "end_date": fin},
        )
        if not AcademicYear.objects.filter(
            etablissement=etablissement, is_active=True
        ).exists():
            annee.is_active = True
            annee.save(update_fields=["is_active"])
        return annee

    @staticmethod
    def _annee_en_cours():
        aujourdhui = timezone.localdate()
        debut = aujourdhui.year if aujourdhui.month >= 9 else aujourdhui.year - 1
        return f"{debut}-{debut + 1}"

    @staticmethod
    def _bornes_de(nom):
        annees = re.findall(r"\d{4}", nom)
        debut = int(annees[0]) if annees else timezone.localdate().year
        return date(debut, 9, 1), date(debut + 1, 7, 31)

    def _creer_les_classes(self, etablissement, annee, noms):
        classes = []
        for nom in noms:
            classe, _ = ClassRoom.objects.get_or_create(
                name=nom, academic_year=annee, etablissement=etablissement
            )
            classes.append(classe)
        return classes

    def _curriculum_de(self, nom_de_classe):
        """Les matieres d'une classe, deduites de son intitule.

        Le nom porte la filiere: « 11eme CG » est de la gestion, « 2eme Annee
        EM1 » de l'electromecanique, « 5eme Annee » du fondamental. Deduire
        plutot que tabuler evite d'ecrire quarante-deux listes a la main, et
        fait qu'une classe ajoutee demain recoit son programme sans qu'on y
        touche.
        """
        majuscule = nom_de_classe.upper()
        for sigle, matieres in SPECIALITES:
            # Le sigle doit etre un mot, ou suivi d'un chiffre de groupe:
            # « 11ème S » ne doit pas matcher dans « SES ».
            if re.search(rf"(?<![A-Z]){sigle}\d*(?![A-Z])", majuscule):
                return tuple(TRONC_COMMUN) + tuple(matieres)
        return tuple(FONDAMENTAL)

    def _creer_les_matieres(self, classes):
        """Une matiere par couple (classe, programme).

        `Subject.classroom` est une cle etrangere: une matiere appartient a une
        classe, et « Mathematiques » existe donc autant de fois qu'il y a de
        classes qui en font. C'est le modele du depot, pas un choix d'ici.
        """
        matieres = []
        for classe in classes:
            for nom, code, coefficient in self._curriculum_de(classe.name):
                matiere, _ = Subject.objects.get_or_create(
                    code=f"{code}-{classe.id}",
                    defaults={
                        "name": nom,
                        "coefficient": Decimal(coefficient),
                        "classroom": classe,
                    },
                )
                # Le volume horaire suit le coefficient: sans lui, la
                # generation d'emploi du temps n'a rien a placer.
                voulu = 2 if coefficient <= 1 else min(4, 1 + coefficient // 2 + 1)
                if matiere.weekly_slots != voulu or matiere.classroom_id != classe.id:
                    matiere.weekly_slots = voulu
                    matiere.classroom = classe
                    matiere.save(update_fields=["weekly_slots", "classroom"])
                matieres.append(matiere)
        return matieres

    # -------------------------------------------------------------- personnes

    @staticmethod
    def _alea(graine, *cles):
        """Un tirage propre a l'objet decrit, et non a l'ordre d'execution.

        C'est ce qui rend la commande idempotente: un generateur partage
        avancerait selon ce qui existe deja, et le second passage tomberait sur
        d'autres valeurs -- donc sur d'autres lignes.
        """
        return random.Random(f"{graine}|" + "|".join(str(c) for c in cles))

    @staticmethod
    def _un_echantillon(eleves, combien):
        """Des eleves pris a pas regulier, et non les premiers de la liste.

        `eleves` arrive classe par classe: une tranche `[:60]` ne prend donc que
        les deux premieres classes. Un ecran filtre par classe -- remise des
        bulletins, cantine, bibliotheque -- s'ouvrait alors sur rien pour les
        onze autres, alors que le compteur global disait soixante.
        """
        if combien <= 0 or not eleves:
            return []
        if combien >= len(eleves):
            return list(eleves)
        pas = len(eleves) / combien
        return [eleves[int(rang * pas)] for rang in range(combien)]

    @staticmethod
    def _numero_malien(tirage):
        """Un mobile malien plausible, au format que les fiches ecoles portent.

        Les familles n'en avaient aucun, et cela vidait tout un pan de
        l'application: `ParentProfile.whatsapp_phone` se remplit depuis
        `User.phone` par signal, et sans numero la remise d'un bulletin par
        WhatsApp n'a nulle part ou aller -- l'ecran affichait soixante remises
        sans destinataire.

        La forme est celle de la saisie (« 76 12 34 56 »), pas E.164:
        `phone_utils` normalise, et c'est precisement ce qu'il faut lui donner a
        normaliser.
        """
        tete = tirage.choice([60, 62, 65, 66, 70, 74, 76, 78, 79, 83])
        return (
            f"{tete} {tirage.randint(10, 99)} "
            f"{tirage.randint(10, 99)} {tirage.randint(10, 99)}"
        )

    def _inscrire_les_eleves(self, etablissement, classes, effectif, graine):
        eleves = []
        code = self._code_de(etablissement)
        annee_courte = str(timezone.localdate().year)[-2:]

        for classe in classes:
            presents = list(
                Student.objects.filter(classroom=classe).select_related("user")
            )
            rang = len(presents)
            eleves.extend(presents)

            while rang < effectif:
                rang += 1
                tirage = self._alea(graine, "eleve", classe.id, rang)
                fille = tirage.random() < 0.5
                prenom = tirage.choice(
                    PRENOMS_FILLES if fille else PRENOMS_GARCONS
                )
                nom = tirage.choice(NOMS)
                matricule = (
                    f"{code}{classe.id:03d}{annee_courte}E{rang:04d}"
                    f"{'F' if fille else 'M'}"
                )
                identifiant = f"{code.lower()}.{classe.id}.{rang:03d}"

                compte, _ = User.objects.get_or_create(
                    username=identifiant,
                    defaults={
                        "first_name": prenom,
                        "last_name": nom.upper(),
                        "role": UserRole.STUDENT,
                        "etablissement": etablissement,
                    },
                )
                compte.set_password("Eleve@2026")
                compte.is_active = True
                compte.etablissement = etablissement
                compte.save(update_fields=["password", "is_active", "etablissement"])

                eleve, _ = Student.objects.get_or_create(
                    user=compte,
                    defaults={
                        "matricule": matricule,
                        "classroom": classe,
                        "etablissement": etablissement,
                        "gender": "F" if fille else "M",
                    },
                )
                eleves.append(eleve)
        return eleves

    @staticmethod
    def _code_de(etablissement):
        brut = (etablissement.code or etablissement.name or "ET").upper()
        lettres = re.sub(r"[^A-Z0-9]", "", brut)
        return (lettres or "ET")[:4]

    def _recruter_les_enseignants(self, etablissement, matieres, graine):
        """Un enseignant par discipline, qui la tient dans toutes ses classes.

        C'est ainsi qu'une ecole fonctionne: le professeur de mathematiques
        enseigne les mathematiques, dans plusieurs classes. Recruter un
        enseignant par couple matiere-classe aurait donne trois cents
        professeurs a une heure de cours chacun.
        """
        par_discipline = {}
        for matiere in matieres:
            par_discipline.setdefault(matiere.name, []).append(matiere)

        code = self._code_de(etablissement)
        enseignants = []

        for rang, (discipline, ses_matieres) in enumerate(
            sorted(par_discipline.items()), start=1
        ):
            # Au-dela de six classes, on partage la discipline entre deux
            # professeurs: une seule personne ne tient pas trente heures.
            groupes = self._repartir(ses_matieres, maximum=6)
            for indice, groupe in enumerate(groupes, start=1):
                tirage = self._alea(graine, "prof", etablissement.id, discipline, indice)
                prenom = tirage.choice(PRENOMS_GARCONS + PRENOMS_FILLES)
                nom = tirage.choice(NOMS)
                identifiant = f"{code.lower()}.prof{rang:02d}{indice}"

                compte, _ = User.objects.get_or_create(
                    username=identifiant,
                    defaults={
                        "first_name": prenom,
                        "last_name": nom.upper(),
                        "role": UserRole.TEACHER,
                        "etablissement": etablissement,
                    },
                )
                compte.set_password("Prof@2026")
                compte.is_active = True
                compte.etablissement = etablissement
                if not compte.phone:
                    compte.phone = self._numero_malien(tirage)
                compte.save(
                    update_fields=["password", "is_active", "etablissement", "phone"]
                )

                enseignant, _ = Teacher.objects.get_or_create(
                    user=compte,
                    defaults={
                        "employee_code": f"{code}-{rang:02d}{indice}",
                        "hire_date": date(2024, 9, 1),
                        "salary_base": Decimal(tirage.choice([250000, 300000, 350000])),
                        "hourly_rate": Decimal(tirage.choice([2500, 3000, 3500])),
                        "etablissement": etablissement,
                    },
                )
                enseignants.append(enseignant)

                for matiere in groupe:
                    TeacherAssignment.objects.get_or_create(
                        teacher=enseignant,
                        subject=matiere,
                        classroom=matiere.classroom,
                    )
        return enseignants

    @staticmethod
    def _repartir(elements, maximum):
        return [
            elements[i : i + maximum] for i in range(0, len(elements), maximum)
        ]

    # ------------------------------------------------------ emploi du temps

    def _composer_l_emploi_du_temps(self, classes, matieres, graine):
        """Place chaque matiere autant de fois que son volume horaire.

        Deux contraintes, celles d'une vraie ecole: une classe ne suit qu'un
        cours a la fois, et un enseignant ne se trouve pas dans deux salles au
        meme moment. Une seance qui ne trouve pas de place est abandonnee
        plutot que posee sur un creneau deja pris -- le modele l'interdit, et
        c'est tant mieux.
        """
        poses = 0
        occupation_classe = set()
        occupation_prof = set()
        # Ce que chaque affectation tient deja. Sans ce compte, un second
        # passage voyait ses propres seances comme « occupees », les sautait, et
        # replacait son volume entier ailleurs: la grille gonflait de vingt-huit
        # heures a chaque relance, et l'idempotence promise etait fausse.
        deja_posees = {}

        for slot in TeacherScheduleSlot.objects.select_related(
            "assignment"
        ).filter(assignment__classroom__in=classes):
            occupation_classe.add(
                (slot.assignment.classroom_id, slot.day_of_week, slot.start_time)
            )
            occupation_prof.add(
                (slot.assignment.teacher_id, slot.day_of_week, slot.start_time)
            )
            deja_posees[slot.assignment_id] = deja_posees.get(slot.assignment_id, 0) + 1

        affectations = list(
            TeacherAssignment.objects.filter(classroom__in=classes)
            .select_related("subject", "classroom", "teacher")
            .order_by("classroom_id", "subject_id")
        )

        for affectation in affectations:
            volume = affectation.subject.weekly_slots or 2
            tirage = self._alea(graine, "edt", affectation.id)
            creneaux = [
                (jour, debut, fin) for jour in JOURS for debut, fin in CRENEAUX
            ]
            tirage.shuffle(creneaux)

            places = deja_posees.get(affectation.id, 0)
            for jour, debut, fin in creneaux:
                if places >= volume:
                    break
                cle_classe = (affectation.classroom_id, jour, debut)
                cle_prof = (affectation.teacher_id, jour, debut)
                if cle_classe in occupation_classe or cle_prof in occupation_prof:
                    continue

                _, cree = TeacherScheduleSlot.objects.get_or_create(
                    assignment=affectation,
                    day_of_week=jour,
                    start_time=debut,
                    defaults={"end_time": fin},
                )
                occupation_classe.add(cle_classe)
                occupation_prof.add(cle_prof)
                places += 1
                poses += 1 if cree else 0

        poses += self._donner_des_heures_aux_oublies(
            affectations, occupation_classe, occupation_prof
        )
        return poses

    def _donner_des_heures_aux_oublies(
        self, affectations, occupation_classe, occupation_prof
    ):
        """Personne ne doit sortir de la grille sans une heure de cours.

        Le placement echoue parfois faute de creneau libre au moment ou il
        cherche: une matiere arrivee tard trouve la classe deja pleine. Un
        professeur peut alors n'avoir rien, ce qui est une grille fausse -- il
        enseigne, donc il a des heures.
        """
        sans_heure = {}
        for affectation in affectations:
            if TeacherScheduleSlot.objects.filter(
                assignment__teacher_id=affectation.teacher_id
            ).exists():
                continue
            sans_heure.setdefault(affectation.teacher_id, affectation)

        poses = 0
        for affectation in sans_heure.values():
            for jour in JOURS:
                place = False
                for debut, fin in CRENEAUX:
                    cle_classe = (affectation.classroom_id, jour, debut)
                    cle_prof = (affectation.teacher_id, jour, debut)
                    if cle_classe in occupation_classe or cle_prof in occupation_prof:
                        continue
                    TeacherScheduleSlot.objects.get_or_create(
                        assignment=affectation,
                        day_of_week=jour,
                        start_time=debut,
                        defaults={"end_time": fin},
                    )
                    occupation_classe.add(cle_classe)
                    occupation_prof.add(cle_prof)
                    poses += 1
                    place = True
                    break
                if place:
                    break
        return poses

    def _publier_les_emplois_du_temps(self, classes):
        for classe in classes:
            TimetablePublication.objects.update_or_create(
                classroom=classe,
                defaults={
                    "is_published": True,
                    "is_locked": False,
                    "published_at": timezone.now(),
                },
            )

    # ---------------------------------------------------------------- notes

    def _dresser_le_calendrier_des_compositions(self, annee, classes, matieres):
        """Les trois campagnes et leurs epreuves, notes ou non.

        Le calendrier ne depend pas des copies: une ecole arrete ses dates de
        composition avant d'avoir corrige quoi que ce soit. Il etait pourtant
        dresse dans `_saisir_les_notes`, si bien que `--sans-notes` laissait le
        module des examens entierement vide -- pas de campagne, pas d'epreuve,
        et donc rien a surveiller.

        Rendu ici, il tient seul, et `--sans-notes` ne saute plus que ce que son
        nom annonce.
        """
        par_classe = {}
        for matiere in matieres:
            par_classe.setdefault(matiere.classroom_id, []).append(matiere)

        calendrier = {}
        for classe in classes:
            ses_matieres = par_classe.get(classe.id, [])
            if not ses_matieres:
                continue
            for trimestre in TRIMESTRES:
                session = self._campagne(annee, trimestre)
                calendrier[(classe.id, trimestre)] = (
                    session,
                    {
                        matiere.id: self._epreuve(session, classe, matiere)
                        for matiere in ses_matieres
                    },
                )
        return calendrier

    def _saisir_les_notes(self, annee, classes, matieres, eleves, graine, calendrier):
        """Trois devoirs et une composition, par matiere et par trimestre.

        `Grade.value` se calcule de la moyenne des devoirs: on pose les
        devoirs, le modele fait le reste. La composition vit ailleurs, dans
        `ExamResult`, rattachee a une epreuve du calendrier deja dresse.
        """
        par_classe = {}
        for matiere in matieres:
            par_classe.setdefault(matiere.classroom_id, []).append(matiere)

        eleves_par_classe = {}
        for eleve in eleves:
            eleves_par_classe.setdefault(eleve.classroom_id, []).append(eleve)

        posees = 0
        for classe in classes:
            ses_matieres = par_classe.get(classe.id, [])
            ses_eleves = eleves_par_classe.get(classe.id, [])
            if not ses_matieres or not ses_eleves:
                continue

            for trimestre in TRIMESTRES:
                session, epreuves = calendrier.get(
                    (classe.id, trimestre), (None, {})
                )
                if session is None:
                    continue

                for eleve in ses_eleves:
                    for matiere in ses_matieres:
                        tirage = self._alea(
                            graine, "note", eleve.id, matiere.id, trimestre
                        )
                        devoirs = [
                            float(tirage.randint(9, 19)) for _ in range(3)
                        ]
                        note, cree = Grade.objects.get_or_create(
                            student=eleve,
                            subject=matiere,
                            classroom=classe,
                            academic_year=annee,
                            term=trimestre,
                            defaults={
                                "homework_scores": devoirs,
                                "value": Decimal(
                                    str(round(sum(devoirs) / len(devoirs), 2))
                                ),
                            },
                        )
                        posees += 1 if cree else 0

                        epreuve = epreuves.get(matiere.id)
                        if epreuve is not None:
                            ExamResult.objects.get_or_create(
                                session=session,
                                planning=epreuve,
                                student=eleve,
                                subject=matiere,
                                defaults={
                                    "score": Decimal(str(tirage.randint(9, 19)))
                                },
                            )
        return posees

    def _campagne(self, annee, trimestre):
        rang = TRIMESTRES.index(trimestre)
        debut = annee.start_date + timedelta(days=80 + rang * 90)
        session, _ = ExamSession.objects.get_or_create(
            title=f"Composition du {rang + 1}er trimestre"
            if rang == 0
            else f"Composition du {rang + 1}e trimestre",
            term=trimestre,
            academic_year=annee,
            defaults={"start_date": debut, "end_date": debut + timedelta(days=6)},
        )
        return session

    def _epreuve(self, session, classe, matiere):
        """Une epreuve par matiere et par classe, dans la fenetre de campagne.

        Les horaires s'echelonnent pour qu'une classe ne compose pas deux
        matieres a la meme heure -- le modele le refuse, et il a raison.
        """
        deja = ExamPlanning.objects.filter(
            session=session, classroom=classe, subject=matiere
        ).first()
        if deja is not None:
            return deja

        rang = ExamPlanning.objects.filter(
            session=session, classroom=classe
        ).count()
        jour = session.start_date + timedelta(
            days=rang // len(CRENEAUX_DE_COMPOSITION)
        )
        if jour > session.end_date:
            jour = session.end_date
        debut, fin = CRENEAUX_DE_COMPOSITION[rang % len(CRENEAUX_DE_COMPOSITION)]

        return ExamPlanning.objects.create(
            session=session,
            classroom=classe,
            subject=matiere,
            exam_date=jour,
            start_time=debut,
            end_time=fin,
        )

    # ---------------------------------------------------------------- frais

    def _nommer_l_encadrement(self, etablissement, graine):
        """Le directeur, le censeur, le comptable et le surveillant.

        Sans eux, l'ecole n'a que des eleves, des enseignants et des familles:
        personne ne peut l'ouvrir. Quatre roles sur neuf n'avaient aucun compte
        -- et la double validation de la paie, l'arbitrage d'un incident ou la
        publication d'un bulletin n'avaient personne pour les accomplir.

        Un compte par role et par ecole: c'est ainsi qu'une ecole est dirigee,
        et cela suffit a ce que chaque ecran trouve son titulaire.
        """
        code = self._code_de(etablissement).lower()
        postes = (
            ("dir", UserRole.DIRECTOR, "Directeur"),
            ("cen", UserRole.CENSOR, "Censeur"),
            ("cpt", UserRole.ACCOUNTANT, "Comptable"),
            ("sur", UserRole.SUPERVISOR, "Surveillant"),
            ("pro", UserRole.PROMOTER, "Promoteur"),
        )

        nommes = 0
        for suffixe, role, fonction in postes:
            tirage = self._alea(graine, "encadrement", etablissement.id, suffixe)
            compte, cree = User.objects.get_or_create(
                username=f"{code}.{suffixe}",
                defaults={
                    "first_name": tirage.choice(PRENOMS_GARCONS + PRENOMS_FILLES),
                    "last_name": tirage.choice(NOMS).upper(),
                    "role": role,
                    "etablissement": etablissement,
                    "email": f"{suffixe}@{code}.local",
                },
            )
            compte.set_password("Ecole@2026")
            compte.is_active = True
            compte.etablissement = etablissement
            if not compte.phone:
                compte.phone = self._numero_malien(tirage)
            compte.save(
                update_fields=["password", "is_active", "etablissement", "phone"]
            )
            nommes += 1 if cree else 0
        return nommes

    def _rattacher_les_familles(self, etablissement, eleves, graine):
        """Un parent par fratrie, et des fratries qui existent.

        Sans `ParentProfile`, le role famille n'a rien a montrer: ni « Mes
        enfants », ni bulletin, ni reste a payer. C'est un role entier de
        l'application qui reste vide.

        Les eleves sont groupes par nom de famille, comme dans une ecole: un
        parent a souvent deux enfants dans l'etablissement, et l'ecran
        « Mes enfants » n'a de sens que si certains en ont plusieurs.
        """
        par_nom = {}
        for eleve in eleves:
            if eleve.parent_id is not None:
                continue
            nom = (getattr(eleve.user, "last_name", "") or "").strip().upper()
            par_nom.setdefault(nom or "SANS-NOM", []).append(eleve)

        crees = 0
        for rang, (nom, fratrie) in enumerate(sorted(par_nom.items()), start=1):
            # Une fratrie par tranche de trois: au-dela, ce sont des homonymes.
            for groupe_rang, groupe in enumerate(
                self._repartir(fratrie, maximum=3), start=1
            ):
                tirage = self._alea(graine, "parent", etablissement.id, nom, groupe_rang)
                prenom = tirage.choice(PRENOMS_GARCONS + PRENOMS_FILLES)
                identifiant = (
                    f"{self._code_de(etablissement).lower()}.par{rang:03d}{groupe_rang}"
                )

                compte, _ = User.objects.get_or_create(
                    username=identifiant,
                    defaults={
                        "first_name": prenom,
                        "last_name": nom,
                        "role": UserRole.PARENT,
                        "etablissement": etablissement,
                    },
                )
                compte.set_password("Parent@2026")
                compte.is_active = True
                compte.etablissement = etablissement
                if not compte.phone:
                    compte.phone = self._numero_malien(tirage)
                compte.save(
                    update_fields=["password", "is_active", "etablissement", "phone"]
                )

                famille, cree = ParentProfile.objects.get_or_create(
                    user=compte,
                    defaults={
                        "etablissement": etablissement,
                        "profession": tirage.choice(
                            ["Commerçant", "Enseignant", "Agriculteur",
                             "Fonctionnaire", "Artisan", "Infirmier"]
                        ),
                    },
                )
                crees += 1 if cree else 0

                for eleve in groupe:
                    if eleve.parent_id is None:
                        eleve.parent = famille
                        eleve.save(update_fields=["parent"])
        return crees

    def _faire_l_appel(self, annee, classes, eleves, graine):
        """Vingt jours d'appel, absences et retards compris.

        Un registre d'absences vide ne montre ni le taux d'assiduite du
        tableau de bord, ni la feuille d'appel, ni les justificatifs. Vingt
        jours suffisent a faire apparaitre des habitudes -- un eleve qui
        arrive souvent en retard se voit.
        """
        jours = self._jours_ouvres(20)
        par_classe = {}
        for eleve in eleves:
            par_classe.setdefault(eleve.classroom_id, []).append(eleve)

        journees = 0
        for classe in classes:
            ses_eleves = par_classe.get(classe.id, [])
            if not ses_eleves:
                continue
            for jour in jours:
                for eleve in ses_eleves:
                    tirage = self._alea(
                        graine, "appel", eleve.id, jour.isoformat()
                    )
                    absent = tirage.random() < 0.04
                    retard = (not absent) and tirage.random() < 0.08
                    if not absent and not retard:
                        continue
                    Attendance.objects.get_or_create(
                        student=eleve,
                        date=jour,
                        defaults={
                            "academic_year": annee,
                            "is_absent": absent,
                            "is_late": retard,
                            "reason": tirage.choice(MOTIFS) if absent else "",
                        },
                    )
                # La feuille se valide et se verrouille, comme le surveillant
                # le fait chaque soir.
                _, cree = AttendanceSheetValidation.objects.get_or_create(
                    classroom=classe,
                    date=jour,
                    defaults={"is_locked": True, "validated_at": timezone.now()},
                )
                journees += 1 if cree else 0
        return journees

    def _pointer_les_enseignants(self, annee, enseignants, graine):
        """L'emargement des enseignants, qui alimente la paie."""
        jours = self._jours_ouvres(20)
        poses = 0
        for enseignant in enseignants:
            for jour in jours:
                tirage = self._alea(
                    graine, "pointage", enseignant.id, jour.isoformat()
                )
                absent = tirage.random() < 0.03
                retard = (not absent) and tirage.random() < 0.10
                _, cree = TeacherAttendance.objects.get_or_create(
                    teacher=enseignant,
                    date=jour,
                    defaults={
                        "academic_year": annee,
                        "is_absent": absent,
                        "is_late": retard,
                        "reason": tirage.choice(MOTIFS) if (absent or retard) else "",
                    },
                )
                poses += 1 if cree else 0
        return poses

    def _consigner_la_discipline(self, annee, eleves, graine):
        """Des incidents, de gravites et d'etats varies -- et leur consequence.

        Dont certains non encore traites, et un dont la famille n'a pas ete
        prevenue: c'est ce que l'ecran met en avant, et il faut donc que cela
        existe.

        La note de conduite suit la gravite. Elle restait a 18 pour tout le
        monde, y compris pour un eleve pris a tricher: l'incident etait consigne
        et sans consequence, le bulletin l'ignorait, et le conseil de fin
        d'annee promouvait toute l'ecole sans un redoublant.
        """
        # Ce qu'un incident coute sur vingt. Un eleve exclu pour conduite passe
        # sous le seuil du conseil de classe, ce qui est le but: une sanction
        # qui ne se lit nulle part n'est pas une sanction.
        retrait = {"low": Decimal("1"), "medium": Decimal("3"), "high": Decimal("9")}

        crees = 0
        for eleve in eleves:
            tirage = self._alea(graine, "discipline", eleve.id)
            if tirage.random() > 0.08:
                continue
            categorie, gravite, description = tirage.choice(MOTIFS_DE_DISCIPLINE)
            traite = tirage.random() < 0.6
            _, cree = DisciplineIncident.objects.get_or_create(
                student=eleve,
                incident_date=timezone.localdate() - timedelta(
                    days=tirage.randint(1, 60)
                ),
                category=categorie,
                defaults={
                    "academic_year": annee,
                    "description": description,
                    "severity": gravite,
                    "sanction": "Avertissement écrit." if traite else "",
                    "status": "resolved" if traite else "open",
                    "parent_notified": traite and tirage.random() < 0.8,
                    "resolved_at": timezone.now() if traite else None,
                },
            )
            crees += 1 if cree else 0

            # `update_or_create` plutot qu'un decrement: relancee, la commande
            # ne doit pas creuser la note un peu plus a chaque passage.
            voulue = max(Decimal("0"), Decimal("18") - retrait[gravite])
            if eleve.conduite != voulue:
                eleve.conduite = voulue
                eleve.save(update_fields=["conduite"])
        return crees

    def _arreter_les_bulletins(self, annee, classes):
        """Valider les notes, puis ouvrir les bulletins aux familles.

        Sans validation, les notes restent modifiables et le bulletin n'est pas
        arrete; sans publication, la famille ne voit rien -- c'est l'embargo,
        et il fonctionne. Les deux premiers trimestres sont arretes, le
        troisieme reste ouvert: une annee en cours, pas une annee close.
        """
        arretes = 0
        for classe in classes:
            for trimestre in TRIMESTRES[:2]:
                _, cree = GradeValidation.objects.get_or_create(
                    classroom=classe,
                    academic_year=annee,
                    term=trimestre,
                    defaults={
                        "is_validated": True,
                        "validated_at": timezone.now(),
                    },
                )
                arretes += 1 if cree else 0
                BulletinPublication.objects.get_or_create(
                    classroom=classe,
                    academic_year=annee,
                    term=trimestre,
                    defaults={"is_published": True},
                )
        return arretes

    def _affecter_les_surveillants(self, classes, enseignants, graine):
        """Un surveillant par epreuve, sauf quelques-unes laissees vacantes.

        L'onglet « Surveillance » met en tete les epreuves **sans** surveillant:
        c'est la seule question qu'on se pose la veille des compositions. Les
        couvrir toutes rendrait cet ecran muet.
        """
        if not enseignants:
            return 0

        posees = 0
        epreuves = list(
            ExamPlanning.objects.filter(classroom__in=classes).order_by("id")
        )
        occupes = set()
        for rang, epreuve in enumerate(epreuves):
            if rang % 7 == 3:
                continue  # une epreuve sur sept reste a pourvoir
            tirage = self._alea(graine, "surveillance", epreuve.id)
            for enseignant in tirage.sample(enseignants, len(enseignants)):
                cle = (enseignant.user_id, epreuve.exam_date, epreuve.start_time)
                if cle in occupes:
                    continue
                _, cree = ExamInvigilation.objects.get_or_create(
                    planning=epreuve, supervisor=enseignant.user
                )
                occupes.add(cle)
                posees += 1 if cree else 0
                break
        return posees

    def _ouvrir_les_disponibilites(self, etablissement, annee, enseignants, graine):
        """Une collecte ouverte, avec des reponses partielles.

        Partielles a dessein: l'ecran affiche un taux de reponse et la liste de
        ceux qui n'ont pas repondu. Une campagne ou tout le monde a repondu ne
        montre pas ce qu'il sait faire.
        """
        aujourdhui = timezone.localdate()
        campagne, _ = AvailabilityCampaign.objects.get_or_create(
            etablissement=etablissement,
            academic_year=annee,
            status="open",
            defaults={
                "label": "Collecte des disponibilités — rentrée",
                "opens_on": aujourdhui - timedelta(days=5),
                "closes_on": aujourdhui + timedelta(days=10),
                "instructions": (
                    "Déclarez vos créneaux préférés et ceux que vous ne pouvez "
                    "pas assurer. La direction arbitre ensuite."
                ),
            },
        )

        poses = 0
        for rang, enseignant in enumerate(enseignants):
            if rang % 3 == 2:
                continue  # un enseignant sur trois n'a pas encore repondu
            tirage = self._alea(graine, "dispo", enseignant.id)
            for jour in sorted(tirage.sample(JOURS, 3)):
                debut, fin = tirage.choice(CRENEAUX)
                genre = tirage.choice(["preferred", "possible", "unavailable"])
                _, cree = TeacherAvailabilitySlot.objects.get_or_create(
                    teacher=enseignant,
                    campaign=campagne,
                    day_of_week=jour,
                    start_time=debut,
                    defaults={
                        "etablissement": etablissement,
                        "end_time": fin,
                        "kind": genre,
                        "note": "Cours dans un autre établissement"
                        if genre == "unavailable"
                        else "",
                    },
                )
                poses += 1 if cree else 0
        return poses

    def _preparer_la_paie(self, etablissement, annee, enseignants):
        """Des fiches du mois, non validees.

        Le censeur vise au niveau un, le comptable au niveau deux. C'est la
        regle la plus difficile a expliquer et la plus convaincante a montrer --
        encore faut-il qu'il y ait quelque chose a viser.
        """
        premier = timezone.localdate().replace(day=1)
        crees = 0
        for enseignant in enseignants:
            heures = TeacherScheduleSlot.objects.filter(
                assignment__teacher=enseignant
            ).count()
            _, cree = TeacherPayroll.objects.get_or_create(
                teacher=enseignant,
                month=premier,
                defaults={
                    "academic_year": annee,
                    "hours_attributed": Decimal(heures * 4),
                    "hours_worked": Decimal(max(0, heures * 4 - 2)),
                    "hours_missed": Decimal(2),
                    "hourly_rate": enseignant.hourly_rate,
                    "amount": enseignant.salary_base,
                },
            )
            crees += 1 if cree else 0
        return crees

    def _engager_des_depenses(self, etablissement, annee):
        """Trois mois de depenses, dont une qui attend encore son visa."""
        aujourdhui = timezone.localdate()
        lignes = (
            ("Craie et fournitures de classe", 45000, "Fournitures", True),
            ("Réparation du groupe électrogène", 180000, "Entretien", True),
            ("Carburant du mois", 95000, "Transport", False),
            ("Papeterie et registres", 62000, "Fournitures", True),
        )
        crees = 0
        for rang, (libelle, montant, categorie, payee) in enumerate(lignes):
            _, cree = Expense.objects.get_or_create(
                label=libelle,
                date=aujourdhui - timedelta(days=30 * rang + 3),
                etablissement=etablissement,
                defaults={
                    "amount": Decimal(montant),
                    "academic_year": annee,
                    "category": categorie,
                    "notes": "" if payee else "En attente de validation.",
                    "paid_on": aujourdhui - timedelta(days=30 * rang)
                    if payee
                    else None,
                },
            )
            crees += 1 if cree else 0
        return crees

    def _animer_la_vie_scolaire(self, etablissement, eleves, graine):
        """Bibliotheque, cantine et stock: les trois registres du quotidien.

        Des emprunts en retard, des repas impayes et un article sous son seuil:
        chacun de ces ecrans a une alerte a montrer, et elle n'a de sens que
        s'il existe un cas qui la declenche.
        """
        aujourdhui = timezone.localdate()
        total = 0

        catalogue = (
            ("Le Devoir de violence", "Yambo Ouologuem", "Roman", 6),
            ("Mathématiques 3e — Collection Afrique", "Collectif", "Mathématiques", 15),
            ("Histoire du Mali médiéval", "Madina Ly-Tall", "Histoire", 8),
            ("Physique-Chimie 2nde", "Collectif", "Sciences", 10),
            ("L'Étrange Destin de Wangrin", "Amadou Hampâté Bâ", "Roman", 7),
        )
        ouvrages = []
        for titre, auteur, matiere, quantite in catalogue:
            # L'ISBN passe par `_alea` et non par `hash()`: Python randomise le
            # `hash()` d'une chaine a chaque processus, et la commande promet le
            # contraire -- meme graine, meme ecole, jusqu'au numero d'ouvrage.
            tirage = self._alea(graine, "isbn", titre)
            ouvrage, cree = Book.objects.get_or_create(
                title=titre,
                etablissement=etablissement,
                defaults={
                    "author": auteur,
                    "isbn": f"978-{tirage.randrange(1000000):06d}",
                    "subject": matiere,
                    "shelf_location": f"R{len(titre) % 5 + 1}",
                    "quantity_total": quantite,
                    "quantity_available": quantite,
                },
            )
            ouvrages.append(ouvrage)
            total += 1 if cree else 0

        emprunteurs = self._un_echantillon(eleves, 12)
        for rang, eleve in enumerate(emprunteurs):
            ouvrage = ouvrages[rang % len(ouvrages)]
            en_retard = rang % 3 == 1
            _, cree = Borrow.objects.get_or_create(
                student=eleve,
                book=ouvrage,
                borrowed_at=aujourdhui - timedelta(days=25 if en_retard else 6),
                defaults={
                    "due_date": aujourdhui - timedelta(days=8)
                    if en_retard
                    else aujourdhui + timedelta(days=8),
                },
            )
            total += 1 if cree else 0
        # `quantity_available` est derive, jamais saisi: sans ce recalcul, les
        # douze emprunts n'entament pas le stock affiche.
        for ouvrage in ouvrages:
            ouvrage.recalculer_disponibilite()

        menus = []
        for rang, (nom, prix) in enumerate(
            (("Riz au gras", 500), ("Tô sauce arachide", 400), ("Riz sauce feuille", 450))
        ):
            menu, cree = CanteenMenu.objects.get_or_create(
                menu_date=aujourdhui - timedelta(days=rang),
                etablissement=etablissement,
                name=nom,
                defaults={"unit_price": Decimal(prix), "is_active": True},
            )
            menus.append(menu)
            total += 1 if cree else 0

        for eleve in self._un_echantillon(eleves, 40):
            menu = menus[eleve.id % len(menus)]
            _, cree = CanteenService.objects.get_or_create(
                student=eleve,
                menu=menu,
                served_on=menu.menu_date,
                defaults={"is_paid": eleve.id % 4 != 0},
            )
            total += 1 if cree else 0

        fournisseur, cree = Supplier.objects.get_or_create(
            name="Librairie du Fleuve",
            etablissement=etablissement,
            defaults={"phone": "76 00 00 00", "email": "contact@fleuve.ml"},
        )
        total += 1 if cree else 0

        articles = (
            ("Craie blanche (boîte)", 40, 10, "boîte"),
            ("Ramette A4", 6, 8, "ramette"),  # sous le seuil: l'alerte se voit
            ("Registre d'appel", 25, 5, "unité"),
            ("Marqueur tableau", 18, 6, "unité"),
        )
        for nom, quantite, seuil, unite in articles:
            article, cree = StockItem.objects.get_or_create(
                name=nom,
                etablissement=etablissement,
                defaults={
                    "quantity": quantite,
                    "minimum_threshold": seuil,
                    "unit": unite,
                    "supplier": fournisseur,
                },
            )
            total += 1 if cree else 0
            # `StockMovementType.IN` vaut « in » en minuscules: un « IN » ecrit
            # a la main n'est ni une entree ni une sortie, et le recalcul de
            # `StockItem.quantite` ramenait alors tous les articles a zero --
            # quatre alertes de seuil au lieu d'une.
            StockMovement.objects.get_or_create(
                item=article,
                movement_type=StockMovementType.IN,
                quantity=quantite,
                defaults={"reason": "Approvisionnement de rentrée"},
            )
        return total

    def _ouvrir_la_communication(self, etablissement, enseignants, eleves):
        """Une annonce par public, et un fil ou l'on se parle.

        Les quatre publics existent depuis que le champ a cesse d'etre libre;
        une demonstration qui n'en montre qu'un ne montre pas la regle.
        """
        directeur = (
            User.objects.filter(
                etablissement=etablissement, role=UserRole.DIRECTOR
            ).first()
            or User.objects.filter(role=UserRole.SUPER_ADMIN).first()
        )

        total = 0
        for public, titre, message in (
            ("all", "Rentrée des classes le 1er octobre", "Les cours reprennent lundi à 8h."),
            ("families", "Réunion de parents samedi", "Rendez-vous à 9h dans la cour."),
            ("teachers", "Remise des copies avant vendredi", "Dépôt au secrétariat."),
            ("staff", "Inventaire de la caisse lundi", "Présence de la comptabilité requise."),
        ):
            _, cree = Announcement.objects.get_or_create(
                etablissement=etablissement,
                title=titre,
                defaults={"message": message, "audience": public, "author": directeur},
            )
            total += 1 if cree else 0

        # Une notification qui attend encore de partir: l'onglet « En attente
        # d'envoi » a besoin d'une ligne pour dire ce qu'il sait dire.
        famille = User.objects.filter(
            etablissement=etablissement, role=UserRole.PARENT
        ).first()
        if famille is not None:
            _, cree = Notification.objects.get_or_create(
                etablissement=etablissement,
                recipient=famille,
                title="Bulletin du premier trimestre disponible",
                defaults={
                    "channel": "sms",
                    "message": "Le bulletin est consultable dans votre espace.",
                    "is_sent": False,
                },
            )
            total += 1 if cree else 0

        if directeur is not None and enseignants:
            groupe, _ = Conversation.objects.get_or_create(
                etablissement=etablissement,
                title="Équipe pédagogique",
                defaults={"is_group": True},
            )
            ConversationParticipant.objects.get_or_create(
                conversation=groupe, user=directeur, defaults={"is_admin": True}
            )
            for enseignant in enseignants[:5]:
                ConversationParticipant.objects.get_or_create(
                    conversation=groupe, user=enseignant.user
                )
            premier, cree = ChatMessage.objects.get_or_create(
                conversation=groupe,
                sender=directeur,
                content="Conseil de classe jeudi à 16h, salle des professeurs.",
            )
            total += 1 if cree else 0
            _, cree = ChatMessage.objects.get_or_create(
                conversation=groupe,
                sender=enseignants[0].user,
                content="Bien noté, j'apporte les relevés.",
                defaults={"reply_to": premier},
            )
            total += 1 if cree else 0
        return total

    def _archiver_les_bilans(self, annee, classes):
        """Le rang et la moyenne de chaque trimestre, figes.

        `StudentAcademicHistory` est ce qui fait qu'un bulletin du premier
        trimestre reimprime en juin porte toujours le rang de decembre. Sans ces
        lignes, l'historique d'un eleve est vide et le rang s'affiche « - ».

        Le calcul n'est pas refait ici: `recalculate_term_ranking` est la regle
        du depot, conduite et composition comprises. En dupliquer une variante
        donnerait des rangs qui divergent de ceux des bulletins.
        """
        archives = 0
        for classe in classes:
            for trimestre in TRIMESTRES:
                recalculate_term_ranking(classe, annee, trimestre)
                archives += StudentAcademicHistory.objects.filter(
                    classroom=classe, academic_year=annee, term=trimestre
                ).count()
        return archives

    def _emarger_les_arrivees(self, etablissement, enseignants, graine):
        """L'heure d'arrivee et de depart, quinze jours durant.

        `TeacherAttendance` dit si une seance a ete assuree; `TeacherTimeEntry`
        dit a quelle heure l'enseignant est arrive. Ce sont deux ecrans
        differents, et seul le premier etait peuple: la feuille d'emargement
        restait vide, retards compris.

        Des retards, il en faut: la tolerance de l'etablissement ne se voit que
        sur quelqu'un qui arrive en retard sans etre compte en retard.
        """
        tolerance = getattr(etablissement, "timesheet_late_tolerance_minutes", 0) or 0
        poses = 0
        for jour in self._jours_ouvres(15):
            for enseignant in enseignants:
                tirage = self._alea(graine, "emargement", enseignant.id, jour)
                if tirage.random() < 0.15:
                    continue  # absent ce jour-la: la feuille porte le manque

                retard = tirage.choice([0, 0, 0, 4, 9, 17, 25])
                arrivee = (
                    datetime.combine(jour, time(8, 0)) + timedelta(minutes=retard)
                ).time()
                depart = time(17, 0) if tirage.random() < 0.8 else None
                heures = Decimal("8.00") if depart else Decimal("0.00")
                _, cree = TeacherTimeEntry.objects.get_or_create(
                    teacher=enseignant,
                    entry_date=jour,
                    defaults={
                        "etablissement": etablissement,
                        "check_in_time": arrivee,
                        "check_out_time": depart,
                        # Le retard retenu est celui qui depasse la tolerance:
                        # c'est la regle de l'etablissement, pas l'ecart brut.
                        "late_minutes": max(0, retard - tolerance),
                        "tolerated_late_minutes": min(retard, tolerance),
                        "worked_hours": heures,
                        "planned_minutes": 480,
                        "covered_minutes": 480 if depart else 0,
                        "is_auto_closed": depart is None,
                        "auto_closed_reason": ""
                        if depart
                        else "Sortie non pointée, journée clôturée automatiquement.",
                        "notes": "",
                    },
                )
                poses += 1 if cree else 0
        return poses

    def _remettre_les_bulletins(self, etablissement, annee, eleves, graine):
        """Les bulletins du premier trimestre, envoyes aux familles.

        Les quatre etats existent a dessein: prepare, envoye, consulte, echoue.
        L'ecran de remise est fait pour les distinguer -- et le motif d'echec ne
        s'affiche que s'il y a un echec. Un numero invalide est le cas reel le
        plus frequent.
        """
        directeur = User.objects.filter(
            etablissement=etablissement, role=UserRole.DIRECTOR
        ).first()

        remises = 0
        for eleve in self._un_echantillon(eleves, 60):
            # `BulletinDelivery.parent` pointe la fiche de famille, pas le
            # compte: c'est la famille qui recoit le bulletin, et elle porte son
            # propre numero WhatsApp.
            parent = eleve.parent
            if parent is None:
                continue
            tirage = self._alea(graine, "remise", eleve.id)
            etat = tirage.choice(["sent", "read", "read", "prepared", "failed"])
            envoye = timezone.now() - timedelta(days=tirage.randint(1, 20))
            _, cree = BulletinDelivery.objects.get_or_create(
                student=eleve,
                academic_year=annee,
                term="T1",
                defaults={
                    "etablissement": etablissement,
                    "parent": parent,
                    "channel": "manual_link",
                    "status": etat,
                    "phone": parent.whatsapp_phone or parent.user.phone or "",
                    "sent_at": None if etat == "prepared" else envoye,
                    "read_at": envoye + timedelta(hours=3)
                    if etat == "read"
                    else None,
                    "failure_reason": "Numéro injoignable"
                    if etat == "failed"
                    else "",
                    "prepared_by": directeur,
                },
            )
            remises += 1 if cree else 0
        return remises

    def _abonner_a_la_cantine(self, annee, eleves):
        """Des abonnements a l'annee, dont un suspendu et un termine.

        Le service quotidien etait peuple, l'abonnement non: l'ecran listait des
        repas servis sans jamais dire qui est abonne, ni qui ne l'est plus.
        """
        poses = 0
        for rang, eleve in enumerate(self._un_echantillon(eleves, 45)):
            etat = "active"
            if rang % 15 == 7:
                etat = "suspended"
            elif rang % 15 == 11:
                etat = "ended"
            _, cree = CanteenSubscription.objects.get_or_create(
                student=eleve,
                academic_year=annee,
                defaults={
                    "start_date": annee.start_date,
                    "end_date": annee.start_date + timedelta(days=120)
                    if etat == "ended"
                    else None,
                    "daily_limit": 1,
                    "status": etat,
                },
            )
            poses += 1 if cree else 0
        return poses

    def _ouvrir_la_bibliotheque_numerique(self, etablissement):
        """Un fonds classe en collections et categories, avec des documents.

        Trois niveaux, et il faut les trois: sans collection pas de categorie,
        sans categorie pas de document. L'ecran s'ouvrait donc sur un arbre vide.

        Un document en erreur d'import est prevu: c'est le seul cas ou la
        colonne « motif » a quelque chose a dire.
        """
        code = self._code_de(etablissement).lower()
        total = 0

        arbre = (
            ("manuels", "Manuels scolaires", (
                ("Mathématiques", ("Algèbre 10ème", "Géométrie 11ème")),
                ("Sciences", ("Physique-Chimie 2nde", "Biologie 1ère")),
            )),
            ("annales", "Annales du baccalauréat", (
                ("Séries techniques", ("Annales CT 2024", "Annales GM 2024")),
            )),
        )

        for rang, (cle, libelle, categories) in enumerate(arbre):
            # Le code est unique par etablissement: il porte donc le sigle de
            # l'ecole, sans quoi la deuxieme ecole montee echouerait.
            collection, cree = LibraryCollection.objects.get_or_create(
                etablissement=etablissement,
                code=f"{code}-{cle}",
                defaults={"label": libelle, "position": rang},
            )
            total += 1 if cree else 0

            for position, (nom, titres) in enumerate(categories):
                categorie, cree = LibraryCategory.objects.get_or_create(
                    collection=collection,
                    name=nom,
                    defaults={"position": position},
                )
                total += 1 if cree else 0

                for index, titre in enumerate(titres):
                    rate = index == 0 and cle == "annales"
                    _, cree = LibraryDocument.objects.get_or_create(
                        category=categorie,
                        title=titre,
                        defaults={
                            "etablissement": etablissement,
                            "origin": "import",
                            # `source_url` est unique des qu'il n'est pas vide:
                            # il porte donc le sigle de l'ecole.
                            "source_url": (
                                f"https://fonds.example.org/{code}/{cle}/"
                                f"{position}-{index}.pdf"
                            ),
                            "size_bytes": 1_200_000 + index * 40_000,
                            "is_downloaded": not rate,
                            "import_error": "Fichier introuvable à la source"
                            if rate
                            else "",
                            "description": "",
                        },
                    )
                    total += 1 if cree else 0

        # Le fournisseur de SMS: sans lui, l'ecran des envois dit seulement
        # qu'aucun fournisseur n'est configure, et rien d'autre.
        _, cree = SmsProviderConfig.objects.get_or_create(
            etablissement=etablissement,
            defaults={
                "provider_name": "Passerelle de démonstration",
                "api_url": "https://sms.example.org/api/v1/send",
                # Jeton manifestement faux: cette commande ne doit jamais
                # deposer en base quelque chose qui ressemble a un secret.
                "api_token": "jeton-de-demonstration-a-remplacer",
                "sender_id": self._code_de(etablissement),
                "is_active": False,
            },
        )
        total += 1 if cree else 0
        return total

    def _simuler_le_passage(self, etablissement, annee, classes):
        """Le conseil de fin d'annee, simule et non execute.

        La nuance est tout: une execution deplacerait les mille deux cents
        eleves dans les classes de l'annee suivante et defirait tout ce qui
        precede. Une simulation montre le meme ecran -- effectifs, promus,
        redoublants -- et ne touche a rien.

        La classe cible se deduit du nom quand elle existe (« 10eme CT » vers
        « 11eme CT »), et reste vide sinon: mieux vaut une cible absente qu'une
        cible fausse.
        """
        directeur = User.objects.filter(
            etablissement=etablissement, role=UserRole.DIRECTOR
        ).first()
        seuil = Decimal("10")
        seuil_conduite = Decimal("10")

        par_nom = {classe.name: classe for classe in classes}
        cibles = {}
        for classe in classes:
            correspondance = re.match(r"^(\d+)(.*)$", classe.name.strip())
            if correspondance is None:
                continue
            suivant = (
                f"{int(correspondance.group(1)) + 1}{correspondance.group(2)}"
            )
            cibles[classe.id] = par_nom.get(suivant)

        lignes = []
        for classe in classes:
            bilans = StudentAcademicHistory.objects.filter(
                classroom=classe, academic_year=annee, term="T3"
            ).select_related("student")
            for bilan in bilans:
                conduite = bilan.student.conduite
                # Les deux seuils du conseil de classe, et non le seul premier:
                # avec des notes entre 9 et 19, la moyenne seule promeut toute
                # l'ecole. C'est la conduite qui fait un redoublant, et c'est
                # aussi ce qui donne un sens a un incident consigne.
                if conduite < seuil_conduite:
                    motif = f"Conduite inférieure à {seuil_conduite}"
                elif bilan.average < seuil:
                    motif = f"Moyenne annuelle inférieure à {seuil}"
                else:
                    motif = ""
                promu = motif == ""
                lignes.append(
                    {
                        "eleve": bilan.student,
                        "source": classe,
                        "cible": cibles.get(classe.id) if promu else classe,
                        "decision": PromotionDecisionType.PROMOTED
                        if promu
                        else PromotionDecisionType.REPEATED,
                        "moyenne": bilan.average,
                        "conduite": conduite,
                        "rang": bilan.rank,
                        "motif": motif,
                    }
                )

        if not lignes:
            return 0

        promus = sum(
            1 for l in lignes if l["decision"] == PromotionDecisionType.PROMOTED
        )
        simulation, _ = PromotionRun.objects.get_or_create(
            etablissement=etablissement,
            source_academic_year=annee,
            status=PromotionRunStatus.SIMULATED,
            defaults={
                # Pas d'annee cible: l'ecole simule en juin, avant de l'ouvrir.
                "target_academic_year": None,
                "min_average": seuil,
                "min_conduite": Decimal("10"),
                "executed_by": directeur,
                "total_students": len(lignes),
                "promoted_count": promus,
                "repeated_count": len(lignes) - promus,
                "archived_count": 0,
                "payload": {
                    "source_classrooms": [classe.id for classe in classes],
                    "classroom_mapping": {
                        str(source): (cible.id if cible else None)
                        for source, cible in cibles.items()
                    },
                },
            },
        )

        posees = 0
        for ligne in lignes:
            _, cree = PromotionDecision.objects.get_or_create(
                run=simulation,
                student=ligne["eleve"],
                defaults={
                    "source_classroom": ligne["source"],
                    "target_classroom": ligne["cible"],
                    "decision": ligne["decision"],
                    "average": ligne["moyenne"],
                    "average_matieres": ligne["moyenne"],
                    "conduite": ligne["conduite"],
                    "rank": ligne["rang"],
                    "reason": ligne["motif"],
                },
            )
            posees += 1 if cree else 0
        return posees

    @staticmethod
    def _jours_ouvres(combien):
        jours, jour = [], timezone.localdate()
        while len(jours) < combien:
            if jour.weekday() < 5:
                jours.append(jour)
            jour -= timedelta(days=1)
        return jours

    def _poser_les_baremes(self, etablissement, annee, classes, options):
        """Un bareme par classe, que l'ecole pourra ensuite modifier.

        Les montants ne sont pas ecrits dans le code: `FeeSchedule` existe pour
        cela, et l'ecran « Finances > Baremes de frais » les edite classe par
        classe. Cette commande ne fait que poser un point de depart, et les
        frais des eleves en decoulent -- changer un bareme et le reappliquer
        suffit donc a corriger toute une classe, sans repasser par ici.
        """
        inscription = Decimal(str(options["frais_inscription"]))
        mensualite = Decimal(str(options["frais_mensuel"]))
        versements = options["mensualites"]

        poses = 0
        for classe in classes:
            _, cree = FeeSchedule.objects.get_or_create(
                etablissement=etablissement,
                academic_year=annee,
                classroom=classe,
                fee_type=FeeType.REGISTRATION,
                label="Inscription",
                defaults={
                    "amount": inscription,
                    "first_due_date": annee.start_date + timedelta(days=15),
                    "occurrences": 1,
                },
            )
            poses += 1 if cree else 0

            _, cree = FeeSchedule.objects.get_or_create(
                etablissement=etablissement,
                academic_year=annee,
                classroom=classe,
                fee_type=FeeType.MONTHLY,
                label="Scolarité mensuelle",
                defaults={
                    "amount": mensualite,
                    "first_due_date": annee.start_date + timedelta(days=30),
                    "occurrences": versements,
                },
            )
            poses += 1 if cree else 0
        return poses

    def _facturer_la_scolarite(self, etablissement, annee, eleves, part_due, graine):
        """Les frais viennent des baremes, les reglements de la caisse.

        L'inscription est reglee par tous -- c'est la condition pour etre
        inscrit. La scolarite est soldee par trois eleves sur quatre; le
        quatrieme s'arrete en cours d'annee, ce qui est ainsi qu'un impaye se
        constitue, pas par un refus net.

        Une ecole ou tout est paye ne montre ni relance ni reste a payer; une
        ecole ou rien ne l'est ne montre pas de caisse.
        """
        # Les frais decoulent des baremes: `appliquer()` ne cree que ce qui
        # manque, et sait deja quels eleves sont concernes.
        for bareme in FeeSchedule.objects.filter(
            etablissement=etablissement, academic_year=annee
        ):
            bareme.appliquer()

        emis = StudentFee.objects.filter(
            student__in=eleves, academic_year=annee
        ).count()

        # Un tirage par eleve donnait vingt-huit pour cent la ou l'on en
        # demandait vingt-cinq: sur cent cinquante eleves, le hasard derive.
        # On designe donc une part exacte, en melangeant de facon reproductible.
        ordonnes = sorted(
            eleves,
            key=lambda e: self._alea(graine, "ordre", e.id).random(),
        )
        # Division entiere, et non `round()`: celui de Python arrondit au pair
        # le plus proche, si bien que 37,5 montait a 38 quand 112,5 descendait a
        # 112. Deux ecoles obtenaient des regles differentes sans que rien ne le
        # dise. La part demandee est desormais un plafond: jamais plus d'un
        # quart d'impayes quand on demande vingt-cinq pour cent.
        combien = len(ordonnes) * part_due // 100
        retardataires = {e.id for e in ordonnes[:combien]}

        regles = 0
        for eleve in eleves:
            en_retard = eleve.id in retardataires
            frais = list(
                StudentFee.objects.filter(
                    student=eleve, academic_year=annee
                ).order_by("fee_type", "due_date")
            )
            mensuels = [f for f in frais if f.fee_type == FeeType.MONTHLY]
            derniers = {f.id for f in mensuels[-3:]} if en_retard else set()

            for rang, frais_du in enumerate(frais):
                # L'inscription se paie toujours; la scolarite se paie sauf
                # pour les derniers mois des retardataires.
                if frais_du.id in derniers:
                    continue
                _, cree = Payment.objects.get_or_create(
                    fee=frais_du,
                    reference=f"REG-{eleve.id:06d}-{rang:02d}",
                    defaults={
                        "amount": frais_du.amount_due,
                        "method": "cash",
                        "etablissement": etablissement,
                    },
                )
                regles += 1 if cree else 0

        return emis
