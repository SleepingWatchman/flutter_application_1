import 'package:flutter/material.dart';

/// Возвращает объект IconData на основе строкового ключа
IconData getIconData(String iconKey) {
  switch (iconKey) {
    case 'person':
      return Icons.person;
    case 'check':
      return Icons.check;
    case 'tree':
      return Icons.park; // или Icons.park – по вашему выбору
    case 'home':
      return Icons.home;
    case 'car':
      return Icons.directions_car;
    case 'close':
      return Icons.close;
    default:
      return Icons.help_outline;
  }
} 