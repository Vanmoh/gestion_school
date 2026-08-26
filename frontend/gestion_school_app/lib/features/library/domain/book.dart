/// Un ouvrage papier et l'etat reel de ses exemplaires.
///
/// `quantityAvailable` vient du serveur et n'est plus saisi: il valait
/// autrefois ce que l'utilisateur avait tape le jour de la creation, et un
/// livre prete restait annonce disponible pour toujours.
class Book {
  final int id;
  final String title;
  final String author;
  final String isbn;
  final int quantityTotal;
  final int quantityAvailable;
  final int quantityBorrowed;

  /// Facultatifs: editeur, annee, matiere et cote en rayon. Vides sur tout
  /// l'existant, ils ne sont affiches que lorsqu'ils sont renseignes.
  final String publisher;
  final int? publishedYear;
  final String subject;
  final String shelfLocation;

  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.isbn,
    required this.quantityTotal,
    required this.quantityAvailable,
    required this.quantityBorrowed,
    this.publisher = '',
    this.publishedYear,
    this.subject = '',
    this.shelfLocation = '',
  });

  factory Book.fromJson(Map<String, dynamic> json) {
    return Book(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString() ?? '',
      author: json['author']?.toString() ?? '',
      isbn: json['isbn']?.toString() ?? '',
      quantityTotal: (json['quantity_total'] as num?)?.toInt() ?? 0,
      quantityAvailable: (json['quantity_available'] as num?)?.toInt() ?? 0,
      quantityBorrowed: (json['quantity_borrowed'] as num?)?.toInt() ?? 0,
      publisher: json['publisher']?.toString() ?? '',
      publishedYear: (json['published_year'] as num?)?.toInt(),
      subject: json['subject']?.toString() ?? '',
      shelfLocation: json['shelf_location']?.toString() ?? '',
    );
  }

  bool get estDisponible => quantityAvailable > 0;

  /// Editeur, annee, matiere et cote, ceux qui sont renseignes seulement.
  String get complements {
    final morceaux = <String>[
      if (subject.isNotEmpty) subject,
      if (publisher.isNotEmpty) publisher,
      if (publishedYear != null) '$publishedYear',
      if (shelfLocation.isNotEmpty) 'rayon $shelfLocation',
    ];
    return morceaux.join(' • ');
  }
}

/// Un pret, et ou il en est.
///
/// L'etat -- rendu, en cours, en retard -- est calcule par le serveur: les
/// deux ecrans qui l'affichaient le recalculaient chacun a sa facon, et le
/// nombre de retards du bandeau ne correspondait pas a la liste dessous.
class Borrow {
  final int id;
  final int studentId;
  final int bookId;
  final String bookTitle;
  final String studentFullName;
  final String studentMatricule;
  final DateTime? borrowedAt;
  final DateTime? dueDate;
  final DateTime? returnedAt;
  final bool isReturned;
  final int daysLate;

  /// Penalite effectivement portee au dossier, posee au retour.
  final double penaltyAmount;

  /// Ce que le retard couterait aujourd'hui, meme avant le retour: c'est ce
  /// montant qui grandit tant que le livre n'est pas revenu.
  final double penaltyDue;

  const Borrow({
    required this.id,
    required this.studentId,
    required this.bookId,
    required this.bookTitle,
    required this.studentFullName,
    required this.studentMatricule,
    required this.borrowedAt,
    required this.dueDate,
    required this.returnedAt,
    required this.isReturned,
    required this.daysLate,
    required this.penaltyAmount,
    required this.penaltyDue,
  });

  factory Borrow.fromJson(Map<String, dynamic> json) {
    return Borrow(
      id: (json['id'] as num?)?.toInt() ?? 0,
      studentId: (json['student'] as num?)?.toInt() ?? 0,
      bookId: (json['book'] as num?)?.toInt() ?? 0,
      bookTitle: json['book_title']?.toString() ?? '',
      studentFullName: json['student_full_name']?.toString() ?? '',
      studentMatricule: json['student_matricule']?.toString() ?? '',
      borrowedAt: DateTime.tryParse(json['borrowed_at']?.toString() ?? ''),
      dueDate: DateTime.tryParse(json['due_date']?.toString() ?? ''),
      returnedAt: DateTime.tryParse(json['returned_at']?.toString() ?? ''),
      isReturned: json['is_returned'] == true,
      daysLate: (json['days_late'] as num?)?.toInt() ?? 0,
      penaltyAmount: _montant(json['penalty_amount']),
      penaltyDue: _montant(json['penalty_due']),
    );
  }

  /// Les montants arrivent en chaine (`DecimalField`) et non en nombre.
  static double _montant(dynamic valeur) {
    if (valeur is num) return valeur.toDouble();
    return double.tryParse(valeur?.toString() ?? '') ?? 0;
  }

  bool get estEnRetard => !isReturned && daysLate > 0;
}
