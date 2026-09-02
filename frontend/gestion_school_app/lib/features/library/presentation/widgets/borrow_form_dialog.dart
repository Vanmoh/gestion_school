import 'package:flutter/material.dart';

import '../../domain/book.dart';

/// Un eleve tel que le formulaire de pret a besoin de le connaitre.
typedef OptionEleve = ({int id, String matricule, String nom});

/// Enregistrement d'un pret: qui, quel ouvrage, jusqu'a quand.
///
/// Seuls les ouvrages ayant un exemplaire en rayon sont proposes: la liste
/// entiere laissait preter un livre deja sorti, et le serveur refusait
/// ensuite une saisie que rien n'avait decouragee.
class BorrowFormDialog extends StatefulWidget {
  final List<Book> livres;
  final List<OptionEleve> eleves;

  /// Duree de pret proposee par defaut, en jours.
  final int dureeParDefaut;

  const BorrowFormDialog({
    super.key,
    required this.livres,
    required this.eleves,
    this.dureeParDefaut = 14,
  });

  @override
  State<BorrowFormDialog> createState() => _BorrowFormDialogState();
}

class _BorrowFormDialogState extends State<BorrowFormDialog> {
  int? _eleve;
  int? _livre;
  late DateTime _emprunt = DateTime.now();
  late DateTime _echeance = DateTime.now().add(
    Duration(days: widget.dureeParDefaut),
  );
  String? _erreur;

  List<Book> get _disponibles =>
      widget.livres.where((livre) => livre.estDisponible).toList();

  @override
  void initState() {
    super.initState();
    _eleve = widget.eleves.isEmpty ? null : widget.eleves.first.id;
    _livre = _disponibles.isEmpty ? null : _disponibles.first.id;
  }

  Future<void> _choisirDate({required bool echeance}) async {
    final initiale = echeance ? _echeance : _emprunt;
    final choix = await showDatePicker(
      context: context,
      initialDate: initiale,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (choix == null) return;
    setState(() {
      if (echeance) {
        _echeance = choix;
      } else {
        _emprunt = choix;
        // L'échéance suit l'emprunt quand elle le precede: une date de
        // retour anterieure au pret est refusee par le serveur.
        if (_echeance.isBefore(choix)) {
          _echeance = choix.add(Duration(days: widget.dureeParDefaut));
        }
      }
    });
  }

  void _valider() {
    if (_eleve == null || _livre == null) {
      setState(() => _erreur = 'Sélectionnez un élève et un ouvrage.');
      return;
    }
    if (_echeance.isBefore(_emprunt)) {
      setState(() => _erreur = 'La date de retour précède la date d’emprunt.');
      return;
    }
    Navigator.of(context).pop(
      BorrowFormResult(
        studentId: _eleve!,
        bookId: _livre!,
        borrowedAt: _emprunt,
        dueDate: _echeance,
      ),
    );
  }

  String _jour(DateTime valeur) {
    final mois = valeur.month.toString().padLeft(2, '0');
    final jour = valeur.day.toString().padLeft(2, '0');
    return '$jour/$mois/${valeur.year}';
  }

  @override
  Widget build(BuildContext context) {
    final disponibles = _disponibles;

    return AlertDialog(
      title: const Text('Enregistrer un emprunt'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (disponibles.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Aucun ouvrage n’a d’exemplaire disponible actuellement.',
                  ),
                )
              else ...[
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: _eleve,
                  decoration: const InputDecoration(labelText: 'Élève'),
                  items: [
                    for (final eleve in widget.eleves)
                      DropdownMenuItem(
                        value: eleve.id,
                        child: Text('${eleve.matricule} • ${eleve.nom}'),
                      ),
                  ],
                  onChanged: (valeur) => setState(() => _eleve = valeur),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: _livre,
                  decoration: const InputDecoration(labelText: 'Ouvrage'),
                  items: [
                    for (final livre in disponibles)
                      DropdownMenuItem(
                        value: livre.id,
                        child: Text(
                          '${livre.title} (${livre.quantityAvailable} dispo.)',
                        ),
                      ),
                  ],
                  onChanged: (valeur) => setState(() => _livre = valeur),
                ),
                const SizedBox(height: 6),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date d’emprunt'),
                  subtitle: Text(_jour(_emprunt)),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: () => _choisirDate(echeance: false),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Retour attendu'),
                  subtitle: Text(_jour(_echeance)),
                  trailing: const Icon(Icons.event_available),
                  onTap: () => _choisirDate(echeance: true),
                ),
                // Plus de champ « pénalité »: elle etait saisie ici, avant
                // meme qu'il y ait retard. Elle se calcule au retour, au
                // tarif journalier de l'etablissement.
              ],
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
          onPressed: disponibles.isEmpty ? null : _valider,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class BorrowFormResult {
  final int studentId;
  final int bookId;
  final DateTime borrowedAt;
  final DateTime dueDate;

  const BorrowFormResult({
    required this.studentId,
    required this.bookId,
    required this.borrowedAt,
    required this.dueDate,
  });
}
