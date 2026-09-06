# Envoi des bulletins aux familles par WhatsApp

## 1. Ce que fait la fonction aujourd'hui

Depuis **Rapports > Envoyer aux familles (WhatsApp)**, l'ecole ouvre la liste
d'une classe. Pour chaque eleve, l'ecran dit si le bulletin peut partir et,
sinon, ce qui manque. Un clic sur « Envoyer » ouvre WhatsApp avec le message
deja redige ; l'utilisateur appuie sur envoyer, revient dans l'application et
confirme le depart.

Le message ne porte pas le PDF en piece jointe mais un **lien de
telechargement signe**, valable 72 heures par defaut. Le bulletin est produit
au moment ou la famille ouvre le lien : rien n'est stocke, et une note
corrigee entre-temps profite au parent.

## 2. Pourquoi l'envoi est assiste et non automatique

Joindre un fichier a une conversation WhatsApp de facon automatisee impose la
**WhatsApp Cloud API** de Meta, c'est-a-dire :

1. un compte Meta Business verifie (documents legaux de l'etablissement) ;
2. un numero dedie, qui ne peut plus servir sur WhatsApp normal ;
3. un modele de message approuve par Meta -- l'ecole etant a l'origine de la
   conversation, elle ne peut pas ecrire librement ;
4. une facturation par conversation, a la charge de l'ecole.

Aucune de ces quatre conditions ne se regle dans le code. Le canal assiste,
lui, fonctionne sans compte, sans delai d'approbation et sans cout.

Automatiser WhatsApp Web (whatsapp-web.js, Selenium et assimiles) contourne
ces contraintes mais viole les conditions d'utilisation de Meta et fait bannir
le numero de l'ecole. Ce n'est pas une option.

## 3. Ce qui empeche un envoi

L'ecran refuse d'envoyer, et le dit sur la ligne de l'eleve :

| Motif affiche | Ce qu'il faut faire |
| --- | --- |
| Aucun parent rattache a cet eleve | Rattacher un parent depuis le module Eleves |
| Numero WhatsApp du parent absent / invalide | « Corriger le contact » sur la ligne |
| Le parent n'a pas donne son accord | Recueillir l'accord, puis cocher la case |
| Aucune note saisie pour la periode | Saisir les notes : le bulletin serait vide |

Un bulletin deja envoye pour la meme periode n'est pas renvoye sans
confirmation explicite.

## 4. Numeros de telephone

Les numeros sont conserves au format international (`+22376123456`). Le
secretariat saisit comme il en a l'habitude (« 76 12 34 56 ») ; c'est le
serveur qui normalise, dans `apps/school/phone_utils.py`.

Deux cas sont **refuses** plutot que devines :

- une case contenant deux numeros (« 76 12 34 56 / 66 74 22 32 ») : personne
  ne peut savoir lequel est celui du tuteur ;
- un numero national incomplet.

La migration `0054_reprise_numeros_whatsapp` reprend les numeros exploitables
depuis le repertoire existant (`User.phone`) et **liste dans les logs les
fiches a corriger a la main**. Elle ne donne aucun consentement : connaitre un
numero n'est pas une autorisation d'envoi.

## 5. Droits

Le module `bulletin_whatsapp` est distinct de `reports` : un enseignant lit
les bulletins de ses classes sans pouvoir les diffuser aux familles. Il est
ouvert au super-administrateur et au directeur (administration), au censeur
(ecriture), et en lecture au promoteur.

## 6. Reglages

Voir `backend/.env.example` :

- `DEFAULT_PHONE_COUNTRY_CODE` (defaut `223`) et `NATIONAL_PHONE_LENGTH`
  (defaut `8`) ;
- `PUBLIC_BASE_URL` : **a renseigner en production** des que l'API repond
  derriere un domaine different de celui qu'atteint le telephone d'un parent.
  Vide, le lien est construit a partir de la requete, qui peut arriver par une
  adresse interne ;
- `BULLETIN_LINK_TTL_HOURS` (defaut `72`).

Le lien est signe par HMAC derive de `SECRET_KEY`. Une rotation de cette cle
invalide les liens deja envoyes -- sans gravite, ils durent trois jours.

## 7. Suivi des envois

Chaque preparation ouvre une ligne `BulletinDelivery` : eleve, parent, numero
**fige au jour de l'envoi**, periode, statut, motif d'echec. Les statuts sont
`prepared`, `sent`, `read` et `failed`.

`sent` est une **declaration de l'ecole** et non un accuse de reception : sur
le canal assiste, le serveur ne voit pas le message partir. `read`, en
revanche, est constate : c'est le premier telechargement du lien par la
famille. C'est ce statut qui dit quelles familles rappeler.

## 8. Passer a l'envoi automatique (etape 2)

Le canal `cloud_api` existe deja dans le modele et n'est emprunte par rien.
Quand les demarches Meta auront abouti, il restera a :

1. ajouter un modele `WhatsAppProviderConfig` calque sur `SmsProviderConfig`
   (jeton par etablissement, module d'acces dedie) ;
2. implementer un `CloudApiChannel` derriere l'interface deja en place dans
   `apps/reports/bulletin_delivery.py` ;
3. envoyer depuis une tache Celery (le worker tourne deja en production) et
   recevoir les statuts par webhook, pour alimenter `BulletinDelivery` ;
4. ajouter `httpx` aux dependances -- le backend n'emet aujourd'hui aucun
   appel HTTP sortant.

Le canal assiste reste alors le mode de repli : une passerelle qui tombe, ou
une facture impayee, ne doit pas laisser l'ecole sans moyen d'envoyer les
bulletins.
