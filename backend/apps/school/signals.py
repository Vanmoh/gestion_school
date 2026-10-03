"""Ce qui doit suivre une ecriture, sans que l'appelant y pense.

Invalidation du cache du tableau de bord.

Les compteurs sont gardes une minute (dashboard_cache). Une minute de retard
passe inapercue sur des effectifs ou des absences, mais pas sur l'argent: un
caissier qui enregistre un paiement puis ouvre le tableau de bord doit y voir
son encaissement, sinon il conclut a une panne et ressaisit.

D'ou ces deux modeles et pas les autres: seuls les paiements et les depenses
sont saisis puis verifies dans la foulee sur le meme ecran.
"""

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db.models.signals import post_delete, post_save, pre_save
from django.dispatch import receiver

from .dashboard_cache import invalidate_stats
from .enseignement import refuser_si_il_n_enseigne_rien
from .models import (
    Attendance,
    DisciplineIncident,
    Expense,
    FeeSchedule,
    ParentProfile,
    ExamResult,
    Payment,
    Student,
    StudentFee,
    TeacherAttendance,
    TeacherPayroll,
    TeacherTimeEntry,
)
from .rattachement_a_l_annee import (
    deja_rattache,
    etablissement_de_l_eleve,
    etablissement_de_l_enseignant,
    rattacher_a_l_annee,
)


@receiver(post_save, sender=Payment)
@receiver(post_delete, sender=Payment)
@receiver(post_save, sender=Expense)
@receiver(post_delete, sender=Expense)
def _clear_dashboard_stats(sender, instance, **kwargs):
    # etablissement_id et non instance.etablissement: lire la cle etrangere
    # declencherait une requete de plus a chaque ecriture, pour un objet dont
    # on n'utilise que l'identifiant.
    invalidate_stats(getattr(instance, "etablissement_id", None))


@receiver(pre_save, sender=settings.AUTH_USER_MODEL)
def _memoriser_l_ancien_telephone(sender, instance, **kwargs):
    """Retient le numero d'avant, pour savoir si le WhatsApp le suivait.

    Lu avant l'ecriture: apres, il est perdu, et l'on ne saurait plus
    distinguer un numero WhatsApp laisse tel quel d'un numero saisi
    volontairement different.
    """
    # Chargement brut -- une restauration: la donnee arrive telle qu'elle
    # etait, on n'en deduit rien. Sans cette garde, ce signal reecrivait ce
    # qu'on restaurait, sur des donnees a moitie chargees.
    if kwargs.get("raw"):
        return
    if not instance.pk:
        instance._ancien_telephone = ""
        return
    ancien = (
        type(instance)
        .objects.filter(pk=instance.pk)
        .values_list("phone", flat=True)
        .first()
    )
    instance._ancien_telephone = ancien or ""


@receiver(post_save, sender=settings.AUTH_USER_MODEL)
def _propager_le_telephone_au_numero_whatsapp(sender, instance, created, **kwargs):
    """Fait suivre le numero WhatsApp quand le telephone change.

    Il existe deux numeros: `User.phone`, champ de repertoire, et
    `ParentProfile.whatsapp_phone`, seul utilise pour l'envoi des bulletins.
    On corrigeait le premier en croyant avoir tout fait, et l'envoi partait
    sur l'ancien numero -- ou sur rien.

    La regle: le numero WhatsApp suit le telephone tant que personne ne les a
    dissocies. Il est donc mis a jour quand il est vide, ou quand il valait
    exactement l'ancien telephone normalise. Un numero WhatsApp saisi
    volontairement different -- le portable du tuteur quand la fiche porte le
    fixe du domicile -- n'est jamais ecrase.

    Le format reste garanti: un telephone illisible (« 76 12 34 56 / bureau
    66 74 22 32 ») ne produit rien plutot qu'un numero devine, et l'ecole
    tranche a la main.
    """
    # Chargement brut -- une restauration: la donnee arrive telle qu'elle
    # etait, on n'en deduit rien. Sans cette garde, ce signal reecrivait ce
    # qu'on restaurait, sur des donnees a moitie chargees.
    if kwargs.get("raw"):
        return
    from apps.school.phone_utils import normaliser_numero

    profil = getattr(instance, "parent_profile", None)
    if profil is None:
        return

    nouveau = normaliser_numero(getattr(instance, "phone", ""))
    if not nouveau:
        return

    actuel = (profil.whatsapp_phone or "").strip()
    if actuel == nouveau:
        return

    ancien_normalise = normaliser_numero(getattr(instance, "_ancien_telephone", ""))
    dissocie = bool(actuel) and actuel != (ancien_normalise or "")
    if dissocie:
        return

    profil.whatsapp_phone = nouveau
    profil.save(update_fields=["whatsapp_phone", "updated_at"])


@receiver(post_save, sender=ParentProfile)
def _reprendre_le_telephone_a_la_creation_du_profil(sender, instance, created, **kwargs):
    """Reprend le telephone du compte quand la fiche parent vient de naitre.

    Le signal precedent ne suffit pas: a l'inscription, le compte est
    enregistre avant que sa fiche parent existe, et la propagation n'a alors
    rien a viser. Un parent cree avec son telephone se retrouvait sans numero
    WhatsApp, donc injoignable, sans que rien ne le signale.
    """
    # Chargement brut -- une restauration: la donnee arrive telle qu'elle
    # etait, on n'en deduit rien. Sans cette garde, ce signal reecrivait ce
    # qu'on restaurait, sur des donnees a moitie chargees.
    if kwargs.get("raw"):
        return
    if not created or (instance.whatsapp_phone or "").strip():
        return

    from apps.school.phone_utils import normaliser_numero

    numero = normaliser_numero(getattr(instance.user, "phone", "") if instance.user else "")
    if not numero:
        return

    # `update` et non `save`: on est deja dans le post_save de cet objet, et
    # le reenregistrer relancerait le signal.
    ParentProfile.objects.filter(pk=instance.pk).update(whatsapp_phone=numero)
    instance.whatsapp_phone = numero


# --- Inscription conditionnee au paiement ----------------------------------
#
# Le statut suit la caisse sans que personne ait a le mettre a jour. Le faire
# a la main aurait garanti l'oubli: le jour ou un parent solde son
# inscription, c'est au guichet, et la secretaire n'ira pas rouvrir la fiche
# pour cocher une case.


def _recalculer_pour(student):
    from .inscription import recalculer

    if student is None:
        return
    try:
        recalculer(student)
    except Exception:
        # Le recalcul ne doit jamais faire echouer l'ecriture qui l'a
        # declenche: un versement enregistre reste enregistre, meme si le
        # statut se remet d'accord au passage suivant.
        pass


@receiver(post_save, sender=Payment)
@receiver(post_delete, sender=Payment)
def _suivre_le_reglement_de_l_inscription(sender, instance, **kwargs):
    """Un versement -- ou son annulation -- peut liberer les documents."""
    # Chargement brut -- une restauration: la donnee arrive telle qu'elle
    # etait, on n'en deduit rien. Sans cette garde, ce signal reecrivait ce
    # qu'on restaurait, sur des donnees a moitie chargees.
    if kwargs.get("raw"):
        return
    fee = getattr(instance, "fee", None)
    _recalculer_pour(getattr(fee, "student", None))


@receiver(post_save, sender=StudentFee)
@receiver(post_delete, sender=StudentFee)
def _suivre_les_frais_d_inscription(sender, instance, **kwargs):
    """Poser le frais d'inscription est ce qui met l'eleve en attente.

    Sans frais, il n'y a rien a payer: un eleve cree avant que le bareme
    soit pose reste en regle jusqu'a ce qu'on lui en reclame un.
    """
    # Chargement brut -- une restauration: la donnee arrive telle qu'elle
    # etait, on n'en deduit rien. Sans cette garde, ce signal reecrivait ce
    # qu'on restaurait, sur des donnees a moitie chargees.
    if kwargs.get("raw"):
        return
    _recalculer_pour(getattr(instance, "student", None))


@receiver(post_save, sender=Student)
def _statuer_a_la_creation_de_la_fiche(sender, instance, created, **kwargs):
    # Chargement brut -- une restauration: la donnee arrive telle qu'elle
    # etait, on n'en deduit rien. Sans cette garde, ce signal reecrivait ce
    # qu'on restaurait, sur des donnees a moitie chargees.
    if kwargs.get("raw"):
        return
    if created:
        _recalculer_pour(instance)


@receiver(post_save, sender=Student)
def _facturer_l_eleve_a_son_inscription(sender, instance, created, **kwargs):
    """Applique a un nouvel eleve les baremes de frais de sa classe.

    Sans cela, le bareme ne suivait pas les arrivees: un eleve inscrit en
    novembre n'avait **aucun frais** tant que personne ne recliquait sur
    « Appliquer ». Et le piege etait qu'il ne s'agissait pas d'une dette
    cachee mais d'une facture jamais etablie -- l'eleve n'apparaissait ni dans
    les relances, ni dans les impayes. Il ne devait officiellement rien, et
    l'oubli ne se voyait nulle part.

    Le bareme et l'inscription restent independants, comme
    `apps/school/inscription.py` l'explique: la fiche s'ouvre sans qu'aucun
    tarif soit fixe, et poser le bareme ensuite rattrape les eleves deja la.
    Ce recepteur ferme le dernier cas ou l'ordre comptait encore.

    Il ne fait rien de plus que ce que le bouton faisait deja: `appliquer()`
    ne cree que les frais manquants, et le couple (eleve, bareme, echeance)
    porte une contrainte d'unicite. Rejouer est donc sans effet.
    """
    if not created or instance.classroom_id is None:
        return

    for bareme in FeeSchedule.objects.filter(classroom_id=instance.classroom_id):
        # Un bareme a la fois: si l'un d'eux est mal renseigne, les autres
        # doivent quand meme produire leurs frais. Une inscription ne peut pas
        # echouer parce qu'un tarif de cantine est incoherent.
        try:
            bareme.appliquer()
        except Exception:
            continue


@receiver(pre_save, sender=TeacherAttendance)
def _ne_pointer_que_ceux_qui_enseignent(sender, instance, **kwargs):
    """Un pointage suppose une seance a assurer.

    La verification est ici, et non seulement dans le serializer, parce que le
    serializer ne couvre que l'API. Les commandes de peuplement, l'admin Django
    et tout code futur ecrivent directement, et c'est ainsi que neuf cent vingt
    pointages sont apparus pour des enseignants sans une matiere.

    Un `pre_save` est le seul point de passage commun a tous ces chemins. Il
    leve `ValidationError`, que DRF transforme en 400 avec le message, et qui
    dans une commande s'affiche telle quelle.
    """
    refuser_si_il_n_enseigne_rien(instance.teacher, quoi="Ce pointage")


@receiver(pre_save, sender=TeacherTimeEntry)
def _n_emarger_que_ceux_qui_enseignent(sender, instance, **kwargs):
    """L'emargement aussi suppose des seances a couvrir.

    `TeacherTimeEntryCoverage` dit a quoi sert ce modele: rapprocher une heure
    d'arrivee des cours effectivement assures. Son `validate()` tolere deja un
    emargement un jour sans cours -- une reunion, une surveillance -- a condition
    d'en donner le motif, et c'est juste. Mais quelqu'un qui ne tient aucune
    matiere n'a de cours **aucun** jour: cinq cent cinquante-quatre emargements
    existaient ainsi, sans rien a couvrir.

    Le creneau d'emploi du temps, lui, n'a pas besoin de cette garde: il pend a
    l'affectation (`TeacherScheduleSlot.assignment`) et ne peut donc pas exister
    sans elle. La regle y tient par construction, ce qui vaut mieux qu'une
    verification.
    """
    refuser_si_il_n_enseigne_rien(instance.teacher, quoi="Cet émargement")


# --- Rattacher a l'annee scolaire ce qui est date -------------------------
#
# Quatre modeles acceptent un `academic_year` vide, et une ligne vide est
# invisible des qu'un ecran choisit une annee: le filtre demande
# `academic_year=<annee>` et `NULL` n'y repond pas. Comme l'application envoie
# l'en-tete d'annee sur toutes ses requetes, ces lignes ne s'affichent jamais
# -- on ne peut donc pas les corriger a l'ecran, faute de les voir.
#
# `AttendanceViewSet` posait deja l'annee a la creation
# (`renseigne_annee_a_la_creation`), mais cela ne couvre que l'API. Les
# commandes de peuplement, l'admin et les migrations ecrivent directement, et
# c'est par la que les quarante-quatre orphelines sont entrees.
#
# Un `pre_save` couvre tous ces chemins. Il ne leve rien: la ligne est valide,
# c'est son rangement qui manque.


@receiver(pre_save, sender=Attendance)
def _ranger_l_absence_dans_son_annee(sender, instance, **kwargs):
    if deja_rattache(instance):
        return
    rattacher_a_l_annee(
        instance,
        date=instance.date,
        etablissement=etablissement_de_l_eleve(instance.student),
    )


@receiver(pre_save, sender=DisciplineIncident)
def _ranger_l_incident_dans_son_annee(sender, instance, **kwargs):
    if deja_rattache(instance):
        return
    rattacher_a_l_annee(
        instance,
        date=instance.incident_date,
        etablissement=etablissement_de_l_eleve(instance.student),
    )


@receiver(pre_save, sender=Expense)
def _ranger_la_depense_dans_son_annee(sender, instance, **kwargs):
    # La depense porte son etablissement: c'est le seul des quatre a ne pas
    # avoir besoin d'un detour par l'eleve ou l'enseignant.
    if deja_rattache(instance):
        return
    rattacher_a_l_annee(
        instance, date=instance.date, etablissement=instance.etablissement
    )


@receiver(pre_save, sender=TeacherAttendance)
def _ranger_le_pointage_dans_son_annee(sender, instance, **kwargs):
    """Aucune orpheline aujourd'hui, et c'est justement le moment de brancher.

    `TeacherAttendance.academic_year` est nullable comme les trois autres. La
    base n'en compte aucune sans annee -- mais les quarante-quatre autres sont
    nees de la meme facilite, et rien n'empeche la prochaine commande de
    peuplement d'en creer ici.
    """
    if deja_rattache(instance):
        return
    rattacher_a_l_annee(
        instance,
        date=instance.date,
        etablissement=etablissement_de_l_enseignant(instance.teacher),
    )


@receiver(pre_save, sender=TeacherPayroll)
def _ranger_la_paie_dans_son_annee(sender, instance, **kwargs):
    # `month` est le premier jour du mois paye. Une paie de juillet ne tombe
    # dans aucune annee scolaire, et reste donc sans rattachement -- ce qui est
    # exact: elle solde un service, elle n'appartient pas a une annee.
    if deja_rattache(instance):
        return
    rattacher_a_l_annee(
        instance,
        date=instance.month,
        etablissement=etablissement_de_l_enseignant(instance.teacher),
    )


@receiver(pre_save, sender=TeacherTimeEntry)
def _ranger_l_emargement_dans_son_annee(sender, instance, **kwargs):
    """Le dernier modele date de la famille, et le plus tardif a l'avoir eu.

    Il n'avait pas de champ du tout: sa liste rendait 1 593 emargements sur
    IFP-OBK -- 751 pour une annee, 842 pour l'autre -- quelle que soit l'annee
    demandee.

    `etablissement` d'abord, l'enseignant en repli: les deux colonnes sont
    nullables, et une ligne importee sans ecole reste localisable par
    l'enseignant qu'elle designe.
    """
    if deja_rattache(instance):
        return
    rattacher_a_l_annee(
        instance,
        date=instance.entry_date,
        etablissement=instance.etablissement
        or etablissement_de_l_enseignant(instance.teacher),
    )


@receiver(pre_save, sender=ExamResult)
def _ne_noter_que_ses_propres_eleves(sender, instance, **kwargs):
    """Une note d'examen relie un eleve a une session de **son** ecole.

    Trois notes de la base reelle ne respectaient pas cela: deux eleves du
    Lycee Technique et une du Complexe Scolaire portaient un resultat sur une
    session « Examen Blanc T1 » appartenant a IFP-OBK.

    Le filtre d'etablissement ne les attrapait pas, parce que les deux couches
    ne suivent pas le meme chemin: la portee d'etablissement passe par
    `student__etablissement`, celle de l'annee par `session__academic_year`.
    Chacune etait coherente de son cote, et la ligne se glissait entre les
    deux -- visible dans la liste de son ecole, mais exclue des que l'annee
    entrait en jeu, donc introuvable dans l'application.

    Ce n'est pas qu'un defaut d'affichage: la moyenne d'une classe, le rang et
    le bulletin se calculent sur ces lignes. Une note accrochee a la session
    d'une autre ecole compte dans un bilan ou elle n'a rien a faire.
    """
    eleve = instance.student
    session = instance.session
    if eleve is None or session is None:
        return

    ecole_de_l_eleve = getattr(eleve, "etablissement_id", None)
    annee = getattr(session, "academic_year", None)
    ecole_de_la_session = getattr(annee, "etablissement_id", None)
    if ecole_de_l_eleve is None or ecole_de_la_session is None:
        # Un rattachement manquant n'est pas une incoherence: `etablissement`
        # est nullable, et refuser ici bloquerait un import legitime.
        return

    if ecole_de_l_eleve != ecole_de_la_session:
        raise ValidationError(
            {
                "session": (
                    "Cette session appartient a un autre etablissement que "
                    "l'eleve. Choisissez une session de son etablissement."
                )
            }
        )
