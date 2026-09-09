# Notifications aux familles: push, courriel, SMS

## Où en est le projet

Le module Communication écrivait ses notifications en base avec
`is_sent=False`, et **rien ne le repassait jamais à `True`**: aucune
passerelle n'existait. Les familles ne recevaient rien.

Ce qui est en place aujourd'hui, et testé:

| Élément | État |
|---|---|
| Modèle `DeviceToken` (un jeton par appareil) | ✅ |
| API `POST/DELETE /api/auth/device-token/` | ✅ |
| Fermeture du jeton à la déconnexion | ✅ |
| Service d'envoi FCM HTTP v1 (`apps/common/push.py`) | ✅ |
| Tâche Celery qui vide la file toutes les 5 min | ✅ |
| Fermeture automatique des jetons morts | ✅ |
| Contrôle de déploiement `gestion_school.W006` | ✅ |
| Permission Android `POST_NOTIFICATIONS` | ✅ |
| **Client Flutter (`firebase_messaging`)** | ⛔ **reste à faire** |
| Courriel (SMTP) | ✅ |
| SMS (passerelle par établissement) | ✅ |

Le client Flutter n'est pas branché, et c'est délibéré: le plugin
`firebase_messaging` exige un fichier `google-services.json` issu d'un projet
Firebase. Sans ce fichier, **le build Android échoue**. Il faut donc créer le
projet Firebase avant d'ajouter la dépendance.

## 1) Créer le projet Firebase

1. <https://console.firebase.google.com> → **Ajouter un projet**.
2. Ajouter une application **Android**, avec le `applicationId` de l'app
   (voir `android/app/build.gradle.kts`; il vaut aujourd'hui
   `com.example.gestion_school_app`, à changer avant publication).
3. Télécharger `google-services.json` → le placer dans
   `frontend/gestion_school_app/android/app/`.
4. **Paramètres du projet → Comptes de service → Générer une nouvelle clé
   privée**: c'est le fichier que le serveur utilisera.

## 2) Configurer le serveur

Sur un serveur d'école (disque persistant):

```bash
FCM_PROJECT_ID=mon-projet-firebase
FCM_CREDENTIALS_FILE=/etc/gestion-school/compte-de-service.json
```

Sur Render ou tout hébergeur sans disque persistant, coller le contenu du
fichier dans une variable:

```bash
FCM_PROJECT_ID=mon-projet-firebase
FCM_CREDENTIALS_JSON={"type":"service_account","project_id":"...",...}
```

Vérifier:

```bash
cd backend
python manage.py check --deploy     # W006 doit disparaître
```

Sans ces variables, l'application continue de fonctionner: les notifications
restent consultables dans l'écran Communication, simplement personne n'est
alerté.

## 3) Brancher le client Flutter

À faire une fois `google-services.json` en place:

```yaml
# pubspec.yaml
dependencies:
  firebase_core: ^3.8.0
  firebase_messaging: ^15.1.5
```

Puis, après connexion, enregistrer le jeton auprès du serveur:

```dart
final jeton = await FirebaseMessaging.instance.getToken();
if (jeton != null) {
  await dio.post('/auth/device-token/', data: {
    'token': jeton,
    'platform': 'android',
  });
}
// Firebase renouvelle le jeton sans prévenir: il faut suivre.
FirebaseMessaging.instance.onTokenRefresh.listen((jeton) {
  dio.post('/auth/device-token/', data: {'token': jeton, 'platform': 'android'});
});
```

Sur Android 13 et au-delà, demander l'autorisation au premier lancement:

```dart
await FirebaseMessaging.instance.requestPermission();
```

À la déconnexion, passer le jeton à `/auth/logout/` (champ `device_token`):
sur un téléphone partagé, le compte suivant verrait sinon passer les
notifications du précédent.

## 4) Vérifier de bout en bout

```bash
cd backend
python manage.py shell -c "
from apps.common.push import envoyer_a_des_appareils
print(envoyer_a_des_appareils(['<jeton-du-telephone>'], titre='Test', message='Bonjour'))
"
```

Un `ResultatEnvoi(envoyes=1)` confirme la chaîne complète.

## Les deux autres canaux

Le courriel et le SMS sont branchés eux aussi
(`backend/apps/common/messagerie.py`), sur le même patron: sans
configuration, l'envoi échoue proprement et la notification reste en base
pour un envoi ultérieur. Un canal fermé n'empêche jamais les autres de
partir.

### Courriel

```bash
EMAIL_HOST=smtp.exemple.ml
EMAIL_PORT=587
EMAIL_HOST_USER=ecole@exemple.ml
EMAIL_HOST_PASSWORD=<mot de passe d'application>
EMAIL_USE_TLS=True
DEFAULT_FROM_EMAIL=ecole@exemple.ml
```

Chez la plupart des fournisseurs, `EMAIL_HOST_PASSWORD` est un **mot de passe
d'application**, pas celui du compte — que la validation en deux étapes
refuse de toute façon. Sans `EMAIL_HOST`, Django écrit les messages sur la
sortie standard et le contrôle `gestion_school.W007` le signale.

### SMS

Rien à mettre dans l'environnement: la passerelle se déclare **par
établissement**, dans l'application (Communication → Fournisseurs SMS), car
le contrat est signé par l'école.

| Champ | Ce qu'il porte |
|---|---|
| Nom du fournisseur | Sert à choisir la convention de champs (Orange, Twilio, Vonage…) |
| URL de l'API | Le point d'entrée `POST` du fournisseur |
| Jeton | Envoyé en `Authorization: Bearer …` |
| Identifiant d'expéditeur | Le nom affiché sur le téléphone (souvent à faire déclarer chez l'opérateur) |

Ce qui change d'un fournisseur à l'autre est le nom des champs, pas la forme
de l'appel; un fournisseur exotique se traite en ajoutant une entrée à
`CHAMPS_PAR_FOURNISSEUR`, sans toucher au reste.

Le refus du fournisseur — crédit épuisé, expéditeur non déclaré, numéro
invalide — est conservé dans les journaux: c'est lui qui permet à l'école
d'agir.

### Vérifier

```bash
cd backend
python manage.py check --deploy    # W006 (push) et W007 (courriel)
```
