import 'package:flutter/material.dart';
import 'dart:convert';
import 'schedule_tag.dart';

/// Тип повторения для пунктов расписания
enum RecurrenceType {
  none,        // Не повторять
  daily,       // Каждый день
  weekly,      // Каждую неделю в тот же день недели
  monthly,     // Каждый месяц в тот же день
  yearly,      // Каждый год в ту же дату
}

/// Модель для повторения расписания
class Recurrence {
  RecurrenceType type;
  int? interval;     // Интервал повторения (например, каждые 2 дня)
  DateTime? endDate; // Дата окончания повторения (null - бесконечно)
  int? count;        // Количество повторений (null - бесконечно)
  
  Recurrence({
    this.type = RecurrenceType.none,
    this.interval = 1,
    this.endDate,
    this.count,
  });
  
  Map<String, dynamic> toMap() {
    return {
      'type': type.index,
      'interval': interval,
      'endDate': endDate?.toIso8601String(),
      'count': count,
    };
  }
  
  factory Recurrence.fromMap(Map<String, dynamic> map) {
    return Recurrence(
      type: RecurrenceType.values[map['type'] ?? 0],
      interval: map['interval'],
      endDate: map['endDate'] != null ? DateTime.parse(map['endDate']) : null,
      count: map['count'],
    );
  }
  
  String get displayName {
    switch (type) {
      case RecurrenceType.none:
        return 'Без повторения';
      case RecurrenceType.daily:
        return interval == 1 ? 'Каждый день' : 'Каждые $interval дней';
      case RecurrenceType.weekly:
        return interval == 1 ? 'Каждую неделю' : 'Каждые $interval недель';
      case RecurrenceType.monthly:
        return interval == 1 ? 'Каждый месяц' : 'Каждые $interval месяцев';
      case RecurrenceType.yearly:
        return interval == 1 ? 'Каждый год' : 'Каждые $interval лет';
    }
  }
  
  @override
  String toString() {
    String result = displayName;
    if (endDate != null) {
      result += ', до ${endDate!.toIso8601String().split('T')[0]}';
    } else if (count != null) {
      result += ', $count раз';
    }
    return result;
  }
}

/// Модель записи расписания
class ScheduleEntry {
  int? id;
  String time;
  String date;
  String? note;
  String? dynamicFieldsJson;
  Recurrence recurrence;
  String? databaseId;
  List<String> tags; // Список тегов для записи расписания
  
  ScheduleEntry({
    this.id,
    required this.time,
    required this.date,
    this.note,
    this.dynamicFieldsJson,
    Recurrence? recurrence,
    this.databaseId,
    List<String>? tags,
  }) : recurrence = recurrence ?? Recurrence(),
       tags = tags ?? [];
  
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'time': time,
      'date': date,
      'note': note,
      'dynamic_fields_json': dynamicFieldsJson,
      'recurrence_json': jsonEncode(recurrence.toMap()),
      'database_id': databaseId,
      'tags_json': jsonEncode(tags), // Сохраняем теги как JSON строку
    };
  }

  factory ScheduleEntry.fromMap(Map<String, dynamic> map) {
    Recurrence? recurrence;
    if (map['recurrence_json'] != null) {
      try {
        final recurrenceMap = jsonDecode(map['recurrence_json']);
        recurrence = Recurrence.fromMap(recurrenceMap);
      } catch (e) {
        print('Ошибка при разборе recurrence_json: $e');
        recurrence = Recurrence();
      }
    }
    
    // Парсим теги
    List<String> tags = [];
    if (map['tags_json'] != null) {
      try {
        final tagsList = jsonDecode(map['tags_json']);
        if (tagsList is List) {
          tags = tagsList.map((tag) => tag.toString()).toList();
        }
      } catch (e) {
        print('Ошибка при разборе tags_json: $e');
      }
    }
    
    return ScheduleEntry(
      id: map['id'],
      time: map['time'],
      date: map['date'],
      note: map['note'],
      dynamicFieldsJson: map['dynamic_fields_json'],
      recurrence: recurrence,
      databaseId: map['database_id'],
      tags: tags,
    );
  }
} 