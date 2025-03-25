import 'package:flutter/material.dart';
import '../models/pinboard_note.dart';
import '../models/connection.dart';

/// Класс для отрисовки соединений между заметками на доске
class ConnectionPainter extends CustomPainter {
  final List<PinboardNoteDB> notes;
  final List<ConnectionDB> connections;
  
  ConnectionPainter({required this.notes, required this.connections});
  
  @override
  void paint(Canvas canvas, Size size) {
    try {
      final Map<int, PinboardNoteDB> notesMap = {
        for (var note in notes) note.id!: note
      };
      for (var connection in connections) {
        PinboardNoteDB? fromNote = notesMap[connection.fromId];
        PinboardNoteDB? toNote = notesMap[connection.toId];
        if (fromNote != null && toNote != null) {
          final Paint paint = Paint()
            ..color = Color(connection.connectionColor)
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke;
          Offset from =
              Offset(fromNote.posX, fromNote.posY) + const Offset(75, 75);
          Offset to = Offset(toNote.posX, toNote.posY) + const Offset(75, 75);
          canvas.drawLine(from, to, paint);
        }
      }
    } catch (e) {
      debugPrint('Ошибка в ConnectionPainter: $e');
    }
  }

  @override
  bool shouldRepaint(covariant ConnectionPainter oldDelegate) {
    return oldDelegate.notes != notes || oldDelegate.connections != connections;
  }
} 