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

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'identifier': identifier,
    'note': note,
    'isHighPriority': isHighPriority,
    'totalCalls': totalCalls,
    'totalChats': totalChats,
    'lastInteracted': lastInteracted.toIso8601String(),
  };

  factory WatchlistTarget.fromJson(Map<String, dynamic> json) => WatchlistTarget(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    identifier: json['identifier'] as String? ?? '',
    note: json['note'] as String? ?? '',
    isHighPriority: (json['isHighPriority'] as bool?) ?? true,
    totalCalls: (json['totalCalls'] as num?)?.toInt() ?? 0,
    totalChats: (json['totalChats'] as num?)?.toInt() ?? 0,
    lastInteracted: DateTime.tryParse(json['lastInteracted'] as String? ?? '') ?? DateTime.now(),
  );
}
