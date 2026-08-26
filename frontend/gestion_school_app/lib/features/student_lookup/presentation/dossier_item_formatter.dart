/// Une ligne du dossier, prete a afficher.
class DossierLine {
  final String title;
  final String subtitle;

  /// Valeur mise en avant a droite (note, montant, statut).
  final String trailing;

  const DossierLine({
    required this.title,
    this.subtitle = '',
    this.trailing = '',
  });
}

/// Traduit un element brut de section en ligne lisible.
///
/// Le serveur renvoie les champs du modele plus un bloc `labels` pour les
/// relations, car plusieurs serializers partages n'exposent que des
/// identifiants. Toute la mise en forme vit ici: repartie dans les widgets,
/// elle divergeait d'une section a l'autre.
DossierLine formatDossierItem(String sectionKey, Map<String, dynamic> item) {
  final labels = item['labels'] is Map
      ? Map<String, dynamic>.from(item['labels'] as Map)
      : const <String, dynamic>{};

  String label(String key) => _text(labels[key]);

  switch (sectionKey) {
    case 'history':
      return DossierLine(
        title: _join([label('annee'), label('classe')], ' — '),
        subtitle: _join([
          if (_has(item['rank'])) 'Rang ${_number(item['rank'])}',
        ], ' · '),
        trailing: _has(item['average']) ? '${_number(item['average'])}/20' : '',
      );

    case 'promotion':
      return DossierLine(
        title: label('decision'),
        subtitle: _join([
          _join([
            _text(item['source_classroom_name']),
            _text(item['target_classroom_name']),
          ], ' → '),
          label('annee'),
        ], ' · '),
        trailing: _has(item['average']) ? '${_number(item['average'])}/20' : '',
      );

    case 'grades':
      return DossierLine(
        title: label('matiere'),
        subtitle: _join([
          _text(item['term']),
          label('classe'),
          label('annee'),
        ], ' · '),
        trailing: _has(item['value']) ? '${_number(item['value'])}/20' : '',
      );

    case 'attendance':
      final absent = item['is_absent'] == true;
      final retard = item['is_late'] == true;
      return DossierLine(
        title: _date(item['date']),
        subtitle: _text(item['reason']),
        trailing: absent ? 'Absent' : (retard ? 'Retard' : 'Présent'),
      );

    case 'discipline':
      return DossierLine(
        // Le libelle servi par le referentiel, a defaut le code brut: depuis
        // que le motif est une liste fermee, `category` vaut « indiscipline »
        // la ou le dossier affichait « Indiscipline ».
        title: _has(item['category_label'])
            ? _text(item['category_label'])
            : _text(item['category']),
        subtitle: _join([
          _date(item['incident_date']),
          _text(item['description']),
        ], ' · '),
        trailing: _text(item['status']) == 'resolved' ? 'Résolu' : 'Ouvert',
      );

    case 'fees':
      return DossierLine(
        title: label('type'),
        subtitle: _join([
          label('annee'),
          if (_has(item['due_date'])) 'Échéance ${_date(item['due_date'])}',
          if (_has(item['amount_paid'])) 'Payé ${_money(item['amount_paid'])}',
        ], ' · '),
        trailing: _has(item['balance'])
            ? 'Reste ${_money(item['balance'])}'
            : _money(item['amount_due']),
      );

    case 'payments':
      final annule = item['is_cancelled'] == true;
      return DossierLine(
        title: _money(item['amount']),
        subtitle: _join([
          _text(item['method']),
          _text(item['fee_type']),
          _date(item['created_at']),
        ], ' · '),
        trailing: annule ? 'Annulé' : '',
      );

    case 'exams':
      return DossierLine(
        title: label('matiere'),
        subtitle: label('session'),
        trailing: _has(item['score']) ? '${_number(item['score'])}/20' : '',
      );

    case 'library':
      final rendu = _has(item['returned_at']);
      return DossierLine(
        title: label('livre'),
        subtitle: _join([
          label('auteur'),
          if (_has(item['borrowed_at'])) 'Emprunté le ${_date(item['borrowed_at'])}',
          if (_has(item['due_date'])) 'À rendre le ${_date(item['due_date'])}',
        ], ' · '),
        trailing: rendu ? 'Rendu' : 'En cours',
      );

    case 'canteen_subscriptions':
      return DossierLine(
        title: label('annee'),
        subtitle: _join([
          if (_has(item['start_date'])) 'Depuis le ${_date(item['start_date'])}',
          if (_has(item['daily_limit'])) '${_number(item['daily_limit'])} repas/jour',
        ], ' · '),
        trailing: label('statut'),
      );

    case 'canteen_services':
      return DossierLine(
        title: label('menu'),
        subtitle: _join([
          _date(item['served_on']),
          if (_has(item['quantity'])) 'x${_number(item['quantity'])}',
        ], ' · '),
        trailing: item['is_paid'] == true ? 'Payé' : 'Impayé',
      );
  }

  // Section inconnue: mieux vaut afficher l'identifiant que rien du tout.
  return DossierLine(title: '#${_text(item['id'])}');
}

String _text(dynamic value) => value?.toString().trim() ?? '';

bool _has(dynamic value) {
  final text = _text(value);
  return text.isNotEmpty && text != 'null';
}

String _join(List<String> parts, String separator) =>
    parts.where((part) => part.isNotEmpty).join(separator);

/// `12.00` se lit `12`, `12.50` se lit `12.5`: les zeros finaux encombrent
/// une colonne de notes sans rien apporter.
String _number(dynamic value) {
  final text = _text(value);
  if (text.isEmpty) return '';
  final parsed = double.tryParse(text);
  if (parsed == null) return text;
  if (parsed == parsed.roundToDouble()) return parsed.toStringAsFixed(0);
  return parsed
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
}

/// Montants en francs CFA, separes par milliers.
///
/// Expose pour que les resumes de rubrique et les lignes depliees suivent la
/// meme regle: « Total dû : 85000 » a cote de « Reste 35 000 F » se lit comme
/// deux unites differentes.
String formatDossierMoney(num value) => _money(value);

String _money(dynamic value) {
  final text = _text(value);
  if (text.isEmpty) return '';
  final parsed = double.tryParse(text);
  if (parsed == null) return text;
  final entier = parsed.round().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < entier.length; index++) {
    if (index > 0 && (entier.length - index) % 3 == 0) buffer.write(' ');
    buffer.write(entier[index]);
  }
  return '$buffer F';
}

String _date(dynamic value) {
  final text = _text(value);
  if (text.isEmpty) return '';
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return text;
  final jour = parsed.day.toString().padLeft(2, '0');
  final mois = parsed.month.toString().padLeft(2, '0');
  return '$jour/$mois/${parsed.year}';
}
