import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/permissions/module_permissions.dart';
import '../domain/book.dart';
import 'library_controller.dart';
import 'widgets/book_form_dialog.dart';
import 'widgets/books_panel.dart';
import 'widgets/borrow_form_dialog.dart';
import 'widgets/borrows_panel.dart';

/// Le fonds papier: le catalogue, les prets, les retours.
///
/// L'ecran ne savait que creer -- un livre, un emprunt -- et rien reprendre:
/// pas de retour, pas de correction de fiche, pas de recherche, et un
/// compteur de disponibilite saisi a la main qui ne bougeait jamais. Le
/// serveur tient desormais ces comptes; cette page se contente de les
/// montrer et d'appeler les actions correspondantes.
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  bool _chargement = true;
  bool _enCours = false;

  List<Book> _livres = const [];
  List<Borrow> _emprunts = const [];
  List<OptionEleve> _eleves = const [];

  String _recherche = '';
  String _filtreDisponibilite = '';
  String _filtreEmprunts = '';

  /// Lu hors du `build` -- au chargement notamment, ou il decide si la liste
  /// des eleves doit seulement etre demandee.
  bool get _peutEcrire =>
      ref.read(currentPermissionsProvider).canWrite('library');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _charger());
  }

  Future<void> _charger() async {
    setState(() => _chargement = true);
    try {
      final depot = ref.read(booksRepositoryProvider);
      final livres = await depot.fetchBooks(
        search: _recherche,
        availability: _filtreDisponibilite,
      );
      final emprunts = await depot.fetchBorrows(status: _filtreEmprunts);
      // La liste des eleves ne sert qu'a enregistrer un pret, et le module
      // « eleves » est ferme aux profils en lecture: la demander pour eux
      // faisait echouer le chargement entier de l'onglet sur un 403.
      final eleves = _peutEcrire ? await _chargerEleves() : const <OptionEleve>[];

      if (!mounted) return;
      setState(() {
        _livres = livres;
        _emprunts = emprunts;
        _eleves = eleves;
      });
    } catch (error) {
      if (!mounted) return;
      _signaler(_message(error, 'Erreur chargement bibliothèque.'));
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<List<OptionEleve>> _chargerEleves() async {
    final reponse = await ref.read(dioProvider).get(
      '/students/',
      queryParameters: {'page_size': 500},
    );
    final data = reponse.data;
    final lignes = data is Map<String, dynamic> && data['results'] is List
        ? data['results'] as List<dynamic>
        : (data is List<dynamic> ? data : const <dynamic>[]);

    return lignes
        .whereType<Map>()
        .map(
          (ligne) => (
            id: (ligne['id'] as num?)?.toInt() ?? 0,
            matricule: ligne['matricule']?.toString() ?? '',
            nom: ligne['user_full_name']?.toString() ?? '',
          ),
        )
        .where((eleve) => eleve.id > 0)
        .toList(growable: false);
  }

  // --- Catalogue ----------------------------------------------------------

  Future<void> _ajouterUnOuvrage() async {
    final saisie = await showDialog<BookFormResult>(
      context: context,
      builder: (_) => const BookFormDialog(),
    );
    if (saisie == null) return;

    await _executer(
      () => ref.read(booksRepositoryProvider).createBook(
        title: saisie.title,
        author: saisie.author,
        isbn: saisie.isbn,
        quantityTotal: saisie.quantityTotal,
        publisher: saisie.publisher,
        publishedYear: saisie.publishedYear,
        subject: saisie.subject,
        shelfLocation: saisie.shelfLocation,
      ),
      succes: 'Ouvrage ajouté.',
      echec: 'Création impossible.',
    );
  }

  Future<void> _modifierUnOuvrage(Book livre) async {
    final saisie = await showDialog<BookFormResult>(
      context: context,
      builder: (_) => BookFormDialog(livre: livre),
    );
    if (saisie == null) return;

    await _executer(
      () => ref.read(booksRepositoryProvider).updateBook(
        livre.id,
        title: saisie.title,
        author: saisie.author,
        isbn: saisie.isbn,
        quantityTotal: saisie.quantityTotal,
        publisher: saisie.publisher,
        publishedYear: saisie.publishedYear,
        subject: saisie.subject,
        shelfLocation: saisie.shelfLocation,
        // L'annee videe doit partir en `null` explicite, sinon l'ancienne
        // valeur survivrait a la correction.
        effacerAnnee: saisie.publishedYear == null,
      ),
      succes: 'Ouvrage modifié.',
      echec: 'Modification impossible.',
    );
  }

  Future<void> _supprimerUnOuvrage(Book livre) async {
    final confirme = await _confirmer(
      titre: 'Supprimer l’ouvrage',
      corps: '« ${livre.title} » sera retiré du catalogue.',
      action: 'Supprimer',
    );
    if (!confirme) return;

    await _executer(
      () => ref.read(booksRepositoryProvider).deleteBook(livre.id),
      succes: 'Ouvrage supprimé.',
      // Le serveur protege un ouvrage encore rattache a des emprunts
      // (`on_delete=PROTECT`): son refus est la bonne reponse, pas un bug.
      echec: 'Suppression impossible : cet ouvrage a un historique d’emprunts.',
    );
  }

  // --- Prets --------------------------------------------------------------

  Future<void> _enregistrerUnPret() async {
    if (_eleves.isEmpty) {
      _signaler('Aucun élève à qui prêter un ouvrage.');
      return;
    }
    final saisie = await showDialog<BorrowFormResult>(
      context: context,
      builder: (_) => BorrowFormDialog(livres: _livres, eleves: _eleves),
    );
    if (saisie == null) return;

    await _executer(
      () => ref.read(booksRepositoryProvider).createBorrow(
        studentId: saisie.studentId,
        bookId: saisie.bookId,
        borrowedAt: saisie.borrowedAt,
        dueDate: saisie.dueDate,
      ),
      succes: 'Emprunt enregistré.',
      echec: 'Enregistrement impossible.',
    );
  }

  Future<void> _rendre(Borrow emprunt) async {
    final penalite = emprunt.penaltyDue;
    final confirme = await _confirmer(
      titre: 'Rendre l’ouvrage',
      corps: penalite > 0
          ? '« ${emprunt.bookTitle} » revient avec ${emprunt.daysLate} jour(s) '
                'de retard. Une pénalité de ${penalite.toStringAsFixed(0)} F '
                'sera portée au dossier.'
          : '« ${emprunt.bookTitle} » sera remis en rayon.',
      action: 'Confirmer le retour',
    );
    if (!confirme) return;

    await _executer(
      () => ref.read(booksRepositoryProvider).returnBorrow(emprunt.id),
      succes: 'Ouvrage rendu.',
      echec: 'Retour impossible.',
    );
  }

  Future<void> _supprimerUnPret(Borrow emprunt) async {
    final confirme = await _confirmer(
      titre: 'Supprimer l’emprunt',
      corps: 'La ligne disparaîtra de l’historique et l’exemplaire '
          'retournera au rayon.',
      action: 'Supprimer',
    );
    if (!confirme) return;

    await _executer(
      () => ref.read(booksRepositoryProvider).deleteBorrow(emprunt.id),
      succes: 'Emprunt supprimé.',
      echec: 'Suppression impossible.',
    );
  }

  // --- Rouages communs ----------------------------------------------------

  /// Joue une action, puis recharge: les compteurs viennent du serveur et
  /// les recalculer ici les ferait diverger de la liste affichee.
  Future<void> _executer(
    Future<void> Function() action, {
    required String succes,
    required String echec,
  }) async {
    setState(() => _enCours = true);
    try {
      await action();
      if (!mounted) return;
      _signaler(succes, succes: true);
      await _charger();
    } catch (error) {
      if (!mounted) return;
      _signaler(_message(error, echec));
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  Future<bool> _confirmer({
    required String titre,
    required String corps,
    required String action,
  }) async {
    final reponse = await showDialog<bool>(
      context: context,
      builder: (contexteDialogue) => AlertDialog(
        title: Text(titre),
        content: Text(corps),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(contexteDialogue).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(contexteDialogue).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return reponse == true;
  }

  String _message(Object error, String repli) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        // Le serveur refuse champ par champ: « book » quand il n'y a plus
        // d'exemplaire, « isbn » sur un doublon. Le message est utilisable
        // tel quel, la ou « erreur 400 » n'apprend rien.
        for (final valeur in data.values) {
          if (valeur is List && valeur.isNotEmpty) return valeur.first.toString();
          if (valeur is String && valeur.isNotEmpty) return valeur;
        }
      }
    }
    return repli;
  }

  void _signaler(String message, {bool succes = false}) {
    if (!mounted) return;
    const vert = Color(0xFF197A43);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: succes ? vert : null,
          content: Text(
            message,
            style: succes ? const TextStyle(color: Colors.white) : null,
          ),
        ),
      );
  }

  Widget _carte({required String titre, Widget? action, required Widget corps}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(titre, style: Theme.of(context).textTheme.titleSmall),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 8),
          corps,
        ],
      ),
    );
  }

  Widget _pastille(String libelle, String valeur, {bool alerte = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: alerte ? scheme.error : scheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(libelle, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(
            valeur,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: alerte ? scheme.error : null,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final droits = ref.watch(currentPermissionsProvider);
    final peutEcrire = droits.canWrite('library');
    final peutSupprimer = droits.canDelete('library');

    if (_chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    final enRetard = _emprunts.where((emprunt) => emprunt.estEnRetard).length;
    final enCours = _emprunts.where((emprunt) => !emprunt.isReturned).length;
    final disponibles = _livres.where((livre) => livre.estDisponible).length;

    final catalogue = _carte(
      titre: 'Catalogue',
      action: peutEcrire
          ? IconButton(
              tooltip: 'Ajouter un ouvrage',
              onPressed: _enCours ? null : _ajouterUnOuvrage,
              icon: const Icon(Icons.add),
            )
          : null,
      corps: BooksPanel(
        livres: _livres,
        recherche: _recherche,
        filtreDisponibilite: _filtreDisponibilite,
        onRechercheChanged: (valeur) {
          setState(() => _recherche = valeur);
          _charger();
        },
        onFiltreChanged: (valeur) {
          setState(() => _filtreDisponibilite = valeur);
          _charger();
        },
        onModifier: peutEcrire ? _modifierUnOuvrage : null,
        onSupprimer: peutSupprimer ? _supprimerUnOuvrage : null,
      ),
    );

    final prets = _carte(
      titre: peutEcrire ? 'Emprunts' : 'Mes emprunts',
      action: peutEcrire
          ? IconButton(
              tooltip: 'Enregistrer un emprunt',
              onPressed: _enCours ? null : _enregistrerUnPret,
              icon: const Icon(Icons.add),
            )
          : null,
      corps: BorrowsPanel(
        emprunts: _emprunts,
        filtre: _filtreEmprunts,
        onFiltreChanged: (valeur) {
          setState(() => _filtreEmprunts = valeur);
          _charger();
        },
        onRendre: peutEcrire ? _rendre : null,
        onSupprimer: peutSupprimer ? _supprimerUnPret : null,
        // Pour l'eleve et le parent, la liste ne contient que leurs propres
        // prets: repeter le nom a chaque ligne n'apprendrait rien.
        masquerEmprunteur: !peutEcrire,
      ),
    );

    return RefreshIndicator(
      onRefresh: _charger,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ouvrages',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      peutEcrire
                          ? 'Catalogue papier, prêts et retours.'
                          : 'Le catalogue de l’établissement et vos emprunts.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _enCours ? null : _charger,
                icon: const Icon(Icons.sync),
                label: const Text('Actualiser'),
              ),
            ],
          ),
          if (_enCours) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _pastille('Ouvrages', '${_livres.length}'),
              _pastille('Disponibles', '$disponibles'),
              _pastille('Prêts en cours', '$enCours'),
              _pastille('Retards', '$enRetard', alerte: enRetard > 0),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 1120) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: catalogue),
                    const SizedBox(width: 12),
                    Expanded(flex: 5, child: prets),
                  ],
                );
              }
              return Column(
                children: [catalogue, const SizedBox(height: 12), prets],
              );
            },
          ),
        ],
      ),
    );
  }
}
