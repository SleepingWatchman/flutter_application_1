class NoteTag {
  final int id;
  final int noteId;
  final String tag;
  final DateTime createdAt;

  NoteTag({
    required this.id,
    required this.noteId,
    required this.tag,
    required this.createdAt,
  });

  NoteTag copy({
    int? id,
    int? noteId,
    String? tag,
    DateTime? createdAt,
  }) {
    return NoteTag(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      tag: tag ?? this.tag,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'note_id': noteId,
      'tag': tag,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory NoteTag.fromMap(Map<String, dynamic> map) {
    return NoteTag(
      id: map['id'],
      noteId: map['note_id'],
      tag: map['tag'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }
} 