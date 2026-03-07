# Exemple requête API depuis Flutter

Fichier concerné: `lib/features/auth/data/auth_repository.dart`

```dart
final tokenResponse = await dio.post(
  ApiConstants.login,
  data: {'username': username, 'password': password},
);

final access = tokenResponse.data['access'] as String;
final refresh = tokenResponse.data['refresh'] as String;
await tokenStorage.saveTokens(access: access, refresh: refresh);
```

Puis récupération du profil authentifié:

```dart
final profileResponse = await dio.get(ApiConstants.me);
```
