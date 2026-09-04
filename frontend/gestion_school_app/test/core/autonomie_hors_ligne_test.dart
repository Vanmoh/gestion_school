/// L'application ne doit rien attendre d'Internet pour fonctionner.
///
/// Elle tourne sur le reseau d'une ecole, souvent sans acces exterieur. Trois
/// dependances s'y etaient glissees sans que rien ne les signale, et chacune
/// ne se constatait qu'une fois hors ligne, devant une classe:
///
/// - le paquet `printing` allait chercher pdf.js sur unpkg.com et attendait
///   ce script sans delai maximal: tout apercu de bulletin ou d'emploi du
///   temps tournait indefiniment;
/// - le moteur web telechargeait les polices Noto de secours sur
///   fonts.gstatic.com pour les glyphes absents d'Inter;
/// - rien ne verifiait la premiere ligne d'`index.html`.
///
/// Ces verifications lisent des fichiers plutot que des widgets: c'est le
/// seul moyen d'attraper une regression qui vit dans le HTML et le pubspec.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/core/theme/app_theme.dart';

/// Les hotes qu'une page servie sur un reseau ferme ne joindra jamais.
const _hotesInjoignables = [
  'unpkg.com',
  'cdn.jsdelivr.net',
  'cdnjs.cloudflare.com',
  'fonts.googleapis.com',
  'fonts.gstatic.com',
  'gstatic.com',
];

void main() {
  group('pdf.js est servi par nous', () {
    test('les deux fichiers sont dans le depot et sont entiers', () {
      final bibliotheque = File('web/pdfjs/pdf.min.js');
      final ouvrier = File('web/pdfjs/pdf.worker.min.js');

      expect(bibliotheque.existsSync(), isTrue, reason: 'web/pdfjs/pdf.min.js');
      expect(ouvrier.existsSync(), isTrue, reason: 'web/pdfjs/pdf.worker.min.js');
      // Un pointeur LFS, une page d'erreur du proxy ou un telechargement
      // interrompu tiennent en quelques kilo-octets -- et un pdf.min.js
      // tronque redonne exactement le symptome d'origine, l'apercu qui
      // tourne sans fin, puisque `onLoad` ne se declenche pas.
      expect(bibliotheque.lengthSync(), greaterThan(200 * 1024));
      expect(ouvrier.lengthSync(), greaterThan(900 * 1024));
    });

    test('index.html pose les deux verrous avant de lancer Flutter', () {
      final page = File('web/index.html').readAsStringSync();

      final base = page.indexOf("window.dartPdfJsBaseUrl = 'pdfjs/'");
      final precharge = page.indexOf('src="pdfjs/pdf.min.js"');
      final ouvrier = page.indexOf('GlobalWorkerOptions.workerSrc');
      final flutter = page.indexOf('src="flutter_bootstrap.js"');

      expect(base, greaterThan(-1), reason: 'le deroutement de l_injection');
      expect(precharge, greaterThan(-1), reason: 'le prechargement local');
      expect(ouvrier, greaterThan(-1), reason: 'le worker local');
      // L'ordre compte: charge apres Flutter, pdf.js pourrait arriver apres
      // le premier apercu, et l'injection distante aurait deja eu lieu.
      expect(precharge, lessThan(flutter));
    });
  });

  test('index.html ne charge aucune ressource d_un tiers', () {
    final page = File('web/index.html').readAsStringSync();

    // Viser les attributs qui declenchent une requete, et non la chaine
    // « http »: la page cite legitimement un lien MDN en commentaire et
    // l'espace de noms SVG du W3C.
    final requetes = RegExp(
      r'''(?:src|href)\s*=\s*["'](https?://[^"']+)["']''',
    ).allMatches(page).map((m) => m.group(1)!).toList();

    expect(
      requetes,
      isEmpty,
      reason: 'ces adresses ne repondront pas sur le reseau d_une ecole',
    );
  });

  group('les glyphes absents d_Inter ne se telechargent pas', () {
    test('la police de secours est embarquee et declaree', () {
      expect(File('assets/fonts/NotoEmoji-Regular.ttf').existsSync(), isTrue);
      // La licence accompagne la police, comme l'OFL d'Inter a cote.
      expect(File('assets/fonts/OFL-NotoEmoji.txt').existsSync(), isTrue);
      expect(
        File('pubspec.yaml').readAsStringSync(),
        contains('family: NotoEmoji'),
      );
    });

    test('le theme la nomme, sans quoi elle ne serait jamais consultee', () {
      final style = AppTheme.dark.textTheme.bodyMedium!;

      expect(style.fontFamily, 'Inter');
      expect(style.fontFamilyFallback, contains('NotoEmoji'));
    });
  });

  test('aucune adresse de tiers dans les sources web', () {
    final suspects = <String>[];
    for (final fichier in Directory('web').listSync(recursive: true)) {
      if (fichier is! File) continue;
      // pdf.js est du code minifie de Mozilla: il cite ses propres adresses
      // sans jamais les joindre. Ce sont nos pages qu'on surveille.
      if (fichier.path.contains('pdfjs/')) continue;
      if (!fichier.path.endsWith('.html') && !fichier.path.endsWith('.json')) {
        continue;
      }
      // Hors commentaires: nommer un CDN pour expliquer pourquoi on ne s'y
      // adresse plus est le contraire d'une dependance.
      final contenu = fichier
          .readAsStringSync()
          .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
      for (final hote in _hotesInjoignables) {
        if (contenu.contains(hote)) suspects.add('${fichier.path} -> $hote');
      }
    }

    expect(suspects, isEmpty);
  });
}
