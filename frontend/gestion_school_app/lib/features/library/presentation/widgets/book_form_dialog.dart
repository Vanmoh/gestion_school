import 'package:flutter/material.dart';

import '../../domain/book.dart';

/// Saisie d'un ouvrage: creation, ou correction d'une fiche existante.
///
/// La quantite disponible n'y figure pas, contrairement a l'ancien
/// formulaire: elle se deduit du total et des exemplaires sortis. La saisir
/// revenait a inviter l'utilisateur a mentir au compteur.
class BookFormDialog extends StatefulWidget {
  /// Nul pour une creation, renseigne pour une correction.
  final Book? livre;

  const BookFormDialog({super.key, this.livre});

  @override
  State<BookFormDialog> createState() => _BookFormDialogState();
}

class _BookFormDialogState extends State<BookFormDialog> {
  late final _titre = TextEditingController(text: widget.livre?.title ?? '');
  late final _auteur = TextEditingController(text: widget.livre?.author ?? '');
  late final _isbn = TextEditingController(text: widget.livre?.isbn ?? '');
  late final _total = TextEditingController(
    text: (widget.livre?.quantityTotal ?? 1).toString(),
  );
  late final _editeur = TextEditingController(text: widget.livre?.publisher ?? '');
  late final _annee = TextEditingController(
    text: widget.livre?.publishedYear?.toString() ?? '',
  );
  late final _matiere = TextEditingController(text: widget.livre?.subject ?? '');
  late final _cote = TextEditingController(
    text: widget.livre?.shelfLocation ?? '',
  );

  String? _erreur;

  @override
  void dispose() {
    _titre.dispose();
    _auteur.dispose();
    _isbn.dispose();
    _total.dispose();
    _editeur.dispose();
    _annee.dispose();
    _matiere.dispose();
    _cote.dispose();
    super.dispose();
  }

  void _valider() {
    final total = int.tryParse(_total.text.trim());
    if (_titre.text.trim().isEmpty ||
        _auteur.text.trim().isEmpty ||
        _isbn.text.trim().isEmpty) {
      setState(() => _erreur = 'Titre, auteur et ISBN sont obligatoires.');
      return;
    }
    if (total == null || total < 0) {
      setState(() => _erreur = 'Indiquez un nombre d’exemplaires valide.');
      return;
    }

    final sortis = widget.livre?.quantityBorrowed ?? 0;
    if (total < sortis) {
      // Le serveur le refuse aussi: le dire ici evite un aller-retour et une
      // erreur qui paraitrait arbitraire.
      setState(
        () => _erreur =
            '$sortis exemplaire(s) sont empruntés : le total ne peut pas '
            'descendre en dessous.',
      );
      return;
    }

    final anneeSaisie = _annee.text.trim();
    final annee = anneeSaisie.isEmpty ? null : int.tryParse(anneeSaisie);
    if (anneeSaisie.isNotEmpty && (annee == null || annee < 1400 || annee > 2200)) {
      setState(() => _erreur = 'Année d’édition invalide.');
      return;
    }

    Navigator.of(context).pop(
      BookFormResult(
        title: _titre.text.trim(),
        author: _auteur.text.trim(),
        isbn: _isbn.text.trim(),
        quantityTotal: total,
        publisher: _editeur.text.trim(),
        publishedYear: annee,
        subject: _matiere.text.trim(),
        shelfLocation: _cote.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final creation = widget.livre == null;
    return AlertDialog(
      title: Text(creation ? 'Ajouter un ouvrage' : 'Modifier l’ouvrage'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _titre,
                autofocus: creation,
                decoration: const InputDecoration(labelText: 'Titre'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _auteur,
                decoration: const InputDecoration(labelText: 'Auteur'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _isbn,
                decoration: const InputDecoration(labelText: 'ISBN'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _total,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Nombre d’exemplaires',
                  helperText: 'La disponibilité se déduit des emprunts en cours.',
                ),
              ),
              const SizedBox(height: 14),
              // Facultatifs, groupes a part: ce sont eux qui permettent de
              // retrouver un ouvrage en rayon, mais aucun n'est exige pour
              // enregistrer une fiche.
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Complements (facultatifs)',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _matiere,
                decoration: const InputDecoration(labelText: 'Matière'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _editeur,
                      decoration: const InputDecoration(labelText: 'Éditeur'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _annee,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Année'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _cote,
                decoration: const InputDecoration(
                  labelText: 'Cote / emplacement',
                  hintText: 'Étagère B3',
                ),
              ),
              if (_erreur != null) ...[
                const SizedBox(height: 12),
                Text(
                  _erreur!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _valider,
          child: Text(creation ? 'Ajouter' : 'Enregistrer'),
        ),
      ],
    );
  }
}

/// Ce que le formulaire rend quand il est valide.
class BookFormResult {
  final String title;
  final String author;
  final String isbn;
  final int quantityTotal;
  final String publisher;
  final int? publishedYear;
  final String subject;
  final String shelfLocation;

  const BookFormResult({
    required this.title,
    required this.author,
    required this.isbn,
    required this.quantityTotal,
    this.publisher = '',
    this.publishedYear,
    this.subject = '',
    this.shelfLocation = '',
  });
}
