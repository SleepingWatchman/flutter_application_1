class SharedDatabase {
  final String id;
  final String name;
  final String ownerId;
  final DateTime createdAt;
  final List<String> collaborators;

  SharedDatabase({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.createdAt,
    required this.collaborators,
  });

  factory SharedDatabase.fromJson(Map<String, dynamic> json) {
    return SharedDatabase(
      id: json['id'],
      name: json['name'],
      ownerId: json['ownerId'],
      createdAt: DateTime.parse(json['createdAt']),
      collaborators: List<String>.from(json['collaborators']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'ownerId': ownerId,
      'createdAt': createdAt.toIso8601String(),
      'collaborators': collaborators,
    };
  }
} 