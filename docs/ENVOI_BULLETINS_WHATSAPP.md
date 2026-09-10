# Envoi des bulletins aux familles par WhatsApp

## 1. Ce que fait la fonction aujourd'hui

Depuis **Rapports > Envoyer aux familles (WhatsApp)**, l'ecole ouvre la liste
d'une classe. Un bandeau y dit si les bulletins de la periode sont arretes --
sans quoi rien ne part (voir §4). Pour chaque eleve, l'ecran dit ensuite si le
bulletin peut partir et, sinon, ce qui manque. Un clic sur « Envoyer » ouvre WhatsApp avec le message
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
| Les bulletins de la periode ne sont pas valides | Valider la periode (voir §4) |
| Cet eleve n'est affecte a aucune classe | L'affecter depuis le module Eleves |
| Aucun parent rattache a cet eleve | Rattacher un parent depuis le module Eleves |
| Numero WhatsApp du parent absent / invalide | « Corriger le contact » sur la ligne |
| Le parent n'a pas donne son accord | Recueillir l'accord, puis cocher la case |
| Aucune note saisie pour la periode | Saisir les notes : le bulletin serait vide |

Un bulletin deja envoye pour la meme periode n'est pas renvoye sans
confirmation explicite.

## 4. Validation de la periode

Aucun bulletin ne part d'une periode qui n'a pas ete arretee. La validation
se fait classe par classe et periode par periode, depuis le bandeau en haut
de l'ecran d'envoi -- ou par l'API `/api/bulletin-publications/` :

- `POST /api/bulletin-publications/publish/` avec `classroom`, `academic_year`,
  `term` et un `notes` facultatif ;
- `POST /api/bulletin-publications/unpublish/` avec les memes trois champs ;
- `GET /api/bulletin-publications/status/?classroom=&academic_year=&term=`
  repond meme quand la periode n'a jamais ete validee.

Trois choses a savoir :

1. **Le defaut est « non validee »**, y compris pour les periodes qui n'ont
   aucune ligne en base. C'est volontaire : la fonction s'ouvre sur des annees
   deja saisies, et l'inverse aurait fait partir d'un coup tous les bulletins
   de l'historique a la premiere mise a jour.
2. **L'impression reste libre.** Seule la diffusion aux familles exige la
   validation : le secretariat doit pouvoir sortir un brouillon pour le
   conseil de classe sans avoir rien arrete.
3. **Rouvrir une periode ne rappelle rien.** Un message WhatsApp deja parti
   ne revient pas ; la reouverture sert a corriger avant le prochain envoi.

Le module d'acces est `bulletin_validation`, distinct de `grades` : un
enseignant saisit les notes de ses classes (`grades` en ecriture) et n'a pas
a decider que le trimestre est clos. Il lit en revanche l'etat de ses propres
classes -- c'est ce qui lui dit que ses moyennes ne bougeront plus.

## 5. Numeros de telephone

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

## 6. Droits

Deux modules, deux actes distincts. `bulletin_validation` arrete les
bulletins d'une periode ; `bulletin_whatsapp` les diffuse. Ce dernier est
separe de `reports` : un enseignant lit les bulletins de ses classes sans
pouvoir les envoyer aux familles. Il est
ouvert au super-administrateur et au directeur (administration), au censeur
(ecriture), et en lecture au promoteur.

## 7. Reglages

Voir `backend/.env.example` :

- `DEFAULT_PHONE_COUNTRY_CODE` (defaut `223`) et `NATIONAL_PHONE_LENGTH`
  (defaut `8`) ;
- `PUBLIC_BASE_URL` : **deduite de `ALLOWED_HOSTS` quand elle n'est pas
  renseignee**. L'API repond deja sur son domaine public, qui figure dans
  `ALLOWED_HOSTS` : l'exiger une seconde fois revenait a compter sur une
  configuration manuelle qui n'avait jamais ete faite. Un reglage explicite
  l'emporte toujours -- une ecole derriere un reverse proxy sur un autre
  domaine le pose ici.

  Ce qui suit reste vrai du mecanisme : L'envoi refuse desormais de partir
  quand le lien ne sortirait pas du reseau local (adresse privee, `localhost`,
  ou reglage absent). Sans elle, le lien reprenait l'adresse de la requete :
  prepare depuis l'application servie en Wi-Fi, il portait
  `http://192.168.x.x:8000` -- inatteignable depuis la connexion mobile d'un
  parent, et pas meme cliquable dans WhatsApp, qui ne linkifie pas une IP
  privee avec un port. Elle est renseignee dans `render.yaml` et
  `render.staging.yaml` ; le controle `gestion_school.W008` le signale au
  demarrage.

  Ancienne mention, conservee pour memoire : **a renseigner en production** des que l'API repond
  derriere un domaine different de celui qu'atteint le telephone d'un parent.
  Vide, le lien est construit a partir de la requete, qui peut arriver par une
  adresse interne ;
- `BULLETIN_LINK_TTL_HOURS` (defaut `72`).

Le lien est signe par HMAC derive de `SECRET_KEY`. Une rotation de cette cle
invalide les liens deja envoyes -- sans gravite, ils durent trois jours.

## 8. Suivi des envois

Chaque preparation ouvre une ligne `BulletinDelivery` : eleve, parent, numero
**fige au jour de l'envoi**, periode, statut, motif d'echec. Les statuts sont
`prepared`, `sent`, `read` et `failed`.

`sent` est une **declaration de l'ecole** et non un accuse de reception : sur
le canal assiste, le serveur ne voit pas le message partir. `read`, en
revanche, est constate : c'est le premier telechargement du lien par la
famille. C'est ce statut qui dit quelles familles rappeler.

## 9. Passer a l'envoi automatique (etape 2)

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

## Le numero du parent : il y en a deux

| Champ | Ou il se regle | A quoi il sert |
|---|---|---|
| Telephone | Gestion utilisateurs | Repertoire. Champ libre : peut porter deux numeros ou une note (« bureau ») |
| Numero WhatsApp | Gestion utilisateurs, sur la fiche d'un parent | L'envoi. Format strict E.164 |

Les deux sont distincts a dessein : imposer le format E.164 a toutes les
fiches existantes aurait bloque leur simple reenregistrement.

**Le numero WhatsApp suit desormais le telephone tout seul.** Corriger le
telephone dans Gestion utilisateurs met a jour le numero d'envoi, a la
creation du parent comme a chaque modification. Deux exceptions, voulues :

- un numero WhatsApp **saisi volontairement different** n'est jamais ecrase.
  C'est le cas du portable du tuteur quand la fiche porte le fixe du
  domicile : une fois les deux dissocies, ils le restent ;
- un telephone **illisible** ne produit rien plutot qu'un numero devine.
  « 76 12 34 56 / bureau 66 74 22 32 » ne se tranche pas tout seul, et
  choisir au hasard enverrait le bulletin d'un eleve chez quelqu'un d'autre.

Vider le telephone n'efface pas le numero d'envoi : effacer un contact ne
doit pas couper les envois en silence.

Mais corriger le telephone ne changeait rien a l'envoi, et rien ne le disait.
La fiche d'un parent porte desormais les deux champs cote a cote. Quand le
numero WhatsApp est vide, un bouton propose le telephone converti -- propose,
jamais ecrit d'office : un « 76 12 34 56 / bureau 66 74 22 32 » ne se tranche
pas tout seul.

L'accord du parent s'affiche sous le champ : sans lui, aucun envoi n'est
prepare, quel que soit le numero.
