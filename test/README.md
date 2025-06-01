# Тестирование Flutter Application

Этот проект включает комплексное тестирование с измерением покрытия кода.

## Структура тестов

```
test/
├── unit/                    # Модульные тесты
│   ├── models/             # Тесты моделей данных
│   ├── providers/          # Тесты провайдеров состояния
│   └── services/           # Тесты сервисов
├── widget/                 # Виджет-тесты
│   └── screens/           # Тесты экранов
├── integration/           # Интеграционные тесты
├── mocks/                 # Мок-объекты для тестирования
└── test_main.dart         # Главный файл запуска тестов
```

## Команды для запуска тестов

### Запуск всех тестов
```bash
flutter test
```

### Запуск тестов с покрытием
```bash
flutter test --coverage
```

### Запуск конкретной группы тестов
```bash
# Только модульные тесты
flutter test test/unit/

# Только виджет-тесты
flutter test test/widget/

# Только интеграционные тесты
flutter test test/integration/
```

### Запуск конкретного тестового файла
```bash
flutter test test/unit/models/user_model_test.dart
```

## Просмотр отчета о покрытии

После запуска тестов с флагом `--coverage` будет создана папка `coverage/` с отчетами:

### HTML отчет
```bash
# Установить lcov (если не установлен)
sudo apt-get install lcov  # Linux
brew install lcov           # macOS

# Генерировать HTML отчет
genhtml coverage/lcov.info -o coverage/html

# Открыть отчет в браузере
open coverage/html/index.html
```

### LCOV отчет
Файл `coverage/lcov.info` можно использовать с различными инструментами анализа покрытия.

## Цели покрытия

- **Минимальное покрытие**: 70%
- **Цель**: 85%
- **Идеальное покрытие**: 95%

### Исключения из покрытия

- Генерируемые файлы (*.g.dart, *.freezed.dart)
- Файлы конфигурации (main.dart, firebase_options.dart)
- Простые модели данных без логики
- Тестовые файлы и моки

## Типы тестов

### 1. Модульные тесты (Unit Tests)
Тестируют отдельные функции, методы и классы в изоляции.

**Примеры:**
- Тесты моделей данных
- Тесты бизнес-логики провайдеров
- Тесты утилитарных функций

### 2. Виджет-тесты (Widget Tests)
Тестируют отдельные виджеты и их взаимодействие.

**Примеры:**
- Тесты пользовательского интерфейса
- Тесты взаимодействия пользователя
- Тесты состояний виджетов

### 3. Интеграционные тесты (Integration Tests)
Тестируют полные сценарии использования приложения.

**Примеры:**
- Тесты полного потока авторизации
- Тесты создания и редактирования заметок
- Тесты совместной работы

## Мокирование

Для тестирования используется библиотека `mockito`. Моки находятся в папке `test/mocks/`.

### Создание мока
```dart
import 'package:mockito/mockito.dart';
import 'package:flutter_application_1/services/auth_service.dart';

class MockAuthService extends Mock implements AuthService {}
```

### Использование мока
```dart
test('should authenticate user', () async {
  // Arrange
  final mockAuthService = MockAuthService();
  when(mockAuthService.login(any, any))
    .thenAnswer((_) async => UserModel(id: 'test', email: 'test@example.com'));

  // Act
  final result = await mockAuthService.login('test@example.com', 'password');

  // Assert
  expect(result.email, equals('test@example.com'));
  verify(mockAuthService.login('test@example.com', 'password')).called(1);
});
```

## Лучшие практики

### 1. Структура тестов
- Используйте паттерн **Arrange-Act-Assert**
- Группируйте связанные тесты с помощью `group()`
- Используйте описательные имена тестов

### 2. Моки и заглушки
- Мокируйте внешние зависимости
- Не мокируйте тестируемый объект
- Используйте `setUp()` и `tearDown()` для подготовки и очистки

### 3. Утверждения
- Используйте специфичные матчеры (`equals`, `isTrue`, `contains`)
- Проверяйте не только успешные, но и ошибочные сценарии
- Тестируйте граничные случаи

### 4. Производительность
- Избегайте тяжелых операций в тестах
- Используйте `pumpAndSettle()` для асинхронных операций в виджет-тестах
- Не делайте реальные сетевые запросы в тестах

## Continuous Integration

Тесты автоматически запускаются в GitHub Actions при каждом коммите и pull request.

### Конфигурация CI/CD
```yaml
- name: Run tests
  run: flutter test --coverage

- name: Upload coverage to Codecov
  uses: codecov/codecov-action@v3
  with:
    file: ./coverage/lcov.info
```

## Отладка тестов

### Проблемы с виджет-тестами
```dart
// Добавить отладочную информацию
await tester.pumpWidget(widget);
print(tester.allWidgets.map((w) => w.runtimeType).toList());

// Сделать скриншот для отладки
await expectLater(find.byType(MyWidget), matchesGoldenFile('widget_test.png'));
```

### Проблемы с асинхронными операциями
```dart
// Дождаться завершения всех анимаций
await tester.pumpAndSettle();

// Дождаться конкретного времени
await tester.pump(Duration(seconds: 1));
```

## Контрибуция

При добавлении нового функционала:

1. Напишите тесты перед реализацией (TDD)
2. Убедитесь, что покрытие не снижается
3. Обновите документацию тестов при необходимости
4. Запустите все тесты перед созданием PR

---

Для получения дополнительной информации о тестировании Flutter приложений:
- [Официальная документация Flutter Testing](https://docs.flutter.dev/testing)
- [Mockito документация](https://pub.dev/packages/mockito)
- [Flutter Test Utils](https://api.flutter.dev/flutter/flutter_test/flutter_test-library.html) 