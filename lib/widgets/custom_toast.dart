import 'package:flutter/material.dart';

class CustomToast {
  static OverlayEntry? _currentToast;

  static void show({
    required BuildContext context,
    required String message,
    IconData? icon,
    Color? backgroundColor,
    Color? textColor,
    Duration duration = const Duration(seconds: 3),
  }) {
    // Удаляем предыдущий toast если он есть
    _currentToast?.remove();
    _currentToast = null;

    final overlay = Overlay.of(context);
    if (overlay == null) return;

    _currentToast = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 16,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: backgroundColor ?? Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    color: textColor ?? Theme.of(context).colorScheme.onSurface,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      color: textColor ?? Theme.of(context).colorScheme.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    overlay.insert(_currentToast!);

    // Автоматически удаляем toast через указанное время
    Future.delayed(duration, () {
      _currentToast?.remove();
      _currentToast = null;
    });
  }

  static void hide() {
    _currentToast?.remove();
    _currentToast = null;
  }
} 