import 'package:flutter/material.dart';

/// Модель записи расписания
class ScheduleEntry {
  int? id;
  String time;
  String date;
  String? note;
  String? dynamicFieldsJson;
  
  ScheduleEntry({
    this.id,
    required this.time,
    required this.date,
    this.note,
    this.dynamicFieldsJson
  });
  
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'time': time,
      'date': date,
      'note': note,
      'dynamic_fields_json': dynamicFieldsJson,
    };
  }

  factory ScheduleEntry.fromMap(Map<String, dynamic> map) {
    return ScheduleEntry(
      id: map['id'],
      time: map['time'],
      date: map['date'],
      note: map['note'],
      dynamicFieldsJson: map['dynamic_fields_json'],
    );
  }
} 