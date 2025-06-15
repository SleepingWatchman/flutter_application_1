import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Виджет выбора цвета с помощью слайдеров
class ColorPicker extends StatefulWidget {
  final Color color;
  final Function(Color) onChanged;

  const ColorPicker({
    Key? key,
    required this.color,
    required this.onChanged,
  }) : super(key: key);

  @override
  _ColorPickerState createState() => _ColorPickerState();
}

class _ColorPickerState extends State<ColorPicker> {
  late HSVColor _hsvColor;
  final double _wheelSize = 200;
  late Offset _currentPosition;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _hsvColor = HSVColor.fromColor(widget.color);
    _calculatePosition();
  }

  void _calculatePosition() {
    final double radius = _hsvColor.saturation * _wheelSize / 2;
    final double angle = _hsvColor.hue * math.pi / 180;
    final double x = _wheelSize / 2 + radius * math.cos(angle);
    final double y = _wheelSize / 2 + radius * math.sin(angle);
    _currentPosition = Offset(x, y);
  }

  void _updateColorFromPosition(Offset position) {
    final double centerX = _wheelSize / 2;
    final double centerY = _wheelSize / 2;
    final double dx = position.dx - centerX;
    final double dy = position.dy - centerY;
    final double radius = _wheelSize / 2;

    // Вычисляем расстояние от центра
    final double distance = math.sqrt(dx * dx + dy * dy);
    
    if (distance <= radius) {
      // Вычисляем угол в радианах и преобразуем в градусы
      double angle = math.atan2(dy, dx);
      if (angle < 0) angle += 2 * math.pi;
      double hue = (angle * 180 / math.pi) % 360;

      // Вычисляем насыщенность на основе расстояния от центра
      double saturation = (distance / radius).clamp(0.0, 1.0);

      setState(() {
        _currentPosition = position;
        _hsvColor = HSVColor.fromAHSV(
          1.0,
          hue,
          saturation,
          _hsvColor.value,
        );
        widget.onChanged(_hsvColor.toColor());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          children: [
            // Цветовое колесо
            Container(
              width: _wheelSize,
              height: _wheelSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  center: Alignment.center,
                  startAngle: 0,
                  endAngle: 2 * math.pi,
                  colors: [
                    const HSVColor.fromAHSV(1.0, 0, 1, 1).toColor(),   // Красный
                    const HSVColor.fromAHSV(1.0, 60, 1, 1).toColor(),  // Желтый
                    const HSVColor.fromAHSV(1.0, 120, 1, 1).toColor(), // Зеленый
                    const HSVColor.fromAHSV(1.0, 180, 1, 1).toColor(), // Голубой
                    const HSVColor.fromAHSV(1.0, 240, 1, 1).toColor(), // Синий
                    const HSVColor.fromAHSV(1.0, 300, 1, 1).toColor(), // Пурпурный
                    const HSVColor.fromAHSV(1.0, 360, 1, 1).toColor(), // Красный
                  ],
                ),
              ),
              child: Center(
                child: Container(
                  width: _wheelSize - 2,
                  height: _wheelSize - 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white,
                        Colors.white.withAlpha(0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Область для обработки жестов
            Positioned.fill(
              child: GestureDetector(
                onPanStart: (details) {
                  _isDragging = true;
                  _updateColorFromPosition(details.localPosition);
                },
                onPanUpdate: (details) {
                  if (_isDragging) {
                    _updateColorFromPosition(details.localPosition);
                  }
                },
                onPanEnd: (details) {
                  _isDragging = false;
                },
                onTapDown: (details) {
                  _updateColorFromPosition(details.localPosition);
                },
                onTap: () {
                  // onTap не предоставляет позицию, поэтому используем текущую позицию
                  // или можно добавить глобальную переменную для последней позиции
                },
                onLongPressStart: (details) {
                  _isDragging = true;
                  _updateColorFromPosition(details.localPosition);
                },
                onLongPressMoveUpdate: (details) {
                  if (_isDragging) {
                    _updateColorFromPosition(details.localPosition);
                  }
                },
                onLongPressEnd: (details) {
                  _isDragging = false;
                },
              ),
            ),
            // Маркер выбранного цвета
            Positioned(
              left: _currentPosition.dx - 8,
              top: _currentPosition.dy - 8,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _hsvColor.toColor(),
                  border: Border.all(
                    color: _hsvColor.toColor().computeLuminance() > 0.5 
                        ? Colors.black 
                        : Colors.white,
                    width: 2,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Предпросмотр выбранного цвета
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: _hsvColor.toColor(),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.white,
              width: 2,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Слайдер яркости
        Row(
          children: [
            const Text('Яркость:'),
            Expanded(
              child: Slider(
                value: _hsvColor.value,
                min: 0,
                max: 1,
                onChanged: (value) {
                  setState(() {
                    _hsvColor = _hsvColor.withValue(value);
                    widget.onChanged(_hsvColor.toColor());
                  });
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
} 