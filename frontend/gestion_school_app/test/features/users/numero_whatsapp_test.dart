/// Le numéro qui sert vraiment à l'envoi des bulletins.
///
/// Il en existe deux: `phone`, champ de répertoire modifié dans Gestion
/// utilisateurs, et le numéro WhatsApp, seul utilisé pour l'envoi. On
/// corrigeait le premier en croyant avoir tout fait, et l'envoi partait sur
/// l'ancien numéro — ou sur rien.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/users/domain/user_account.dart';

Map<String, dynamic> _json({
  String phone = '76 12 34 56',
  String whatsapp = '',
  bool consent = false,
  String suggestion = '',
}) {
  return {
    'id': 7,
    'username': 'awa.traore',
    'first_name': 'Awa',
    'last_name': 'Traoré',
    'email': 'awa@ecole.ml',
    'role': 'parent',
    'phone': phone,
    'whatsapp_phone': whatsapp,
    'whatsapp_consent': consent,
    'whatsapp_phone_suggestion': suggestion,
  };
}

void main() {
  group('lecture de la fiche', () {
    test('les trois champs sont repris du serveur', () {
      final compte = UserAccount.fromJson(
        _json(whatsapp: '+22376123456', consent: true, suggestion: ''),
      );

      expect(compte.whatsappPhone, '+22376123456');
      expect(compte.whatsappConsent, isTrue);
      expect(compte.whatsappPhoneSuggestion, '');
    });

    test('un serveur qui ne les sert pas ne casse rien', () {
      // Une version antérieure de l'API ne renvoie pas ces champs.
      final compte = UserAccount.fromJson({
        'id': 7,
        'username': 'awa',
        'role': 'parent',
      });

      expect(compte.whatsappPhone, '');
      expect(compte.whatsappConsent, isFalse);
      expect(compte.whatsappPhoneSuggestion, '');
    });

    test('la suggestion arrive quand le numéro manque', () {
      final compte = UserAccount.fromJson(
        _json(whatsapp: '', suggestion: '+22376123456'),
      );

      expect(compte.whatsappPhone, isEmpty);
      expect(compte.whatsappPhoneSuggestion, '+22376123456');
    });
  });

  group('peut recevoir par WhatsApp', () {
    test('il faut un numéro et l_accord du parent', () {
      final compte = UserAccount.fromJson(
        _json(whatsapp: '+22376123456', consent: true),
      );

      expect(compte.peutRecevoirParWhatsApp, isTrue);
    });

    test('un numéro sans accord ne suffit pas', () {
      // Un bulletin est une donnée scolaire d'un mineur: son passage sur un
      // service tiers se demande avant, pas après.
      final compte = UserAccount.fromJson(
        _json(whatsapp: '+22376123456', consent: false),
      );

      expect(compte.peutRecevoirParWhatsApp, isFalse);
    });

    test('un accord sans numéro ne suffit pas non plus', () {
      final compte = UserAccount.fromJson(_json(whatsapp: '', consent: true));

      expect(compte.peutRecevoirParWhatsApp, isFalse);
    });

    test('un numéro fait d_espaces ne compte pas', () {
      final compte = UserAccount.fromJson(
        _json(whatsapp: '   ', consent: true),
      );

      expect(compte.peutRecevoirParWhatsApp, isFalse);
    });

    test('le téléphone de répertoire n_y change rien', () {
      // C'est tout le piège: il est rempli, et l'envoi ne part pas.
      final compte = UserAccount.fromJson(
        _json(phone: '76 12 34 56', whatsapp: '', consent: true),
      );

      expect(compte.phone, isNotEmpty);
      expect(compte.peutRecevoirParWhatsApp, isFalse);
    });
  });
}
