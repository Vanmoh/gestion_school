"""Les quatre ecoles reelles, decrites **une seule fois**.

Elles l'etaient trois fois, et les trois descriptions ne concordaient pas:

- la migration `9999_insert_etablissements` creait « Lycee Technique Oumar Bah
  (LTOB) », « Lycee Technique Oumar Bah (LOBK) », « IFP-OBK » et « Complexe
  Scolaire Omar Bah (CSOB) » -- avec « Omar » sans u;
- la commande `insert_etablissements` creait « LTOB », « LOBK », « IFP-OBK » et
  « Complexe Scolaire Oumar Bah »;
- `insert_classes.ESTABLISSEMENT_CLASSES` attendait encore d'autres noms.

Un seul nom etait commun aux deux premieres listes: « IFP-OBK ». Lancer la
migration puis la commande creait donc **sept** etablissements pour quatre
ecoles. La commande fusionnait ensuite ses alias et en supprimait trois -- d'ou
quatre ecoles portant les identifiants 3, 5, 7 et 11, et une base ou rien
n'expliquait les trous.

Trois consequences, toutes constatees:

1. Les noms ont derive. Quelqu'un a renomme « LYCCE OBK » a la main, un nom
   qu'aucune liste ne reconnait: `controler_la_dotation` repondait « hors des
   listes de classes, non controlee » et cette ecole n'a jamais ete verifiee.
2. Chaque base de test heritait des quatre lignes de la migration, que le test
   n'avait pas demandees.
3. Personne ne pouvait dire quel etait le nom juste.

D'ou ce module. `code` est l'identifiant stable: il est en base, il ne derive
pas, et il compose les matricules (« LT10CT25E0001M »). `sigle` est la cle de
`ESTABLISSEMENT_CLASSES`. `nom` est ce qu'un ecran affiche -- et il porte le
sigle entre parentheses, pour que le rapprochement par sigle fonctionne meme
si quelqu'un le retape.
"""

from __future__ import annotations

# `code` n'est jamais modifie: il compose les matricules deja distribues.
ETABLISSEMENTS_REELS = (
    {
        "code": "LT",
        "sigle": "LTOB",
        "nom": "Lycée Technique Oumar Bah (LTOB)",
    },
    {
        "code": "LO",
        "sigle": "LOBK",
        # « Lycee Oumar Bah », sans « Technique »: c'est la migration
        # `0070_le_lycee_oumar_bah_porte_son_nom` qui l'a tranche, et l'ecole
        # s'appelle ainsi. Choisir un autre nom ici aurait fait une quatrieme
        # description concurrente, ce que ce module existe pour empecher.
        "nom": "Lycée Oumar Bah (LOBK)",
    },
    {
        "code": "IO",
        "sigle": "IFP-OBK",
        "nom": "IFP-OBK",
    },
    {
        "code": "CS",
        "sigle": "CSOB",
        "nom": "Complexe Scolaire Oumar Bah (CSOB)",
    },
)

# Les noms qu'une base peut deja porter, et vers quel code ils renvoient.
#
# Y figurent les deux listes historiques, les variantes sans accent, et les
# saisies a la main constatees en production -- « LYCCE OBK » en est une. La
# comparaison se fait sans casse ni accent (voir `code_de`), donc inutile
# d'enumerer les variantes de casse.
NOMS_CONNUS = {
    # LTOB
    "ltob": "LT",
    "lycee technique oumar bah (ltob)": "LT",
    "lycee technique oumar bah": "LT",
    # LOBK
    "lobk": "LO",
    "lycee oumar bah de kaloum": "LO",
    "lycee oumar bah de kaloum (lobk)": "LO",
    "lycee technique oumar bah (lobk)": "LO",
    "lycee oumar bah (lobk)": "LO",
    "lycce obk": "LO",
    "lycee obk": "LO",
    # IFP-OBK
    "ifp-obk": "IO",
    "ifp obk": "IO",
    "institut de formation professionnelle oumar bah": "IO",
    # CSOB
    "csob": "CS",
    "complexe scolaire oumar bah": "CS",
    "complexe scolaire oumar bah (csob)": "CS",
    "complexe scolaire omar bah (csob)": "CS",
    "complexe scolaire omar bah": "CS",
}

PAR_CODE = {ecole["code"]: ecole for ecole in ETABLISSEMENTS_REELS}


def sans_accent(texte: str) -> str:
    """Rapproche « Lycée » et « Lycee », qui designent la meme ecole.

    Les deux orthographes coexistent dans les listes historiques, et une base
    peut porter l'une ou l'autre selon qui a saisi.
    """
    remplacements = str.maketrans("àâäéèêëîïôöùûüç", "aaaeeeeiioouuuc")
    return texte.translate(remplacements)


def cle_de_nom(nom: str) -> str:
    return sans_accent((nom or "").strip().lower())


def code_de(etablissement) -> str | None:
    """Le code canonique de cette ecole: par son code, puis par son nom.

    Le code d'abord, parce qu'il ne derive pas. Le nom ensuite, pour rattraper
    une base ou le code manque -- et par `NOMS_CONNUS`, pour qu'une saisie a la
    main deja constatee ne redevienne pas une ecole inconnue.
    """
    code = (getattr(etablissement, "code", "") or "").strip().upper()
    if code in PAR_CODE:
        return code
    return NOMS_CONNUS.get(cle_de_nom(getattr(etablissement, "name", "")))
