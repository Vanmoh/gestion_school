class PaginatedResult<T> {
  final int count;
  final String? next;
  final String? previous;
  final List<T> results;

  const PaginatedResult({
    required this.count,
    required this.next,
    required this.previous,
    required this.results,
  });

  bool get hasNext => next != null && next!.trim().isNotEmpty;
  bool get hasPrevious => previous != null && previous!.trim().isNotEmpty;
}
