"""Ce que les commandes de peuplement ne creent pas, et que les ecrans montrent.

`seed_demo_data` puis `seed_ltob_data` donnent une ecole credible sur le papier:
cinq classes, quarante-cinq matieres, cinquante eleves. Mais sept ecrans
restent vides, et pour deux raisons differentes.

**Le premier est un enchainement qu'on ne devine pas.** L'emploi du temps ne se
seme pas: l'application sait le generer, et son ecran a les boutons pour cela.
Seulement `TeacherScheduleSlotViewSet._preparer` n'inscrit une matiere au
besoin que si elle porte `weekly_slots > 0` -- or ce champ vaut zero par defaut
et **aucune commande ne le renseigne**. La generation repond donc « Aucune
matiere a placer », et l'ecran reste vide alors que tout est en place. Cette
commande pose les volumes horaires; la generation, elle, se fait depuis
l'application, ou elle se voit.

**Les autres sont des registres que rien ne remplit**: pointages, paie,
encaissements, depenses, incidents, conversations, emprunts. Un ecran vide ne
se distingue pas d'un ecran casse, ni pour une demonstration, ni pour qui
decouvre le logiciel.

Trois proprietes que cette commande tient, et qu'il ne faut pas lui retirer:

1. **Idempotente.** Tout passe par `get_or_create` ou `update_or_create`. La
   relancer deux fois ne double rien -- `bootstrap.sh` appelle le seed a chaque
   montage, celle-ci doit pouvoir le suivre.
2. **Deterministe.** Une seule source d'alea, `random.Random(graine)`. Deux
   executions a la meme graine donnent la meme ecole, sans quoi une video
   tournee deux fois ne montrerait pas les memes chiffres.
3. **Refus hors developpement.** Meme garde-fou que `seed_empty_classes`: elle
   cree des comptes a mot de passe faible et des ecritures comptables fictives.
"""

import random
from datetime import date, time, timedelta
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
    AvailabilityCampaign,
    AvailabilityKind,
    Borrow,
    CanteenMenu,
    CanteenService,
    ClassRoom,
    DisciplineCategory,
    DisciplineIncident,
    DisciplineSeverity,
    DisciplineStatus,
    Etablissement,
    Expense,
    FeeType,
    Notification,
    NotificationChannel,
    Payment,
    Student,
    StudentFee,
    Subject,
    Teacher,
    TeacherAssignment,
    TeacherAttendance,
    TeacherAvailabilitySlot,
    TeacherPayroll,
    TimetablePublication,
)

# Les memes prenoms et noms que `seed_empty_classes`, et pour la meme raison:
# une ecole malienne ne s'appelle pas Dupont. La liste est recopiee plutot
# qu'importee d'une commande voisine -- deux commandes de peuplement qui se
# lisent l'une l'autre cassent ensemble.
PRENOMS = (
    "Amadou", "Fatoumata", "Ibrahim", "Kadiatou", "Moussa", "Aminata",
    "Seydou", "Oumou", "Bakary", "Mariam", "Cheick", "Assitan",
)
NOMS = (
    "Traore", "Diallo", "Keita", "Coulibaly", "Sangare", "Toure",
    "Konate", "Sidibe", "Dembele", "Maiga", "Cisse", "Doumbia",
)

# Les creneaux d'une journee de cours, tels que l'ecran les propose.
CRENEAUX = (
    (time(8, 0), time(10, 0)),
    (time(10, 15), time(12, 15)),
    (time(15, 0), time(17, 0)),
)

JOURS = ("MON", "TUE", "WED", "THU", "FRI")

MOTIFS_DE_RETARD = (
    "Transport en panne",
    "Embouteillage sur la route de Bamako",
    "Convocation administrative",
)


class Command(BaseCommand):
    help = (
        "Complete la base de demonstration: volumes horaires, enseignants, "
        "pointages, paie, encaissements, incidents, conversations."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--etablissement",
            default="Établissement Démo",
            help="Nom de l'etablissement a garnir.",
        )
        parser.add_argument(
            "--cible-enseignants",
            type=int,
            default=10,
            help="Nombre d'enseignants a atteindre (defaut 10).",
        )
        parser.add_argument(
            "--graine",
            type=int,
            default=2026,
            help="Graine d'alea, pour que deux executions se ressemblent.",
        )
        parser.add_argument(
            "--forcer",
            action="store_true",
            help="Passe outre le refus hors developpement. Base jetable seulement.",
        )

    @staticmethod
    def _alea(graine, *cles):
        """Un generateur propre a l'objet decrit par `cles`.

        Un seul generateur partage rendait la commande **non idempotente**: le
        premier passage cree dix enseignants et consomme dix tirages, le second
        n'en cree aucun -- la suite du decor tombait donc sur d'autres jours,
        d'autres creneaux, d'autres ouvrages, et `get_or_create` ajoutait des
        lignes au lieu de retrouver les siennes.

        En derivant l'alea de l'identite de l'objet, chaque ligne retrouve
        toujours le meme tirage, quel que soit ce qui existe deja en base.
        """
        return random.Random(f"{graine}|" + "|".join(str(cle) for cle in cles))

    def handle(self, *args, **options):
        self._refuser_hors_developpement(forcer=options["forcer"])

        nom = options["etablissement"]
        etablissement = Etablissement.objects.filter(name=nom).first()
        if etablissement is None:
            raise CommandError(
                f"Aucun etablissement nomme « {nom} ». Lancez d'abord "
                "seed_demo_data."
            )

        annee = (
            AcademicYear.objects.filter(etablissement=etablissement, is_active=True)
            .order_by("-start_date")
            .first()
        )
        if annee is None:
            raise CommandError(
                f"« {nom} » n'a aucune annee scolaire active. Lancez d'abord "
                "seed_demo_data."
            )

        graine = options["graine"]
        compteurs = {}

        with transaction.atomic():
            enseignants = self._garnir_les_enseignants(
                etablissement, graine, options["cible_enseignants"], compteurs
            )
            self._poser_les_volumes_horaires(etablissement, graine, compteurs)
            self._affecter_les_enseignants(
                etablissement, enseignants, compteurs
            )
            self._ouvrir_la_collecte_des_disponibilites(
                etablissement, annee, enseignants, graine, compteurs
            )
            self._preparer_les_publications(etablissement, compteurs)
            self._pointer_les_enseignants(
                etablissement, annee, enseignants, graine, compteurs
            )
            self._preparer_une_paie_a_valider(
                etablissement, annee, enseignants, compteurs
            )
            self._encaisser_des_frais(etablissement, annee, graine, compteurs)
            self._engager_des_depenses(etablissement, annee, compteurs)
            self._declarer_des_incidents(etablissement, annee, compteurs)
            self._ouvrir_des_conversations(etablissement, compteurs)
            self._publier_des_annonces(etablissement, compteurs)
            self._animer_la_bibliotheque_et_la_cantine(
                etablissement, compteurs
            )

        self.stdout.write(self.style.SUCCESS("Decor de demonstration complete."))
        for libelle, valeur in compteurs.items():
            self.stdout.write(f"  {libelle:<34} {valeur}")

    # ------------------------------------------------------------------ garde

    def _refuser_hors_developpement(self, *, forcer):
        """Refuse de tourner sur autre chose qu'une base jetable.

        Cette commande cree des comptes a mot de passe faible et des ecritures
        comptables fictives. Meme garde que `seed_empty_classes`, pour la meme
        raison: la commande la plus utile en developpement est la plus
        destructrice ailleurs.
        """
        if forcer or settings.DEBUG:
            return
        raise CommandError(
            "Refus: DEBUG est faux. Cette commande garnit une base de "
            "demonstration et n'a rien a faire en production. "
            "Utilisez --forcer sur une base jetable."
        )

    # ------------------------------------------------------- les enseignants

    def _garnir_les_enseignants(self, etablissement, graine, cible, compteurs):
        """Amene l'effectif enseignant a la cible.

        Une ecole de cinq classes et quarante-cinq matieres avec un seul
        enseignant ne montre ni charge horaire, ni emargement, ni paie: les
        trois ecrans se lisent par comparaison entre plusieurs personnes.
        """
        existants = list(
            Teacher.objects.filter(etablissement=etablissement).select_related("user")
        )
        crees = 0
        indice = len(existants)

        while len(existants) < cible:
            indice += 1
            prenom = PRENOMS[indice % len(PRENOMS)]
            nom = NOMS[(indice * 7) % len(NOMS)]
            identifiant = f"demo.ens{indice:02d}"

            compte, _ = User.objects.get_or_create(
                username=identifiant,
                defaults={
                    "first_name": prenom,
                    "last_name": nom,
                    "role": UserRole.TEACHER,
                    "etablissement": etablissement,
                },
            )
            # Le prefixe « demo. » n'est pas decoratif: il rend ces comptes
            # reconnaissables d'un coup d'oeil sur une base, et purgeables par
            # motif -- ce que la liste canonique des comptes de demonstration
            # ne couvre pas.
            compte.set_password("Demo@12345")
            compte.is_active = True
            compte.etablissement = etablissement
            compte.save(update_fields=["password", "is_active", "etablissement"])

            enseignant, cree = Teacher.objects.get_or_create(
                user=compte,
                defaults={
                    "employee_code": f"DEM-{indice:04d}",
                    "hire_date": date(2024, 9, 1),
                    "salary_base": Decimal(
                        self._alea(graine, "salaire", indice).choice(
                            [250000, 300000, 350000]
                        )
                    ),
                    "hourly_rate": Decimal(
                        self._alea(graine, "taux", indice).choice([2500, 3000, 3500])
                    ),
                    "etablissement": etablissement,
                },
            )
            existants.append(enseignant)
            crees += 1 if cree else 0

        compteurs["Enseignants"] = len(existants)
        return existants

    # ------------------------------------------------- les volumes horaires

    def _poser_les_volumes_horaires(self, etablissement, graine, compteurs):
        """Le deblocage de l'emploi du temps, et la raison de cette commande.

        `Subject.weekly_slots` vaut zero par defaut, avec un commentaire qui dit
        « La direction renseigne ce qu'elle veut voir placer ». En
        demonstration, personne ne le renseigne, et la generation repond
        « Aucune matiere a placer » sur une ecole par ailleurs complete.

        Les volumes suivent le coefficient: une matiere a coefficient 4 pese
        plus d'heures qu'une matiere a coefficient 1. C'est ce qu'une ecole
        fait, et cela rend la grille generee vraisemblable.
        """
        matieres = Subject.objects.filter(
            classroom__etablissement=etablissement
        ).distinct()

        touchees = 0
        for matiere in matieres:
            if matiere.weekly_slots:
                continue
            coefficient = float(matiere.coefficient or 1)
            tirage = self._alea(graine, "volume", matiere.id)
            if coefficient >= 4:
                volume = tirage.choice([3, 4])
            elif coefficient >= 2:
                volume = tirage.choice([2, 3])
            else:
                volume = 2
            matiere.weekly_slots = volume
            matiere.save(update_fields=["weekly_slots"])
            touchees += 1

        compteurs["Matieres a volume horaire"] = matieres.filter(
            weekly_slots__gt=0
        ).count()
        compteurs["Matieres de l'etablissement"] = matieres.count()

    def _affecter_les_enseignants(self, etablissement, enseignants, compteurs):
        """Chaque matiere de chaque classe recoit un enseignant.

        Sans affectation, la generation n'a personne a placer -- et l'ecran des
        charges horaires, celui des disponibilites et la paie restent vides eux
        aussi. Distribution en tourniquet: elle repartit la charge au lieu de
        donner quarante-cinq matieres au premier de la liste.
        """
        matieres = list(
            Subject.objects.filter(classroom__etablissement=etablissement)
            .select_related("classroom")
            .order_by("classroom_id", "id")
        )
        crees = 0
        for position, matiere in enumerate(matieres):
            if matiere.classroom_id is None:
                continue
            enseignant = enseignants[position % len(enseignants)]
            _, cree = TeacherAssignment.objects.get_or_create(
                teacher=enseignant,
                subject=matiere,
                classroom=matiere.classroom,
            )
            crees += 1 if cree else 0

        compteurs["Affectations enseignant-matiere"] = (
            TeacherAssignment.objects.filter(
                classroom__etablissement=etablissement
            ).count()
        )

    # ------------------------------------------------- les disponibilites

    def _ouvrir_la_collecte_des_disponibilites(
        self, etablissement, annee, enseignants, graine, compteurs
    ):
        """Une campagne ouverte, avec des reponses partielles.

        Partielles exprès: l'ecran affiche un taux de reponse et la liste de
        ceux qui n'ont pas repondu. Une campagne ou tout le monde a repondu ne
        montre pas ce que l'ecran sait faire.
        """
        aujourdhui = timezone.localdate()
        campagne, _ = AvailabilityCampaign.objects.get_or_create(
            etablissement=etablissement,
            academic_year=annee,
            status=AvailabilityCampaign.Status.OPEN,
            defaults={
                "label": "Collecte des disponibilites - rentree",
                "opens_on": aujourdhui - timedelta(days=5),
                "closes_on": aujourdhui + timedelta(days=9),
                "instructions": (
                    "Declarez vos creneaux preferes et ceux que vous ne "
                    "pouvez pas assurer. La direction arbitre ensuite."
                ),
            },
        )

        # Deux enseignants sur trois repondent: le troisieme reste visible dans
        # « sans reponse ».
        repondants = [e for i, e in enumerate(enseignants) if i % 3 != 2]
        crees = 0
        for enseignant in repondants:
            tirage = self._alea(graine, "dispo", enseignant.id)
            for jour in sorted(tirage.sample(JOURS, 3)):
                debut, fin = tirage.choice(CRENEAUX)
                genre = tirage.choice(
                    [
                        AvailabilityKind.PREFERRED,
                        AvailabilityKind.POSSIBLE,
                        AvailabilityKind.UNAVAILABLE,
                    ]
                )
                _, cree = TeacherAvailabilitySlot.objects.get_or_create(
                    teacher=enseignant,
                    campaign=campagne,
                    day_of_week=jour,
                    start_time=debut,
                    end_time=fin,
                    defaults={
                        "etablissement": etablissement,
                        "kind": genre,
                        "note": (
                            "Cours a l'autre etablissement"
                            if genre == AvailabilityKind.UNAVAILABLE
                            else ""
                        ),
                    },
                )
                crees += 1 if cree else 0

        compteurs["Creneaux de disponibilite declares"] = (
            TeacherAvailabilitySlot.objects.filter(campaign=campagne).count()
        )
        compteurs["Enseignants ayant repondu"] = len(repondants)

    def _preparer_les_publications(self, etablissement, compteurs):
        """Toutes les classes publiees sauf une.

        Celle qui reste en brouillon est le geste que la direction accomplit a
        l'ecran: sans elle, le bouton « Publier » n'aurait rien a publier.
        """
        classes = list(
            ClassRoom.objects.filter(etablissement=etablissement).order_by("id")
        )
        if not classes:
            compteurs["Publications d'emploi du temps"] = 0
            return

        laissee_en_brouillon = classes[-1]
        publiees = 0
        for classe in classes:
            publier = classe != laissee_en_brouillon
            TimetablePublication.objects.update_or_create(
                classroom=classe,
                defaults={
                    "is_published": publier,
                    "is_locked": publier,
                    "published_at": timezone.now() if publier else None,
                    "notes": (
                        ""
                        if publier
                        else "Laissee en brouillon pour la demonstration."
                    ),
                },
            )
            publiees += 1 if publier else 0

        compteurs["Classes a l'emploi du temps publie"] = publiees
        compteurs["Classe laissee en brouillon"] = laissee_en_brouillon.name

    # -------------------------------------------------- emargement et paie

    def _pointer_les_enseignants(
        self, etablissement, annee, enseignants, graine, compteurs
    ):
        """Quinze jours ouvres de pointage, avec des retards et des absences.

        L'ecran d'emargement et le rapport de concordance se lisent sur une
        serie: un seul jour ne dit ni assiduite, ni ecart.
        """
        jour = timezone.localdate()
        jours_ouvres = []
        while len(jours_ouvres) < 15:
            if jour.weekday() < 5:
                jours_ouvres.append(jour)
            jour -= timedelta(days=1)

        crees = 0
        for enseignant in enseignants:
            for date_du_jour in jours_ouvres:
                tirage = self._alea(
                    graine, "pointage", enseignant.id, date_du_jour.isoformat()
                )
                absent = tirage.random() < 0.05
                retard = (not absent) and tirage.random() < 0.12
                _, cree = TeacherAttendance.objects.get_or_create(
                    teacher=enseignant,
                    date=date_du_jour,
                    defaults={
                        "academic_year": annee,
                        "is_absent": absent,
                        "is_late": retard,
                        "reason": (
                            tirage.choice(MOTIFS_DE_RETARD)
                            if (absent or retard)
                            else ""
                        ),
                    },
                )
                crees += 1 if cree else 0

        compteurs["Pointages enseignants"] = TeacherAttendance.objects.filter(
            teacher__etablissement=etablissement
        ).count()

    def _preparer_une_paie_a_valider(
        self, etablissement, annee, enseignants, compteurs
    ):
        """Des fiches de paie non validees, pour la double signature.

        Le censeur vise au niveau un, le comptable au niveau deux. C'est la
        regle la plus difficile a expliquer sans voix et la plus convaincante a
        montrer -- encore faut-il qu'il y ait quelque chose a viser.
        """
        premier_du_mois = timezone.localdate().replace(day=1)
        crees = 0
        for enseignant in enseignants:
            _, cree = TeacherPayroll.objects.get_or_create(
                teacher=enseignant,
                month=premier_du_mois,
                defaults={
                    "academic_year": annee,
                    "hours_attributed": Decimal("60"),
                    "hours_worked": Decimal("57"),
                    "hours_missed": Decimal("3"),
                    "hourly_rate": enseignant.hourly_rate,
                    "amount": enseignant.salary_base,
                },
            )
            crees += 1 if cree else 0

        compteurs["Fiches de paie du mois"] = TeacherPayroll.objects.filter(
            teacher__etablissement=etablissement, month=premier_du_mois
        ).count()

    # -------------------------------------------------------- la caisse

    def _encaisser_des_frais(self, etablissement, annee, graine, compteurs):
        """Des frais et des encaissements: soldes, partiels, en retard.

        Les trois cas coexistent volontairement. Une caisse ou tout est soldé
        ne montre ni relance, ni reste a payer, ni recu partiel -- c'est-a-dire
        rien de ce que le comptable fait de ses journees.
        """
        eleves = list(
            Student.objects.filter(etablissement=etablissement).order_by("id")[:35]
        )
        echeance = timezone.localdate().replace(day=5)

        frais_crees = 0
        paiements_crees = 0
        for position, eleve in enumerate(eleves):
            du = Decimal("85000")
            frais, cree = StudentFee.objects.get_or_create(
                student=eleve,
                academic_year=annee,
                fee_type=FeeType.MONTHLY,
                due_date=echeance,
                defaults={"amount_due": du},
            )
            frais_crees += 1 if cree else 0

            # Un tiers solde, un tiers partiel, un tiers n'a rien verse.
            cas = position % 3
            if cas == 2:
                continue
            montant = du if cas == 0 else Decimal("40000")
            _, cree = Payment.objects.get_or_create(
                fee=frais,
                reference=f"DEM-PAY-{eleve.id:05d}",
                defaults={
                    "amount": montant,
                    "method": self._alea(graine, "moyen", eleve.id).choice(
                        ["cash", "mobile_money", "cheque"]
                    ),
                    "etablissement": etablissement,
                },
            )
            paiements_crees += 1 if cree else 0

        compteurs["Frais mensuels"] = StudentFee.objects.filter(
            student__etablissement=etablissement, fee_type=FeeType.MONTHLY
        ).count()
        compteurs["Encaissements"] = Payment.objects.filter(
            etablissement=etablissement, is_cancelled=False
        ).count()

    def _engager_des_depenses(self, etablissement, annee, compteurs):
        """Trois mois de depenses, dont une qui attend encore son visa."""
        aujourdhui = timezone.localdate()
        lignes = (
            ("Craie et fournitures de classe", Decimal("45000"), "Fournitures", True),
            ("Reparation du groupe electrogene", Decimal("180000"), "Entretien", True),
            ("Carburant du mois", Decimal("95000"), "Transport", False),
        )
        crees = 0
        for position, (libelle, montant, categorie, payee) in enumerate(lignes):
            _, cree = Expense.objects.get_or_create(
                label=libelle,
                date=aujourdhui - timedelta(days=30 * position + 3),
                defaults={
                    "amount": montant,
                    "academic_year": annee,
                    "category": categorie,
                    "notes": "" if payee else "En attente de validation.",
                    "paid_on": aujourdhui - timedelta(days=30 * position) if payee else None,
                },
            )
            crees += 1 if cree else 0

        compteurs["Depenses engagees"] = Expense.objects.filter(
            academic_year=annee
        ).count()

    # ------------------------------------------------------- la discipline

    def _declarer_des_incidents(self, etablissement, annee, compteurs):
        """Huit incidents, de gravites et d'etats varies.

        Dont un dont les parents n'ont pas ete informes: c'est ce que l'ecran
        signale, et il faut donc qu'il existe.
        """
        eleves = list(
            Student.objects.filter(etablissement=etablissement).order_by("id")[:8]
        )
        declarant = User.objects.filter(
            username="surveillant1", etablissement=etablissement
        ).first()

        motifs = (
            (DisciplineCategory.RETARD, DisciplineSeverity.LOW, "Arrivee a 8h40 sans justificatif."),
            (DisciplineCategory.TENUE, DisciplineSeverity.LOW, "Tenue non conforme au reglement."),
            (DisciplineCategory.INDISCIPLINE, DisciplineSeverity.MEDIUM, "Bavardages repetes malgre les rappels."),
            (DisciplineCategory.INSOLENCE, DisciplineSeverity.MEDIUM, "Propos irrespectueux envers un surveillant."),
            (DisciplineCategory.ABSENCE, DisciplineSeverity.MEDIUM, "Absence non justifiee en cours de mathematiques."),
            (DisciplineCategory.TRICHE, DisciplineSeverity.HIGH, "Documents non autorises pendant une composition."),
            (DisciplineCategory.DEGRADATION, DisciplineSeverity.HIGH, "Table de classe deterioree."),
            (DisciplineCategory.VIOLENCE, DisciplineSeverity.HIGH, "Bagarre dans la cour de recreation."),
        )

        crees = 0
        for position, eleve in enumerate(eleves):
            categorie, gravite, description = motifs[position % len(motifs)]
            traite = position % 3 == 0
            _, cree = DisciplineIncident.objects.get_or_create(
                student=eleve,
                incident_date=timezone.localdate() - timedelta(days=position + 1),
                category=categorie,
                defaults={
                    "academic_year": annee,
                    "description": description,
                    "severity": gravite,
                    "sanction": "Avertissement ecrit." if traite else "",
                    "status": (
                        DisciplineStatus.RESOLVED if traite else DisciplineStatus.OPEN
                    ),
                    # Un incident dont la famille n'a pas ete prevenue: c'est ce
                    # que l'ecran met en avant.
                    "parent_notified": traite and position != 3,
                    "resolved_at": timezone.now() if traite else None,
                    "reported_by": declarant,
                },
            )
            crees += 1 if cree else 0

        compteurs["Incidents disciplinaires"] = DisciplineIncident.objects.filter(
            student__etablissement=etablissement
        ).count()

    # ------------------------------------------------------- la messagerie

    def _ouvrir_des_conversations(self, etablissement, compteurs):
        """Trois fils, et les trois etats qu'un message peut prendre.

        Un message repondu, un modifie, un supprime: le modele les prevoit
        tous les trois, et le fil ne les montre que s'ils existent.
        """
        directeur = User.objects.filter(username="directeur").first()
        enseignant = User.objects.filter(username="enseignant1").first()
        parent = User.objects.filter(username="parent1").first()
        if not (directeur and enseignant and parent):
            compteurs["Conversations ouvertes"] = 0
            return

        groupe, _ = Conversation.objects.get_or_create(
            etablissement=etablissement,
            title="Equipe pedagogique",
            defaults={"is_group": True},
        )
        for personne, administrateur in ((directeur, True), (enseignant, False)):
            ConversationParticipant.objects.get_or_create(
                conversation=groupe,
                user=personne,
                defaults={"is_admin": administrateur},
            )

        premier, _ = ChatMessage.objects.get_or_create(
            conversation=groupe,
            sender=directeur,
            content="Conseil de classe jeudi a 16h, salle des professeurs.",
        )
        ChatMessage.objects.get_or_create(
            conversation=groupe,
            sender=enseignant,
            content="Bien note, j'apporte les releves de la 11eme CG.",
            defaults={"reply_to": premier},
        )
        modifie, cree = ChatMessage.objects.get_or_create(
            conversation=groupe,
            sender=directeur,
            content="Le conseil est repousse a vendredi, meme heure.",
        )
        if cree:
            modifie.edited_at = timezone.now()
            modifie.save(update_fields=["edited_at"])

        # Un fil direct entre une famille et un enseignant: c'est celui que le
        # chapitre « parent » montre.
        direct, _ = Conversation.objects.get_or_create(
            etablissement=etablissement,
            title="",
            is_group=False,
            defaults={},
        )
        for personne in (parent, enseignant):
            ConversationParticipant.objects.get_or_create(
                conversation=direct, user=personne
            )
        ChatMessage.objects.get_or_create(
            conversation=direct,
            sender=enseignant,
            content=(
                "Bonjour, votre enfant progresse en mathematiques ce trimestre."
            ),
        )
        retire, cree = ChatMessage.objects.get_or_create(
            conversation=direct,
            sender=parent,
            content="Message retire",
        )
        if cree:
            retire.deleted_at = timezone.now()
            retire.deleted_by = parent
            retire.save(update_fields=["deleted_at", "deleted_by"])

        compteurs["Conversations ouvertes"] = Conversation.objects.filter(
            etablissement=etablissement
        ).count()
        compteurs["Messages echanges"] = ChatMessage.objects.filter(
            conversation__etablissement=etablissement
        ).count()

    def _publier_des_annonces(self, etablissement, compteurs):
        """Une annonce par public, et une notification qui attend de partir.

        Les quatre publics existent depuis que le champ a cesse d'etre libre;
        une demonstration qui n'en montre qu'un ne montre pas la regle.
        """
        directeur = User.objects.filter(username="directeur").first()
        annonces = (
            ("all", "Rentree des classes le 1er octobre", "Les cours reprennent lundi a 8h."),
            ("families", "Reunion de parents samedi", "Rendez-vous a 9h dans la cour."),
            ("teachers", "Remise des copies avant vendredi", "Depot au secretariat."),
            ("staff", "Inventaire de la caisse lundi", "Presence de la comptabilite requise."),
        )
        crees = 0
        for public, titre, message in annonces:
            _, cree = Announcement.objects.get_or_create(
                etablissement=etablissement,
                title=titre,
                defaults={
                    "message": message,
                    "audience": public,
                    "author": directeur,
                },
            )
            crees += 1 if cree else 0

        parent = User.objects.filter(username="parent1").first()
        if parent is not None:
            Notification.objects.get_or_create(
                etablissement=etablissement,
                recipient=parent,
                title="Bulletin du premier trimestre disponible",
                defaults={
                    "channel": NotificationChannel.SMS,
                    "message": "Le bulletin est consultable dans votre espace.",
                    # Volontairement non envoyee: l'onglet « En attente
                    # d'envoi » de l'ecran Communication a besoin d'une ligne.
                    "is_sent": False,
                },
            )

        compteurs["Annonces publiees"] = Announcement.objects.filter(
            etablissement=etablissement
        ).count()

    def _animer_la_bibliotheque_et_la_cantine(self, etablissement, compteurs):
        """Des emprunts en cours et en retard, des services payes ou non.

        La disponibilite d'un ouvrage se derive de ses emprunts: on la laisse
        se recalculer plutot que de la poser, sinon le decor se contredit.
        """
        from apps.school.models import Book

        eleves = list(
            Student.objects.filter(etablissement=etablissement).order_by("id")[:6]
        )
        # Le seed de demonstration ne cree qu'un seul ouvrage: un catalogue
        # d'un livre ne montre ni recherche, ni rayon, ni rupture.
        catalogue = (
            ("Le Devoir de violence", "Yambo Ouologuem", "Roman", 4),
            ("Mathematiques 3e - Collection Afrique", "Collectif", "Mathematiques", 12),
            ("Histoire du Mali medieval", "Madina Ly-Tall", "Histoire", 6),
            ("Physique-Chimie 2nde", "Collectif", "Sciences", 8),
        )
        for titre, auteur, matiere, quantite in catalogue:
            Book.objects.get_or_create(
                title=titre,
                etablissement=etablissement,
                defaults={
                    "author": auteur,
                    "isbn": f"978-DEM-{abs(hash(titre)) % 100000:05d}",
                    "subject": matiere,
                    "shelf_location": f"R{len(titre) % 5 + 1}",
                    "quantity_total": quantite,
                    "quantity_available": quantite,
                },
            )

        # Les ouvrages du catalogue de demonstration, et eux seuls, dans un
        # ordre fixe: prendre « les quatre premiers livres de la base » liait la
        # cle de l'emprunt a ce qui existait deja, et un second passage
        # rattachait les memes eleves a d'autres livres -- donc de nouveaux
        # emprunts a chaque execution.
        titres = [titre for titre, _, _, _ in catalogue]
        ouvrages = sorted(
            Book.objects.filter(etablissement=etablissement, title__in=titres),
            key=lambda ouvrage: titres.index(ouvrage.title),
        )
        if not ouvrages:
            compteurs["Emprunts de bibliotheque"] = 0
            compteurs["Services de cantine"] = 0
            return

        aujourdhui = timezone.localdate()

        for eleve in eleves:
            ouvrage = ouvrages[eleve.id % len(ouvrages)]
            en_retard = eleve.id % 2 == 1
            Borrow.objects.get_or_create(
                student=eleve,
                book=ouvrage,
                borrowed_at=aujourdhui - timedelta(days=20 if en_retard else 5),
                defaults={
                    "due_date": aujourdhui - timedelta(days=6)
                    if en_retard
                    else aujourdhui + timedelta(days=9),
                },
            )

        for ouvrage in ouvrages:
            if hasattr(ouvrage, "recalculer_disponibilite"):
                ouvrage.recalculer_disponibilite()

        # Meme precaution pour la cantine: l'association eleve-menu se derive de
        # l'identite de l'eleve, non de son rang dans une liste dont la longueur
        # depend de la base.
        menus = list(CanteenMenu.objects.order_by("id")[:2])
        for eleve in eleves:
            if not menus:
                break
            CanteenService.objects.get_or_create(
                student=eleve,
                menu=menus[eleve.id % len(menus)],
                served_on=aujourdhui - timedelta(days=eleve.id % 4),
                defaults={"is_paid": eleve.id % 3 != 0},
            )

        compteurs["Emprunts de bibliotheque"] = Borrow.objects.filter(
            student__etablissement=etablissement
        ).count()
        compteurs["Services de cantine"] = CanteenService.objects.filter(
            student__etablissement=etablissement
        ).count()
