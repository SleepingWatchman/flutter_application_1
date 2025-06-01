/// Главный файл для запуска всех тестов в проекте
/// 
/// Запуск всех тестов: flutter test
/// Запуск с покрытием: flutter test --coverage
library;

import 'package:flutter_test/flutter_test.dart';

// Импорт всех тестовых файлов
import 'unit/models/user_model_test.dart' as user_model_test;
import 'unit/models/note_model_test.dart' as note_model_test;
import 'unit/providers/auth_provider_test.dart' as auth_provider_test;
import 'unit/providers/database_provider_test.dart' as database_provider_test;
import 'unit/services/auth_service_test.dart' as auth_service_test;
import 'widget/screens/notes_screen_test.dart' as notes_screen_test;
import 'widget/screens/collaboration/shared_databases_screen_test.dart' as shared_databases_screen_test;

void main() {
  group('Unit Tests', () {
    group('Models', () {
      user_model_test.main();
      note_model_test.main();
    });

    group('Providers', () {
      auth_provider_test.main();
      database_provider_test.main();
    });

    group('Services', () {
      auth_service_test.main();
    });
  });

  group('Widget Tests', () {
    group('Screens', () {
      notes_screen_test.main();
      shared_databases_screen_test.main();
    });
  });
} 