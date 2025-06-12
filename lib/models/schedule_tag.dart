class ScheduleTag {
  final int id;
  final int scheduleEntryId;
  final String tag;
  final DateTime createdAt;

  ScheduleTag({
    required this.id,
    required this.scheduleEntryId,
    required this.tag,
    required this.createdAt,
  });

  ScheduleTag copy({
    int? id,
    int? scheduleEntryId,
    String? tag,
    DateTime? createdAt,
  }) {
    return ScheduleTag(
      id: id ?? this.id,
      scheduleEntryId: scheduleEntryId ?? this.scheduleEntryId,
      tag: tag ?? this.tag,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'schedule_entry_id': scheduleEntryId,
      'tag': tag,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory ScheduleTag.fromMap(Map<String, dynamic> map) {
    return ScheduleTag(
      id: map['id'],
      scheduleEntryId: map['schedule_entry_id'],
      tag: map['tag'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }
} 