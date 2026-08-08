import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/network/media_url.dart';

void main() {
  const base = 'https://api.exemple.test/api/';

  test('une URL absolue est rendue intacte', () {
    // Le stockage objet signe ses liens: y toucher casserait la signature.
    const signee =
        'https://projet.storage.supabase.co/media/students/a.jpg?X-Amz-Signature=abc';

    expect(resolveMediaUrl(signee, base), signee);
  });

  test('un chemin relatif est resolu contre la base de l_API', () {
    expect(
      resolveMediaUrl('/media/students/photo.jpg', base),
      'https://api.exemple.test/media/students/photo.jpg',
    );
  });

  test('une valeur vide ne produit pas une adresse bancale', () {
    expect(resolveMediaUrl('', base), '');
    expect(resolveMediaUrl('   ', base), '');
  });

  test('sans base connue, le chemin est conserve tel quel', () {
    // Perdre le chemin rendrait le diagnostic impossible cote appelant.
    expect(resolveMediaUrl('/media/a.jpg', ''), '/media/a.jpg');
  });

  test('les espaces autour de la valeur ne changent rien', () {
    expect(
      resolveMediaUrl('  /media/a.jpg  ', base),
      'https://api.exemple.test/media/a.jpg',
    );
  });
}
