import 'package:flutter/material.dart';

class DatabaseProvider extends ChangeNotifier {
  bool _needsUpdate = false;

  bool get needsUpdate => _needsUpdate;

  void setNeedsUpdate(bool value) {
    if (_needsUpdate != value) {
      _needsUpdate = value;
      notifyListeners();
    }
  }

  void resetUpdateFlag() {
    _needsUpdate = false;
  }
} 