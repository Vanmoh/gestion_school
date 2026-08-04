import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/student_lookup/presentation/dossier_item_formatter.dart';

void main() {
  group('notes', () {
    test('la note perd ses zeros inutiles mais garde ses decimales', () {
      // Une colonne de "12.00" est illisible; "12.50" doit rester "12.5".
      expect(
        formatDossierItem('grades', {
          'value': '12.00',
          'labels': {'matiere': 'Maths'},
        }).trailing,
        '12/20',
      );
      expect(
        formatDossierItem('grades', {
          'value': '12.50',
          'labels': {'matiere': 'Maths'},
        }).trailing,
        '12.5/20',
      );
    });

    test('le libelle de matiere vient du serveur, pas de l_identifiant', () {
      final line = formatDossierItem('grades', {
        'subject': 7,
        'term': 'T1',
        'labels': {'matiere': 'Histoire', 'annee': '2025-2026'},
      });

      expect(line.title, 'Histoire');
      expect(line.subtitle, contains('T1'));
      expect(line.subtitle, contains('2025-2026'));
    });

    test('sans libelle, la ligne ne montre pas un identifiant brut', () {
      expect(formatDossierItem('grades', {'subject': 7}).title, '');
    });
  });

  group('montants', () {
    test('les milliers sont separes et suivis du franc', () {
      final line = formatDossierItem('payments', {'amount': '125000.00'});

      expect(line.title, '125 000 F');
    });

    test('un paiement annule est signale', () {
      expect(
        formatDossierItem('payments', {
          'amount': '1000',
          'is_cancelled': true,
        }).trailing,
        'Annulé',
      );
      expect(
        formatDossierItem('payments', {
          'amount': '1000',
          'is_cancelled': false,
        }).trailing,
        '',
      );
    });

    test('le solde restant prime sur le montant du', () {
      final line = formatDossierItem('fees', {
        'amount_due': '100000',
        'amount_paid': '40000',
        'balance': '60000',
        'labels': {'type': 'Frais inscription'},
      });

      expect(line.title, 'Frais inscription');
      expect(line.trailing, 'Reste 60 000 F');
      expect(line.subtitle, contains('Payé 40 000 F'));
    });
  });

  group('dates', () {
    test('les dates ISO deviennent jour/mois/annee', () {
      expect(
        formatDossierItem('attendance', {'date': '2026-03-07'}).title,
        '07/03/2026',
      );
    });

    test('une date illisible est rendue telle quelle plutot que perdue', () {
      expect(
        formatDossierItem('attendance', {'date': 'inconnue'}).title,
        'inconnue',
      );
    });
  });

  group('statuts', () {
    test('absence, retard et presence se distinguent', () {
      expect(
        formatDossierItem('attendance', {
          'date': '2026-03-07',
          'is_absent': true,
        }).trailing,
        'Absent',
      );
      expect(
        formatDossierItem('attendance', {
          'date': '2026-03-07',
          'is_late': true,
        }).trailing,
        'Retard',
      );
      expect(
        formatDossierItem('attendance', {'date': '2026-03-07'}).trailing,
        'Présent',
      );
    });

    test('un emprunt rendu se distingue d_un emprunt en cours', () {
      expect(
        formatDossierItem('library', {
          'labels': {'livre': 'L Etranger'},
          'returned_at': '2026-03-01',
        }).trailing,
        'Rendu',
      );
      expect(
        formatDossierItem('library', {
          'labels': {'livre': 'L Etranger'},
        }).trailing,
        'En cours',
      );
    });
  });

  test('une section inconnue reste identifiable au lieu de disparaitre', () {
    expect(formatDossierItem('inattendue', {'id': 42}).title, '#42');
  });
}
