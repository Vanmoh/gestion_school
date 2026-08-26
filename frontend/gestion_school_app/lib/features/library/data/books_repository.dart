import 'package:dio/dio.dart';

import '../domain/book.dart';

/// Le fonds papier: le catalogue et les prets.
///
/// Distinct du fonds numerique de la meme rubrique -- un ouvrage se compte
/// en exemplaires et se rend, un PDF se consulte. L'ecran parlait jusqu'ici
/// a `dio` directement, en manipulant des `Map` sans forme: c'est la que se
/// perdaient les champs que le serveur avait pourtant renvoyes.
class BooksRepository {
  final Dio dio;

  BooksRepository(this.dio);

  List<Map<String, dynamic>> _lignes(dynamic data) {
    final List<dynamic> brutes;
    if (data is Map<String, dynamic> && data['results'] is List) {
      brutes = data['results'] as List<dynamic>;
    } else if (data is List<dynamic>) {
      brutes = data;
    } else {
      brutes = const [];
    }
    return brutes
        .whereType<Map>()
        .map((ligne) => Map<String, dynamic>.from(ligne))
        .toList(growable: false);
  }

  /// Toutes les pages du catalogue, filtre par le serveur.
  ///
  /// `availability` vaut « available » ou « out »; vide, il ne filtre rien.
  Future<List<Book>> fetchBooks({
    String search = '',
    String availability = '',
  }) async {
    final livres = <Book>[];
    String? chemin = '/books/';
    Map<String, dynamic>? parametres = {
      'page_size': 200,
      if (search.trim().isNotEmpty) 'search': search.trim(),
      if (availability.isNotEmpty) 'availability': availability,
    };

    while (chemin != null) {
      final reponse = await dio.get(chemin, queryParameters: parametres);
      livres.addAll(_lignes(reponse.data).map(Book.fromJson));
      final data = reponse.data;
      final suivant = data is Map<String, dynamic> ? data['next'] : null;
      // `next` porte deja les parametres: les repasser les dupliquerait.
      chemin = suivant?.toString();
      parametres = null;
    }
    return livres;
  }

  Future<Book> createBook({
    required String title,
    required String author,
    required String isbn,
    required int quantityTotal,
    String publisher = '',
    int? publishedYear,
    String subject = '',
    String shelfLocation = '',
  }) async {
    final reponse = await dio.post(
      '/books/',
      // `quantity_available` n'est pas envoye: le serveur le derive du total
      // et des emprunts en cours. L'envoyer donnait un compteur qui mentait
      // des le premier pret.
      data: {
        'title': title,
        'author': author,
        'isbn': isbn,
        'quantity_total': quantityTotal,
        'publisher': publisher,
        'published_year': ?publishedYear,
        'subject': subject,
        'shelf_location': shelfLocation,
      },
    );
    return Book.fromJson(Map<String, dynamic>.from(reponse.data as Map));
  }

  Future<Book> updateBook(
    int bookId, {
    String? title,
    String? author,
    String? isbn,
    int? quantityTotal,
    String? publisher,
    int? publishedYear,
    String? subject,
    String? shelfLocation,
    bool effacerAnnee = false,
  }) async {
    final reponse = await dio.patch(
      '/books/$bookId/',
      data: {
        'title': ?title,
        'author': ?author,
        'isbn': ?isbn,
        'quantity_total': ?quantityTotal,
        'publisher': ?publisher,
        'subject': ?subject,
        'shelf_location': ?shelfLocation,
        // `null` explicite quand l'utilisateur vide l'annee: la syntaxe
        // null-aware l'omettrait, et la valeur precedente resterait en base.
        if (effacerAnnee) 'published_year': null else 'published_year': ?publishedYear,
      },
    );
    return Book.fromJson(Map<String, dynamic>.from(reponse.data as Map));
  }

  Future<void> deleteBook(int bookId) async {
    await dio.delete('/books/$bookId/');
  }

  /// Les prets, filtres par etat cote serveur.
  ///
  /// `status` vaut « ongoing », « returned » ou « late »; vide, tout remonte.
  Future<List<Borrow>> fetchBorrows({String status = ''}) async {
    final prets = <Borrow>[];
    String? chemin = '/borrows/';
    Map<String, dynamic>? parametres = {
      'page_size': 200,
      if (status.isNotEmpty) 'status': status,
    };

    while (chemin != null) {
      final reponse = await dio.get(chemin, queryParameters: parametres);
      prets.addAll(_lignes(reponse.data).map(Borrow.fromJson));
      final data = reponse.data;
      final suivant = data is Map<String, dynamic> ? data['next'] : null;
      chemin = suivant?.toString();
      parametres = null;
    }
    return prets;
  }

  Future<Borrow> createBorrow({
    required int studentId,
    required int bookId,
    required DateTime borrowedAt,
    required DateTime dueDate,
  }) async {
    final reponse = await dio.post(
      '/borrows/',
      // Pas de penalite a la creation: elle etait saisie ici, c'est-a-dire
      // avant qu'il y ait le moindre retard. Elle se calcule au retour.
      data: {
        'student': studentId,
        'book': bookId,
        'borrowed_at': _jour(borrowedAt),
        'due_date': _jour(dueDate),
      },
    );
    return Borrow.fromJson(Map<String, dynamic>.from(reponse.data as Map));
  }

  /// Rend un exemplaire: date du jour par defaut, penalite calculee.
  ///
  /// [penaltyAmount] impose un montant a la place du calcul -- le geste
  /// commercial reste une decision d'ecole.
  Future<Borrow> returnBorrow(
    int borrowId, {
    DateTime? returnedAt,
    double? penaltyAmount,
  }) async {
    final reponse = await dio.post(
      '/borrows/$borrowId/return/',
      data: {
        if (returnedAt != null) 'returned_at': _jour(returnedAt),
        if (penaltyAmount != null) 'penalty_amount': penaltyAmount.toString(),
      },
    );
    return Borrow.fromJson(Map<String, dynamic>.from(reponse.data as Map));
  }

  Future<void> deleteBorrow(int borrowId) async {
    await dio.delete('/borrows/$borrowId/');
  }

  String _jour(DateTime valeur) {
    final mois = valeur.month.toString().padLeft(2, '0');
    final jour = valeur.day.toString().padLeft(2, '0');
    return '${valeur.year.toString().padLeft(4, '0')}-$mois-$jour';
  }
}
