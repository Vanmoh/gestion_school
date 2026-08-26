import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/books_repository.dart';
import '../data/library_repository.dart';

final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return LibraryRepository(ref.read(dioProvider));
});

/// Le fonds papier, sur son propre depot: un ouvrage se compte en
/// exemplaires et se rend, la ou un PDF se consulte.
final booksRepositoryProvider = Provider<BooksRepository>((ref) {
  return BooksRepository(ref.read(dioProvider));
});
