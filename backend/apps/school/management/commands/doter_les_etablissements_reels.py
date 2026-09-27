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
from datetime import date, time, timedelta
from decimal import Decimal

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.utils import timezone

from apps.accounts.models import User, UserRole
from apps.school.models import (
    AcademicYear,
    ClassRoom,
    Etablissement,
    ExamPlanning,
    ExamResult,
    ExamSession,
    FeeSchedule,
    FeeType,
    Grade,
    Payment,
    Student,
    StudentFee,
    Subject,
    Teacher,
    TeacherAssignment,
    TeacherScheduleSlot,
    TimetablePublication,
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
        """Les classes prevues pour cette ecole, par son nom ou ses alias."""
        nom = etablissement.name.strip().lower()
        for cle, valeur in listes.items():
            noms = [cle] + list(valeur.get("aliases", []))
            for candidat in noms:
                c = candidat.strip().lower()
                if c == nom or c in nom or nom in c:
                    return valeur["classes"]
        return None

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

        notes = 0
        if not options["sans_notes"]:
            notes = self._saisir_les_notes(annee, classes, matieres, eleves, graine)

        baremes = self._poser_les_baremes(etablissement, annee, classes, options)
        frais = self._facturer_la_scolarite(
            etablissement, annee, eleves, options["part_non_soldee"], graine
        )

        self.stdout.write(f"  classes              {len(classes)}")
        self.stdout.write(f"  matieres             {len(matieres)}")
        self.stdout.write(f"  eleves               {len(eleves)}")
        self.stdout.write(f"  enseignants          {len(enseignants)}")
        self.stdout.write(f"  creneaux d'horaire   {creneaux}")
        self.stdout.write(f"  notes saisies        {notes}")
        self.stdout.write(f"  baremes de frais     {baremes}")
        self.stdout.write(f"  frais emis           {frais}")

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
                compte.save(update_fields=["password", "is_active", "etablissement"])

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

        for slot in TeacherScheduleSlot.objects.select_related(
            "assignment"
        ).filter(assignment__classroom__in=classes):
            occupation_classe.add(
                (slot.assignment.classroom_id, slot.day_of_week, slot.start_time)
            )
            occupation_prof.add(
                (slot.assignment.teacher_id, slot.day_of_week, slot.start_time)
            )

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

            places = 0
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

    def _saisir_les_notes(self, annee, classes, matieres, eleves, graine):
        """Trois devoirs et une composition, par matiere et par trimestre.

        `Grade.value` se calcule de la moyenne des devoirs: on pose les
        devoirs, le modele fait le reste. La composition vit ailleurs, dans
        `ExamResult`, rattachee a une epreuve -- c'est ce que le module des
        examens attend depuis qu'une note porte son epreuve.
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
                session = self._campagne(annee, trimestre)
                epreuves = {
                    matiere.id: self._epreuve(session, classe, matiere)
                    for matiere in ses_matieres
                }

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
        combien = round(len(ordonnes) * part_due / 100)
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
