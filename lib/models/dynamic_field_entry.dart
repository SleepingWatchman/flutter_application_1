import 'package:flutter/material.dart';

/// Класс для работы с динамическими полями в расписании
class DynamicFieldEntry {
  TextEditingController keyController;
  TextEditingController valueController;
  
  DynamicFieldEntry({required String key, required String value})
      : keyController = TextEditingController(text: key),
        valueController = TextEditingController(text: value);
}