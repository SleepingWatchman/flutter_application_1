import 'package:flutter/material.dart';

/// Виджет выбора цвета с помощью слайдеров
class ColorPicker extends StatefulWidget {
  final Color color;
  final ValueChanged<Color> onChanged;
  
  const ColorPicker({
    Key? key, 
    required this.color, 
    required this.onChanged
  }) : super(key: key);
  
  @override
  _ColorPickerState createState() => _ColorPickerState();
}

class _ColorPickerState extends State<ColorPicker> {
  late double r;
  late double g;
  late double b;
  
  @override
  void initState() {
    super.initState();
    r = widget.color.red.toDouble();
    g = widget.color.green.toDouble();
    b = widget.color.blue.toDouble();
  }

  void _updateColor() {
    widget.onChanged(Color.fromARGB(255, r.toInt(), g.toInt(), b.toInt()));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const Text("R"),
            Expanded(
              child: Slider(
                min: 0,
                max: 255,
                value: r,
                onChanged: (value) {
                  setState(() {
                    r = value;
                    _updateColor();
                  });
                },
              ),
            ),
          ],
        ),
        Row(
          children: [
            const Text("G"),
            Expanded(
              child: Slider(
                min: 0,
                max: 255,
                value: g,
                onChanged: (value) {
                  setState(() {
                    g = value;
                    _updateColor();
                  });
                },
              ),
            ),
          ],
        ),
        Row(
          children: [
            const Text("B"),
            Expanded(
              child: Slider(
                min: 0,
                max: 255,
                value: b,
                onChanged: (value) {
                  setState(() {
                    b = value;
                    _updateColor();
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