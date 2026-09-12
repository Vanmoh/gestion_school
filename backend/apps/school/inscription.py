"""Ou en est le reglement de l'inscription d'un eleve.

Beaucoup d'ecoles n'ouvrent le dossier qu'apres encaissement de
l'inscription. La regle ne peut pas bloquer la creation de la fiche: un
paiement s'accroche a un frais, et un frais a un eleve. Sans fiche, il
n'existe aucun endroit ou enregistrer le versement -- la regle prise au pied
de la lettre s'interdit elle-meme, et la caisse repasse au carnet papier.

L'eleve est donc cree, et c'est la delivrance des documents officiels --
bulletin, carte scolaire -- qui attend le reglement. L'appel, les notes et
la discipline restent ouverts: un eleve assis en classe doit etre pointe et
note, sinon le registre ment.
"""

from __future__ import annotations

from decimal import Decimal

from django.db import models
from django.utils import timezone


def _etablissement_de(student):
    return getattr(student, "etablissement", None)


def regle_active_pour(student) -> bool:
    """Vrai si l'ecole de cet eleve conditionne l'inscription au paiement."""
    etablissement = _etablissement_de(student)
    return bool(getattr(etablissement, "inscription_exige_paiement", False))


def montant_minimum_pour(student) -> Decimal:
    etablissement = _etablissement_de(student)
    montant = getattr(etablissement, "inscription_montant_minimum", None)
    return Decimal(montant or 0)


def frais_d_inscription(student):
    """Les frais de type « inscription » de cet eleve.

    Toutes annees confondues: l'eleve reinscrit garde ses frais des annees
    passees, et ce qui compte est ce qu'il doit aujourd'hui. Restreindre a
    l'annee active ferait basculer tout le monde en attente au 1er septembre,
    avant meme que le bareme de la rentree soit pose.
    """
    from apps.school.models import FeeType

    return student.fees.filter(fee_type=FeeType.REGISTRATION)


def montant_regle(student) -> Decimal:
    """Ce qui est deja entre sur les frais d'inscription de cet eleve."""
    from apps.school.models import Payment

    total = Payment.objects.filter(
        fee__in=frais_d_inscription(student), is_cancelled=False
    ).aggregate(valeur=models.Sum("amount"))["valeur"]
    return Decimal(total or 0)


def montant_du(student) -> Decimal:
    """Ce que l'ecole reclame au titre de l'inscription."""
    total = frais_d_inscription(student).aggregate(
        valeur=models.Sum("amount_due")
    )["valeur"]
    return Decimal(total or 0)


def seuil_a_atteindre(student) -> Decimal:
    """Le montant qui libere les documents.

    Le plancher regle par l'ecole, borne par ce qui est reellement du: un
    plancher de 25 000 F sur un frais de 15 000 F rendrait l'inscription
    impossible a solder. Un frais absent donne zero -- sans frais pose, il
    n'y a rien a payer, donc rien a bloquer.
    """
    du = montant_du(student)
    if du <= 0:
        return Decimal(0)
    minimum = montant_minimum_pour(student)
    if minimum <= 0:
        return du
    return min(minimum, du)


def statut_attendu(student) -> str:
    """Le statut que l'etat de la caisse impose, hors exemption.

    L'exemption n'est pas recalculee ici: elle est une decision, pas un
    constat. Seule la direction la pose et la retire.
    """
    from apps.school.models import Student

    if not regle_active_pour(student):
        return Student.Inscription.VALIDEE

    seuil = seuil_a_atteindre(student)
    if seuil <= 0:
        return Student.Inscription.VALIDEE
    if montant_regle(student) >= seuil:
        return Student.Inscription.VALIDEE
    return Student.Inscription.EN_ATTENTE


def recalculer(student, *, enregistrer: bool = True) -> str:
    """Remet le statut d'accord avec la caisse. Rend le statut obtenu."""
    from apps.school.models import Student

    if student.inscription_status == Student.Inscription.EXEMPTEE:
        return student.inscription_status

    attendu = statut_attendu(student)
    if attendu == student.inscription_status:
        return attendu

    student.inscription_status = attendu
    if enregistrer:
        # `update()` plutot que `save()`: le recalcul part d'un signal de
        # paiement, et reecrire toute la fiche depuis la ferait perdre ce
        # qu'un autre processus vient d'y changer.
        Student.objects.filter(pk=student.pk).update(
            inscription_status=attendu, updated_at=timezone.now()
        )
    return attendu


def exempter(student, *, motif: str, par=None):
    """Dispense cet eleve du paiement, en gardant qui l'a decide."""
    from apps.school.models import Student

    student.inscription_status = Student.Inscription.EXEMPTEE
    student.inscription_exempted_reason = (motif or "").strip()[:255]
    student.inscription_exempted_by = par
    student.inscription_exempted_at = timezone.now()
    student.save(
        update_fields=[
            "inscription_status",
            "inscription_exempted_reason",
            "inscription_exempted_by",
            "inscription_exempted_at",
            "updated_at",
        ]
    )
    return student


def lever_l_exemption(student):
    """Retire la dispense et remet le statut d'accord avec la caisse."""
    from apps.school.models import Student

    student.inscription_status = Student.Inscription.EN_ATTENTE
    student.inscription_exempted_reason = ""
    student.inscription_exempted_by = None
    student.inscription_exempted_at = None
    student.save(
        update_fields=[
            "inscription_status",
            "inscription_exempted_reason",
            "inscription_exempted_by",
            "inscription_exempted_at",
            "updated_at",
        ]
    )
    recalculer(student)
    return student


def documents_bloques(student) -> bool:
    """Vrai si les documents officiels de cet eleve sont retenus."""
    from apps.school.models import Student

    if not regle_active_pour(student):
        return False
    return student.inscription_status == Student.Inscription.EN_ATTENTE


def motif_du_blocage(student) -> str:
    """Ce qu'on repond quand un document est retenu.

    Le montant manquant, et non « inscription non reglee »: la secretaire
    doit pouvoir dire au parent combien apporter, sans ouvrir un autre
    ecran.
    """
    manquant = seuil_a_atteindre(student) - montant_regle(student)
    if manquant <= 0:
        manquant = Decimal(0)
    nom = str(student)
    return (
        f"Inscription non reglee pour {nom}: il reste "
        f"{manquant:,.0f} F a encaisser.".replace(",", " ")
    )
