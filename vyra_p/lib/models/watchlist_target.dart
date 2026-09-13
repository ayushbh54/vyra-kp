class WatchlistTarget {
  final String id;
  final String name;
  final String identifier; // Phone or @handle
  final String note;
  final bool isHighPriority;
  final int totalCalls;
  final int totalChats;
  final DateTime lastInteracted;

  const WatchlistTarget({
    required this.id,
    required this.name,
    required this.identifier,
    required this.note,
    this.isHighPriority = true,
    required this.totalCalls,
    required this.totalChats,
    required this.lastInteracted,
  });
}
