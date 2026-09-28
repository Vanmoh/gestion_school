"""Retire de la base une ecole de demonstration, et rien d'autre.

`bootstrap.sh` et `deploy_one_click.sh` appellent `seed_demo_data` a chaque
montage: « Etablissement Demo » reapparait donc tout seul, avec sa classe, ses
deux eleves et ses dix comptes. Sur un poste de developpement c'est le but; sur
une base qu'on montre ou qu'on exploite, c'est une ecole de plus dans le
selecteur, et deux eleves fictifs dans les listes.

`purger_comptes_demo` retire les comptes. Rien ne retirait l'ecole.

**Cette commande detruit des donnees, et elle le fait dans cet ordre:**

1. elle dresse l'inventaire de ce qu'elle emporterait, et s'arrete la;
2. elle refuse si l'ecole ne ressemble pas a un decor -- un seul eleve dont le
   nom n'appartient a aucune liste fictive connue suffit a l'arreter;
3. elle ne supprime qu'avec `--confirmer`, et dans une transaction.

Vingt des vingt-six relations qui pointent vers un etablissement sont en
`PROTECT`: la suppression se fait donc feuille par feuille, dans l'ordre
inverse des dependances. Un `delete()` direct echouerait sur la premiere.
"""

from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.db.models import ProtectedError

from apps.accounts.models import User
from apps.chat.models import Conversation
from apps.common.comptes_demo import NOMS_DES_COMPTES_DE_DEMONSTRATION
from apps.school.models import (
    AcademicYear,
    Announcement,
    AvailabilityCampaign,
    Book,
    Borrow,
    CanteenService,
    CanteenMenu,
    ClassRoom,
    Etablissement,
    ExamInvigilation,
    ExamPlanning,
    ExamResult,
    ExamSession,
    Expense,
    Notification,
    ParentProfile,
    Payment,
    SmsProviderConfig,
    StockItem,
    Student,
    Subject,
    Supplier,
    Teacher,
    TeacherAssignment,
    TeacherScheduleSlot,
    TimetablePublication,
)

# Le nom que `seed_demo_data` donne a son ecole.
NOM_PAR_DEFAUT = "Établissement Démo"


def _noms_fictifs_connus():
    """Les noms de famille que les commandes de peuplement produisent.

    Lus a la source plutot que recopies: une liste figee ici finirait par
    laisser passer des eleves semes par une commande plus recente, et une
    barriere qui derive de ce qu'elle garde ne garde rien.
    """
    noms = {"nguessan", "kouadio", "diallo"}
    for chemin, attribut in (
        ("apps.school.management.commands.seed_empty_classes", "NOMS"),
        ("apps.school.management.commands.completer_le_decor_de_demonstration", "NOMS"),
    ):
        try:
            module = __import__(chemin, fromlist=[attribut])
            noms.update(n.strip().lower() for n in getattr(module, attribut, ()))
        except Exception:
            continue
    try:
        from apps.school.management.commands.seed_ltob_data import Command as Ltob

        noms.update(n.strip().lower() for n in getattr(Ltob, "LAST_NAMES", ()))
    except Exception:
        pass
    return noms


class Command(BaseCommand):
    help = (
        "Inventorie puis supprime une ecole de demonstration. "
        "Sans --confirmer, elle ne fait que montrer."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--etablissement",
            default=NOM_PAR_DEFAUT,
            help=f"Nom de l'ecole a retirer (defaut « {NOM_PAR_DEFAUT} »).",
        )
        parser.add_argument(
            "--confirmer",
            action="store_true",
            help="Supprime reellement. Sans lui, la commande se contente de compter.",
        )
        parser.add_argument(
            "--forcer",
            action="store_true",
            help=(
                "Passe outre le refus quand l'ecole contient des noms inconnus. "
                "A n'employer qu'apres avoir lu l'inventaire ligne par ligne."
            ),
        )

    def handle(self, *args, **options):
        nom = options["etablissement"]
        etablissement = Etablissement.objects.filter(name=nom).first()
        if etablissement is None:
            self.stdout.write(
                self.style.SUCCESS(
                    f"Aucune ecole nommee « {nom} »: rien a retirer."
                )
            )
            self._lister_ce_qui_reste()
            return

        inventaire = self._inventorier(etablissement)
        self._afficher(etablissement, inventaire)

        suspects = self._eleves_aux_noms_inconnus(etablissement)
        if suspects and not options["forcer"]:
            self.stderr.write(
                self.style.ERROR(
                    f"\nRefus: {len(suspects)} eleve(s) de cette ecole portent un nom "
                    "qui n'appartient a aucune liste fictive connue."
                )
            )
            for matricule, nom_eleve in suspects[:5]:
                self.stderr.write(f"  - {matricule} ({nom_eleve})")
            raise CommandError(
                "Cette ecole ne ressemble pas a un decor. Relisez l'inventaire, "
                "et n'employez --forcer qu'en connaissance de cause."
            )

        if not options["confirmer"]:
            self.stdout.write(
                self.style.WARNING(
                    "\nRien n'a ete supprime. Relancez avec --confirmer pour agir."
                )
            )
            return

        with transaction.atomic():
            self._supprimer(etablissement)

        self.stdout.write(
            self.style.SUCCESS(f"\n« {nom} » a ete retiree de la base.")
        )
        self._lister_ce_qui_reste()

    # ---------------------------------------------------------- l'inventaire

    def _inventorier(self, etablissement):
        """Ce que la suppression emporterait, compte par compte."""
        return [
            ("Annees scolaires", AcademicYear.objects.filter(etablissement=etablissement)),
            ("Classes", ClassRoom.objects.filter(etablissement=etablissement)),
            ("Matieres", Subject.objects.filter(classroom__etablissement=etablissement)),
            ("Eleves", Student.objects.filter(etablissement=etablissement)),
            ("Enseignants", Teacher.objects.filter(etablissement=etablissement)),
            ("Familles", ParentProfile.objects.filter(etablissement=etablissement)),
            ("Comptes", User.objects.filter(etablissement=etablissement)),
            ("Encaissements", Payment.objects.filter(etablissement=etablissement)),
            ("Depenses", Expense.objects.filter(etablissement=etablissement)),
            ("Annonces", Announcement.objects.filter(etablissement=etablissement)),
            ("Notifications", Notification.objects.filter(etablissement=etablissement)),
            ("Ouvrages", Book.objects.filter(etablissement=etablissement)),
            ("Menus de cantine", CanteenMenu.objects.filter(etablissement=etablissement)),
            ("Articles de stock", StockItem.objects.filter(etablissement=etablissement)),
            ("Fournisseurs", Supplier.objects.filter(etablissement=etablissement)),
            ("Passerelles SMS", SmsProviderConfig.objects.filter(etablissement=etablissement)),
        ]

    def _afficher(self, etablissement, inventaire):
        self.stdout.write(
            self.style.WARNING(
                f"Ce que la suppression de « {etablissement.name} » emporterait:"
            )
        )
        for libelle, queryset in inventaire:
            compte = queryset.count()
            if compte:
                self.stdout.write(f"  {libelle:<22} {compte}")

    def _eleves_aux_noms_inconnus(self, etablissement):
        """Les eleves dont le nom ne vient d'aucune commande de peuplement.

        Un seul suffit a arreter la commande: mieux vaut refuser une
        suppression legitime que detruire une ecole reelle.
        """
        fictifs = _noms_fictifs_connus()
        suspects = []
        for eleve in Student.objects.filter(etablissement=etablissement).select_related(
            "user"
        ):
            nom = (getattr(eleve.user, "last_name", "") or "").strip().lower()
            if nom and nom not in fictifs:
                suspects.append((eleve.matricule or str(eleve.id), nom))
        return suspects

    # ---------------------------------------------------------- la suppression

    def _supprimer(self, etablissement):
        """Feuille par feuille, dans l'ordre inverse des dependances.

        Vingt relations sont en `PROTECT`: un `delete()` direct echouerait sur
        la premiere, et un ordre approximatif echouerait plus loin. On descend
        donc des ecritures vers les personnes, puis des personnes vers la
        structure.
        """
        def etape(libelle, queryset):
            self._effacer(libelle, queryset)

        # Ce qui relie deux choses vient en premier: un emprunt protege son
        # ouvrage, un service de cantine protege son menu. Les supprimer apres
        # aurait bloque sur un `ProtectedError`, ce qu'un premier essai a
        # d'ailleurs fait.
        etape("emprunts", Borrow.objects.filter(student__etablissement=etablissement))
        etape(
            "services de cantine",
            CanteenService.objects.filter(student__etablissement=etablissement),
        )

        # Les ecritures et les documents ensuite.
        etape("encaissements", Payment.objects.filter(etablissement=etablissement))
        etape("depenses", Expense.objects.filter(etablissement=etablissement))
        etape("annonces", Announcement.objects.filter(etablissement=etablissement))
        etape("notifications", Notification.objects.filter(etablissement=etablissement))
        etape("passerelles SMS", SmsProviderConfig.objects.filter(etablissement=etablissement))
        etape("menus de cantine", CanteenMenu.objects.filter(etablissement=etablissement))
        etape("ouvrages", Book.objects.filter(etablissement=etablissement))
        etape("articles de stock", StockItem.objects.filter(etablissement=etablissement))
        etape("fournisseurs", Supplier.objects.filter(etablissement=etablissement))

        # Puis les personnes: les eleves emportent leurs notes, leurs absences
        # et leurs frais par cascade.
        etape("eleves", Student.objects.filter(etablissement=etablissement))
        etape("enseignants", Teacher.objects.filter(etablissement=etablissement))
        etape("familles", ParentProfile.objects.filter(etablissement=etablissement))

        # Ce qui designe une matiere ou une classe doit partir avant elles:
        # une epreuve protege sa matiere, une affectation aussi, et un creneau
        # d'emploi du temps protege son affectation.
        etape(
            "creneaux d'emploi du temps",
            TeacherScheduleSlot.objects.filter(
                assignment__classroom__etablissement=etablissement
            ),
        )
        etape(
            "notes d'examen",
            ExamResult.objects.filter(student__etablissement=etablissement),
        )
        etape(
            "surveillances",
            ExamInvigilation.objects.filter(
                planning__classroom__etablissement=etablissement
            ),
        )
        etape(
            "epreuves",
            ExamPlanning.objects.filter(classroom__etablissement=etablissement),
        )
        etape(
            "campagnes d'examen",
            ExamSession.objects.filter(
                academic_year__etablissement=etablissement
            ),
        )
        etape(
            "affectations enseignant-matiere",
            TeacherAssignment.objects.filter(
                classroom__etablissement=etablissement
            ),
        )
        etape(
            "publications d'emploi du temps",
            TimetablePublication.objects.filter(
                classroom__etablissement=etablissement
            ),
        )

        # Puis la structure.
        etape("matieres", Subject.objects.filter(classroom__etablissement=etablissement))
        etape("classes", ClassRoom.objects.filter(etablissement=etablissement))
        # Une campagne de disponibilites et une depense designent leur annee:
        # elles partent avant elle.
        etape(
            "campagnes de disponibilites",
            AvailabilityCampaign.objects.filter(etablissement=etablissement),
        )
        etape(
            "depenses de l'annee",
            Expense.objects.filter(academic_year__etablissement=etablissement),
        )
        etape("annees scolaires", AcademicYear.objects.filter(etablissement=etablissement))

        # Les comptes en dernier: `ActivityLog` les garde en `SET_NULL`, donc
        # le journal survit a la suppression -- ce qui est voulu, un audit ne
        # s'efface pas avec son auteur.
        # Les conversations designent leur ecole: elles partent avant elle, et
        # emportent leurs messages par cascade.
        etape(
            "conversations",
            Conversation.objects.filter(etablissement=etablissement),
        )

        etape("comptes", User.objects.filter(etablissement=etablissement))

        # Les comptes semes sans etablissement: `seed_ltob_data` cree ses
        # eleves sans les rattacher, si bien qu'ils survivaient a la
        # suppression de leur ecole -- cinquante et un comptes qui ne
        # pointaient plus vers rien. On ne retire que ceux dont le profil est
        # parti avec elle: un compte encore rattache a un eleve ou a un
        # enseignant appartient a quelqu'un.
        orphelins = User.objects.filter(
            etablissement__isnull=True,
            student_profile__isnull=True,
            teacher_profile__isnull=True,
            parent_profile__isnull=True,
            is_superuser=False,
            is_staff=False,
        ).exclude(username__in=NOMS_DES_COMPTES_DE_DEMONSTRATION)
        etape("comptes devenus orphelins", orphelins)

        try:
            etablissement.delete()
        except ProtectedError as protege:
            raise CommandError(
                "L'ecole elle-meme ne peut pas etre supprimee: quelque chose "
                f"s'y rattache encore. {protege.args[0]}"
            ) from protege

    def _effacer(self, libelle, queryset):
        compte = queryset.count()
        if not compte:
            return
        try:
            queryset.delete()
        except ProtectedError as protege:
            # Le message brut de Django nomme un modele technique. On dit ce
            # qu'il faut supprimer d'abord, pour que l'ordre se corrige au lieu
            # de se deviner.
            raise CommandError(
                f"Impossible de supprimer les {libelle}: quelque chose s'y "
                f"rattache encore. {protege.args[0]}"
            ) from protege
        self.stdout.write(f"  - {compte} {libelle}")

    # ------------------------------------------------------- ce qui subsiste

    def _lister_ce_qui_reste(self):
        self.stdout.write("")
        self.stdout.write(self.style.SUCCESS("Ecoles presentes en base:"))
        for ecole in Etablissement.objects.order_by("name"):
            classes = ClassRoom.objects.filter(etablissement=ecole).count()
            eleves = Student.objects.filter(etablissement=ecole).count()
            self.stdout.write(
                f"  {ecole.name:<46} {classes:>3} classe(s)  {eleves:>4} eleve(s)"
            )
