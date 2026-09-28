"""Dire si une base est reellement utilisable, et non seulement peuplee.

Un compteur non nul ne prouve rien. Une base peut porter mille eleves et rester
inexploitable: des enseignants sans heures, des familles injoignables, une
caisse ou tout est paye, un ecran d'alertes sans alerte. Les compteurs de
`doter_les_etablissements_reels` disent ce qu'elle a cree; cette commande dit ce
que la base vaut.

**Elle juge dans le perimetre de la dotation, et pas au-dela.** La dotation ne
gere que les classes nommees dans `insert_classes`. Une base sur laquelle on a
travaille en porte d'autres -- classes d'essai, eleves importes, matieres d'un
ancien seed -- et le lui reprocher serait faux: elle n'y touche pas, exprès.
D'ou deux niveaux, et la distinction est le coeur de cette commande:

- les **erreurs** portent sur ce que la dotation garantit dans son perimetre.
  Une erreur se repare en relancant la dotation, et la commande sort en echec:
  un script d'un seul clic doit s'arreter la;
- les **avertissements** portent sur ce qui est hors perimetre. On le signale,
  on n'echoue pas -- sinon la commande deviendrait impossible a satisfaire sur
  une base vivante, et on prendrait l'habitude de l'ignorer.

    manage.py controler_la_dotation
    manage.py controler_la_dotation --etablissement "IFP-OBK" --part-non-soldee 25
"""

from collections import defaultdict
from decimal import Decimal

from django.core.management.base import BaseCommand
from django.db.models import Sum

from apps.accounts.models import User, UserRole
from apps.school.management.commands.doter_les_etablissements_reels import (
    SIGNATURE_DE_LA_DOTATION,
    Command as CommandeDeDotation,
)
from apps.school.management.commands.insert_classes import ESTABLISSEMENT_CLASSES
from apps.school.models import (
    AcademicYear,
    BulletinDelivery,
    CanteenSubscription,
    ClassRoom,
    DisciplineIncident,
    Etablissement,
    ExamInvigilation,
    ExamPlanning,
    FeeType,
    ParentProfile,
    Payment,
    PromotionDecision,
    PromotionRun,
    PromotionRunStatus,
    LibraryCategory,
    LibraryCollection,
    LibraryDocument,
    SmsProviderConfig,
    StockItem,
    Student,
    StudentAcademicHistory,
    StudentFee,
    Subject,
    Teacher,
    TeacherAssignment,
    TeacherAttendance,
    TeacherPayroll,
    TeacherScheduleSlot,
    TeacherTimeEntry,
)

ROLES_D_ENCADREMENT = (
    UserRole.DIRECTOR,
    UserRole.CENSOR,
    UserRole.ACCOUNTANT,
    UserRole.SUPERVISOR,
    UserRole.PROMOTER,
)


class Command(BaseCommand):
    help = "Controle qu'une base dotee est reellement utilisable."

    def add_arguments(self, parser):
        parser.add_argument(
            "--etablissement",
            default="",
            help="N'en controler qu'un seul, par son nom. Vide = tous.",
        )
        parser.add_argument(
            "--part-non-soldee",
            type=int,
            default=25,
            help="Part attendue d'eleves n'ayant pas solde leur scolarite.",
        )

    def handle(self, *args, **options):
        vise = options["etablissement"].strip()
        part = options["part_non_soldee"]
        dotation = CommandeDeDotation()

        erreurs, avertissements = [], []
        controlees = 0

        for etablissement in Etablissement.objects.order_by("id"):
            if vise and etablissement.name != vise:
                continue

            # Le meme rapprochement que la dotation, et par le meme code: un
            # controle qui deduirait le perimetre autrement finirait par juger
            # une autre ecole que celle qui a ete dotee.
            noms = dotation._classes_de(etablissement, ESTABLISSEMENT_CLASSES)
            if noms is None:
                self.stdout.write(
                    f"  « {etablissement.name} »: hors des listes de classes, "
                    "non controlee."
                )
                continue

            # L'annee active, et elle seule: la dotation ne travaille que sur
            # celle-la. Sans ce filtre, une ecole qui a prepare l'annee suivante
            # voyait ses classes comptees deux fois -- « 30 classes dotees »
            # pour une liste de quinze, et six cent onze eleves pour
            # quatre cent cinquante. Les frais, les volumes horaires et les
            # bilans de l'annee d'apres devenaient autant de fausses anomalies.
            annee = AcademicYear.objects.filter(
                etablissement=etablissement, is_active=True
            ).first()
            if annee is None:
                self.stdout.write(
                    f"  « {etablissement.name} »: aucune annee active, "
                    "non controlee."
                )
                continue

            perimetre = ClassRoom.objects.filter(
                etablissement=etablissement,
                academic_year=annee,
                name__in=list(noms),
            )
            eleves = Student.objects.filter(classroom__in=perimetre)
            if not eleves.exists():
                self.stdout.write(
                    f"  « {etablissement.name} »: aucun eleve dans ses classes, "
                    "non dotee."
                )
                continue

            controlees += 1
            self.stdout.write("")
            self.stdout.write(self.style.SUCCESS(f"=== {etablissement.name} ==="))
            self._controler(
                etablissement, annee, perimetre, eleves, part, erreurs, avertissements
            )

        self.stdout.write("")
        if not controlees:
            self.stdout.write(
                self.style.WARNING("Aucun etablissement dote: rien a controler.")
            )
            return

        for message in avertissements:
            self.stdout.write(self.style.WARNING(f"  hors perimetre: {message}"))

        if erreurs:
            self.stdout.write("")
            for message in erreurs:
                self.stdout.write(self.style.ERROR(f"  erreur: {message}"))
            self.stdout.write("")
            # Le remede voyage avec chaque anomalie, et non en bas de page.
            # « Relancez la dotation » etait faux pour les lignes anterieures a
            # la regle -- des pointages d'enseignants que la dotation ne connait
            # pas: les relancer ne les corrigeait jamais, et un conseil faux fait
            # perdre plus de temps qu'un silence.
            self.stdout.write(
                self.style.ERROR(
                    f"{len(erreurs)} anomalie(s) dans le perimetre de la "
                    "dotation. Le remede est indique avec chacune."
                )
            )
            # `SystemExit` plutot que `CommandError`: l'appelant lit le code de
            # sortie, et une trace Python n'apprendrait rien de plus.
            raise SystemExit(1)

        conclusion = f"{controlees} etablissement(s) controle(s): base utilisable."
        if avertissements:
            conclusion += (
                f" {len(avertissements)} observation(s) hors perimetre, sans gravite."
            )
        self.stdout.write(self.style.SUCCESS(conclusion))

    # ------------------------------------------------------------------ detail

    def _controler(
        self, etablissement, annee, perimetre, eleves, part, erreurs, avertis
    ):
        code = etablissement.code or etablissement.name
        effectif = eleves.count()
        self._ligne(
            "annee controlee", f"{annee.name} -- {perimetre.count()} classes"
        )
        self._ligne("eleves dotes", f"{effectif}")

        # --- la caisse ---------------------------------------------------
        du, regle = self._par_eleve(eleves)
        non_soldes = sum(1 for e, montant in du.items() if regle[e] < montant)
        attendu = effectif * part // 100
        self._ligne("eleves non soldes", f"{non_soldes}/{effectif} (attendu {attendu})")
        if non_soldes != attendu:
            erreurs.append(
                f"{code}: {non_soldes} eleves non soldes au lieu de {attendu}"
            )

        du_i, regle_i = self._par_eleve(eleves, fee_type=FeeType.REGISTRATION)
        impayees = sum(1 for e, montant in du_i.items() if regle_i[e] < montant)
        self._ligne("inscriptions impayees", f"{impayees}/{len(du_i)}")
        if impayees:
            erreurs.append(f"{code}: {impayees} inscriptions impayees")
        if len(du_i) < effectif:
            erreurs.append(
                f"{code}: {effectif - len(du_i)} eleves sans frais d'inscription emis"
            )

        # --- l'emploi du temps -------------------------------------------
        # Les enseignants du perimetre sont ceux qui tiennent une matiere dans
        # une classe dotee. Un enseignant de l'ecole sans aucune affectation n'y
        # entre pas: la dotation ne lui inventera pas un cours.
        affectes = set(
            TeacherAssignment.objects.filter(classroom__in=perimetre).values_list(
                "teacher_id", flat=True
            )
        )
        avec_heures = set(
            TeacherScheduleSlot.objects.filter(
                assignment__classroom__in=perimetre
            ).values_list("assignment__teacher_id", flat=True)
        )
        sans_heures = affectes - avec_heures
        self._ligne("enseignants sans heures", f"{len(sans_heures)}/{len(affectes)}")
        if sans_heures:
            erreurs.append(
                f"{code}: {len(sans_heures)} enseignants affectes sans une seule heure"
            )

        hors = (
            Teacher.objects.filter(etablissement=etablissement)
            .exclude(id__in=affectes)
            .count()
        )
        if hors:
            avertis.append(
                f"{code}: {hors} enseignants sans affectation dans les classes dotees"
            )

        sans_volume = Subject.objects.filter(
            classroom__in=perimetre, weekly_slots=0
        ).count()
        self._ligne(
            "matieres sans volume",
            f"{sans_volume}/{Subject.objects.filter(classroom__in=perimetre).count()}",
        )
        if sans_volume:
            erreurs.append(
                f"{code}: {sans_volume} matieres sans volume horaire "
                "(la generation d'emploi du temps n'a rien a placer)"
            )
        ailleurs = Subject.objects.filter(
            classroom__etablissement=etablissement, weekly_slots=0
        ).exclude(classroom__in=perimetre).count()
        if ailleurs:
            avertis.append(
                f"{code}: {ailleurs} matieres sans volume horaire hors classes dotees"
            )

        # --- l'encadrement -----------------------------------------------
        presents = set(
            User.objects.filter(
                etablissement=etablissement, role__in=ROLES_D_ENCADREMENT
            ).values_list("role", flat=True)
        )
        manquants = [r for r in ROLES_D_ENCADREMENT if r not in presents]
        self._ligne("encadrement", f"{len(presents)}/5 roles")
        if manquants:
            erreurs.append(
                f"{code}: aucun compte pour {', '.join(manquants)} "
                "-- personne ne peut ouvrir l'ecole"
            )

        # --- les bilans ---------------------------------------------------
        bilans = StudentAcademicHistory.objects.filter(student__in=eleves).count()
        self._ligne("bilans archives", f"{bilans} (attendu {effectif * 3})")
        if bilans < effectif * 3:
            erreurs.append(
                f"{code}: {effectif * 3 - bilans} bilans trimestriels manquants "
                "-- le rang s'affichera « - » sur les bulletins"
            )

        # --- les familles -------------------------------------------------
        familles = ParentProfile.objects.filter(children__in=eleves).distinct()
        muettes = familles.filter(user__phone="").count()
        self._ligne("familles injoignables", f"{muettes}/{familles.count()}")
        if muettes:
            erreurs.append(
                f"{code}: {muettes} familles sans numero -- aucun bulletin ne "
                "peut leur partir"
            )

        remises = BulletinDelivery.objects.filter(student__in=eleves)
        etats = set(remises.values_list("status", flat=True))
        self._ligne("remises de bulletin", f"{remises.count()} en {len(etats)} etats")
        sans_numero = remises.filter(phone="").count()
        if sans_numero:
            avertis.append(
                f"{code}: {sans_numero} remises sans numero, anterieures a la dotation"
            )

        # --- la discipline ------------------------------------------------
        sanctionnes = eleves.filter(
            id__in=DisciplineIncident.objects.values("student_id")
        )
        sans_effet = sanctionnes.filter(conduite=18).count()
        self._ligne("eleves sanctionnes", f"{sanctionnes.count()}")
        if sans_effet:
            erreurs.append(
                f"{code}: {sans_effet} eleves sanctionnes gardent 18 de conduite "
                "-- un incident sans consequence"
            )

        # --- les examens --------------------------------------------------
        epreuves = ExamPlanning.objects.filter(classroom__in=perimetre).count()
        pourvues = (
            ExamInvigilation.objects.filter(planning__classroom__in=perimetre)
            .values("planning_id")
            .distinct()
            .count()
        )
        self._ligne("epreuves surveillees", f"{pourvues}/{epreuves}")
        if not epreuves:
            erreurs.append(f"{code}: aucune epreuve au calendrier")
        elif not pourvues:
            erreurs.append(f"{code}: aucune epreuve surveillee")
        elif pourvues == epreuves:
            avertis.append(
                f"{code}: toutes les epreuves sont pourvues, l'onglet "
                "« Surveillance » n'aura rien a montrer"
            )

        # --- le stock -----------------------------------------------------
        articles = list(StockItem.objects.filter(etablissement=etablissement))
        sous_seuil = [a for a in articles if a.quantity < a.minimum_threshold]
        self._ligne("stock sous seuil", f"{len(sous_seuil)}/{len(articles)}")
        if articles and not sous_seuil:
            avertis.append(
                f"{code}: aucun article sous son seuil, l'ecran d'alertes sera muet"
            )
        if articles and len(sous_seuil) == len(articles):
            erreurs.append(
                f"{code}: tous les articles sont sous leur seuil "
                "-- les entrees de stock n'ont pas ete comptees"
            )

        # --- le conseil de fin d'annee ------------------------------------
        # Par sa signature, et non la premiere venue: une simulation faite
        # depuis l'application n'a pas le meme perimetre, et la juger ici
        # reprocherait a la dotation le travail de quelqu'un d'autre.
        conseil = (
            PromotionRun.objects.filter(
                etablissement=etablissement,
                payload__origine=SIGNATURE_DE_LA_DOTATION,
            )
            .order_by("pk")
            .first()
        )
        autres = (
            PromotionRun.objects.filter(etablissement=etablissement)
            .exclude(payload__origine=SIGNATURE_DE_LA_DOTATION)
            .count()
        )
        if autres:
            avertis.append(
                f"{code}: {autres} simulation(s) de fin d'annee faites depuis "
                "l'application, laissees intactes"
            )
        if conseil is None:
            erreurs.append(f"{code}: aucun conseil de fin d'annee")
        else:
            decisions = PromotionDecision.objects.filter(run=conseil).count()
            self._ligne(
                "conseil",
                f"{conseil.status} -- {conseil.promoted_count} promus, "
                f"{conseil.repeated_count} redoublants",
            )
            if conseil.status != PromotionRunStatus.SIMULATED:
                erreurs.append(
                    f"{code}: le conseil a ete execute et non simule "
                    "-- les eleves ont change de classe"
                )
            if conseil.total_students != decisions:
                erreurs.append(
                    f"{code}: le conseil annonce {conseil.total_students} eleves "
                    f"pour {decisions} decisions"
                )

        # --- l'emargement et la paie, enseignant par enseignant -----------
        # Un enseignant affecte doit exister partout ou l'ecole le compte: sur
        # la feuille d'emargement comme sur la paie. Seuls ceux que la dotation
        # recrutait y figuraient, et quinze sur vingt-quatre manquaient.
        emargent = set(
            TeacherTimeEntry.objects.filter(teacher_id__in=affectes).values_list(
                "teacher_id", flat=True
            )
        )
        self._ligne("enseignants emargeant", f"{len(emargent)}/{len(affectes)}")
        if len(emargent) < len(affectes):
            erreurs.append(
                f"{code}: {len(affectes) - len(emargent)} enseignants affectes "
                "sans une ligne d'emargement"
            )

        payes = set(
            TeacherPayroll.objects.filter(teacher_id__in=affectes).values_list(
                "teacher_id", flat=True
            )
        )
        self._ligne("fiches de paie", f"{len(payes)}/{len(affectes)}")
        if len(payes) < len(affectes):
            erreurs.append(
                f"{code}: {len(affectes) - len(payes)} enseignants affectes "
                "sans fiche de paie"
            )

        # Et personne d'autre: un pointage suppose une seance a assurer. Neuf
        # cent vingt lignes existaient pour des enseignants sans une matiere, et
        # un registre d'absences ne dit pas qui enseigne quoi -- rien ne le
        # signalait.
        pointes_a_tort = (
            TeacherAttendance.objects.filter(
                teacher__etablissement=etablissement
            )
            .exclude(teacher__id__in=TeacherAssignment.objects.values("teacher_id"))
            .count()
        )
        if pointes_a_tort:
            erreurs.append(
                f"{code}: {pointes_a_tort} pointages d'enseignants sans une "
                "seule matiere -- il n'y a rien a assurer. Affectez-leur une "
                "matiere, ou retirez-les avec "
                "« retirer_les_enseignants_sans_matiere »"
            )

        emarges_a_tort = (
            TeacherTimeEntry.objects.filter(etablissement=etablissement)
            .exclude(teacher__id__in=TeacherAssignment.objects.values("teacher_id"))
            .count()
        )
        if emarges_a_tort:
            erreurs.append(
                f"{code}: {emarges_a_tort} emargements d'enseignants sans une "
                "seule matiere -- il n'y a aucune seance a couvrir. Meme remede "
                "que ci-dessus"
            )

        # --- la remise des bulletins, famille par famille -----------------
        avec_famille = eleves.filter(parent__isnull=False)
        servis = set(
            remises.filter(student__in=avec_famille).values_list(
                "student_id", flat=True
            )
        )
        self._ligne("bulletins remis", f"{len(servis)}/{avec_famille.count()}")
        if len(servis) < avec_famille.count():
            erreurs.append(
                f"{code}: {avec_famille.count() - len(servis)} eleves ayant une "
                "famille sans remise de bulletin"
            )
        if len(etats) < 4:
            erreurs.append(
                f"{code}: les remises ne portent que {len(etats)} etats sur 4 "
                "-- le motif d'echec ne s'affichera nulle part"
            )

        # --- la cantine ----------------------------------------------------
        abonnes = CanteenSubscription.objects.filter(student__in=eleves).count()
        proportion = 100 * abonnes // max(effectif, 1)
        self._ligne("abonnes cantine", f"{abonnes}/{effectif} ({proportion} %)")
        if not abonnes:
            erreurs.append(f"{code}: aucun abonnement a la cantine")
        elif not 20 <= proportion <= 70:
            # Un plafond absolu donnait onze pour cent ici et trente-cinq la:
            # la meme base racontait deux ecoles differentes.
            avertis.append(
                f"{code}: {proportion} % d'abonnes a la cantine, hors de la "
                "fourchette 20-70 % attendue"
            )

        # --- le fonds numerique --------------------------------------------
        collections = LibraryCollection.objects.filter(etablissement=etablissement)
        documents = LibraryDocument.objects.filter(etablissement=etablissement)
        categories = LibraryCategory.objects.filter(collection__in=collections)
        self._ligne(
            "fonds numerique",
            f"{collections.count()} collections, {categories.count()} categories, "
            f"{documents.count()} documents",
        )
        if not collections.exists() or not categories.exists():
            erreurs.append(
                f"{code}: le fonds numerique n'a pas ses trois niveaux "
                "-- l'arbre s'ouvrira vide"
            )
        elif not documents.exists():
            erreurs.append(f"{code}: aucun document dans le fonds numerique")
        elif not documents.exclude(import_error="").exists():
            avertis.append(
                f"{code}: aucun document en erreur d'import, la colonne "
                "« motif » n'aura rien a dire"
            )

        # --- la passerelle SMS ---------------------------------------------
        passerelle = SmsProviderConfig.objects.filter(
            etablissement=etablissement
        ).first()
        if passerelle is None:
            erreurs.append(
                f"{code}: aucune passerelle SMS -- l'ecran des envois dira "
                "seulement qu'aucun fournisseur n'est configure"
            )
        else:
            self._ligne(
                "passerelle sms",
                f"{passerelle.provider_name} ({'active' if passerelle.is_active else 'inactive'})",
            )
            if passerelle.is_active:
                erreurs.append(
                    f"{code}: la passerelle SMS est active -- un peuplement ne "
                    "doit jamais pouvoir faire partir un envoi"
                )

        # --- ce qui vit hors des listes -----------------------------------
        dehors = Student.objects.filter(etablissement=etablissement).exclude(
            classroom__in=perimetre
        )
        autre_annee = dehors.exclude(classroom__academic_year=annee).count()
        hors_listes = dehors.count() - autre_annee
        if autre_annee:
            avertis.append(
                f"{code}: {autre_annee} eleves sur une autre annee scolaire"
            )
        if hors_listes:
            avertis.append(
                f"{code}: {hors_listes} eleves dans des classes hors "
                "« insert_classes », non dotes"
            )

    # ----------------------------------------------------------------- outils

    def _ligne(self, libelle, valeur):
        self.stdout.write(f"  {libelle:<24} {valeur}")

    @staticmethod
    def _par_eleve(eleves, **filtres):
        """Deux requetes separees, jamais jointes.

        Joindre les frais et leurs paiements dans un meme `annotate` multiplie
        les lignes, et `distinct=True` sur un `Sum` dedoublonne les montants
        egaux: deux facons de se mentir sur une caisse.
        """
        du = defaultdict(Decimal)
        for eleve, montant in (
            StudentFee.objects.filter(student__in=eleves, **filtres)
            .values_list("student_id")
            .annotate(s=Sum("amount_due"))
        ):
            du[eleve] = montant or Decimal(0)

        regle = defaultdict(Decimal)
        for eleve, montant in (
            Payment.objects.filter(
                fee__student__in=eleves,
                is_cancelled=False,
                **{f"fee__{champ}": valeur for champ, valeur in filtres.items()},
            )
            .values_list("fee__student_id")
            .annotate(s=Sum("amount"))
        ):
            regle[eleve] = montant or Decimal(0)

        return du, regle
