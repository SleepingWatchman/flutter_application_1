class NoteImage {
  final int id;
  final int noteId;
  final String imagePath;
  final DateTime createdAt;

  NoteImage({
    required this.id,
    required this.noteId,
    required this.imagePath,
    required this.createdAt,
  });

  NoteImage copy({
    int? id,
    int? noteId,
    String? imagePath,
    DateTime? createdAt,
  }) {
    return NoteImage(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      imagePath: imagePath ?? this.imagePath,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'note_id': noteId,
      'image_path': imagePath,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory NoteImage.fromMap(Map<String, dynamic> map) {
    return NoteImage(
      id: map['id'],
      noteId: map['note_id'],
      imagePath: map['image_path'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }
} 