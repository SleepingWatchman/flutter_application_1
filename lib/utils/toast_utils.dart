import 'package:flutter/material.dart';
import 'package:oktoast/oktoast.dart';

/// Показывает кастомный toast с иконкой
void showCustomToastWithIcon(String message,
    {Color accentColor = Colors.green, double fontSize = 14.0, Widget? icon}) {
  Future.delayed(const Duration(milliseconds: 300), () {
    try {
      showToastWidget(
        Align(
          alignment: Alignment.bottomRight,
          child: Container(
            margin: const EdgeInsets.only(right: 20, bottom: 20),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 41, 41, 41).withOpacity(0.8),
              borderRadius: BorderRadius.circular(8),
            ),
            constraints: const BoxConstraints(maxWidth: 250),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Верхняя полоса с акцентным цветом
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Если задана иконка, выводим Row с иконкой и текстом
                icon != null
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          icon,
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              message,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: fontSize, color: Colors.white),
                            ),
                          ),
                        ],
                      )
                    : Text(
                        message,
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(fontSize: fontSize, color: Colors.white),
                      ),
              ],
            ),
          ),
        ),
        duration: const Duration(seconds: 2),
        dismissOtherToast: true,
      );
    } catch (e) {
      debugPrint("Ошибка при показе toast: $e");
    }
  });
} 