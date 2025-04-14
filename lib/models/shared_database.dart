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
      id: json['id'] as String,
      name: json['name'] as String,
      ownerId: json['ownerId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      collaborators: List<String>.from(json['collaborators'] as List),
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