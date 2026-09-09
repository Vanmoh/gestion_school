# Notifications push (Firebase Cloud Messaging)

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

## Ce qui reste fermé

- **SMS**: `SmsProviderConfig` stocke une URL et un jeton que rien n'appelle.
  Les notifications de canal SMS restent en attente — elles ne sont pas
  marquées envoyées, ce qui serait mentir sur ce qui est parti.
- **Courriel**: aucun `EMAIL_BACKEND` n'est configuré.

Ces deux canaux suivent le même patron que le push: un service d'envoi, et la
tâche `envoyer_les_notifications_en_attente` qui apprend à les traiter.
