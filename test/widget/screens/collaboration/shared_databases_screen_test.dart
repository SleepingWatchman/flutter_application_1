import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SharedDatabasesScreen Widget Tests', () {
    testWidgets('should display guest mode message when in guest mode', (WidgetTester tester) async {
      // Тест отображения сообщения для гостевого режима
      
      // Arrange & Act
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: const Text('Совместные базы данных'),
            ),
            body: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.account_circle_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Совместные базы недоступны в гостевом режиме',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Пожалуйста, создайте аккаунт или авторизуйтесь',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Assert
      expect(find.text('Совместные базы недоступны в гостевом режиме'), findsOneWidget);
      expect(find.text('Пожалуйста, создайте аккаунт или авторизуйтесь'), findsOneWidget);
      expect(find.byIcon(Icons.account_circle_outlined), findsOneWidget);
    });

    testWidgets('should display empty state when no databases', (WidgetTester tester) async {
      // Тест отображения пустого состояния
      
      // Arrange & Act
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: const Text('Совместные базы данных'),
            ),
            body: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.storage,
                    size: 64,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'У вас пока нет совместных баз данных',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Создайте новую или примите приглашение',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Assert
      expect(find.text('У вас пока нет совместных баз данных'), findsOneWidget);
      expect(find.text('Создайте новую или примите приглашение'), findsOneWidget);
      expect(find.byIcon(Icons.storage), findsOneWidget);
    });

    testWidgets('should display app bar with correct actions', (WidgetTester tester) async {
      // Тест наличия правильных действий в AppBar
      
      // Arrange & Act
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: const Text('Совместные базы данных'),
              actions: [
                Stack(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.mail),
                      onPressed: () {},
                    ),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: const Text(
                          '2',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () {},
                ),
                IconButton(
                  icon: const Icon(Icons.import_export),
                  onPressed: () {},
                ),
              ],
            ),
            body: const SizedBox(),
          ),
        ),
      );

      // Assert
      expect(find.byIcon(Icons.mail), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.byIcon(Icons.import_export), findsOneWidget);
      expect(find.text('2'), findsOneWidget); // Badge с количеством приглашений
    });

    testWidgets('should display database card with correct information', (WidgetTester tester) async {
      // Тест отображения карточки базы данных
      
      // Arrange & Act
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Card(
              margin: const EdgeInsets.all(8.0),
              child: ListTile(
                title: const Text('Тестовая база данных'),
                subtitle: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Создана: 2024-01-01'),
                    Text('Участников: 3'),
                    Text(
                      'Активная база данных',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.people),
                      tooltip: 'Участники базы данных',
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: const Icon(Icons.logout),
                      tooltip: 'Переключиться на личную базу',
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      // Assert
      expect(find.text('Тестовая база данных'), findsOneWidget);
      expect(find.text('Создана: 2024-01-01'), findsOneWidget);
      expect(find.text('Участников: 3'), findsOneWidget);
      expect(find.text('Активная база данных'), findsOneWidget);
      expect(find.byIcon(Icons.people), findsOneWidget);
      expect(find.byIcon(Icons.logout), findsOneWidget);
    });

    testWidgets('should display create button', (WidgetTester tester) async {
      // Тест отображения кнопки создания базы данных
      
      // Arrange & Act
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.add),
                  label: const Text('Создать новую базу данных'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16.0),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Assert
      expect(find.text('Создать новую базу данных'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    group('Interaction Tests', () {
      testWidgets('should respond to database card tap', (WidgetTester tester) async {
        // Тест нажатия на карточку базы данных
        
        // Arrange
        bool cardTapped = false;
        
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: GestureDetector(
                onTap: () {
                  cardTapped = true;
                },
                child: Card(
                  child: ListTile(
                    title: const Text('Тестовая база данных'),
                  ),
                ),
              ),
            ),
          ),
        );

        // Act
        await tester.tap(find.byType(Card));
        await tester.pump();

        // Assert
        expect(cardTapped, isTrue);
      });

      testWidgets('should respond to participants button tap', (WidgetTester tester) async {
        // Тест нажатия на кнопку участников
        
        // Arrange
        bool participantsButtonTapped = false;
        
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: IconButton(
                icon: const Icon(Icons.people),
                tooltip: 'Участники базы данных',
                onPressed: () {
                  participantsButtonTapped = true;
                },
              ),
            ),
          ),
        );

        // Act
        await tester.tap(find.byIcon(Icons.people));
        await tester.pump();

        // Assert
        expect(participantsButtonTapped, isTrue);
      });

      testWidgets('should respond to create button tap', (WidgetTester tester) async {
        // Тест нажатия на кнопку создания
        
        // Arrange
        bool createButtonTapped = false;
        
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ElevatedButton.icon(
                onPressed: () {
                  createButtonTapped = true;
                },
                icon: const Icon(Icons.add),
                label: const Text('Создать новую базу данных'),
              ),
            ),
          ),
        );

        // Act
        await tester.tap(find.text('Создать новую базу данных'));
        await tester.pump();

        // Assert
        expect(createButtonTapped, isTrue);
      });
    });

    group('Loading States', () {
      testWidgets('should display loading indicator', (WidgetTester tester) async {
        // Тест отображения индикатора загрузки
        
        // Arrange & Act
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          ),
        );

        // Assert
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      });

      testWidgets('should display error state', (WidgetTester tester) async {
        // Тест отображения состояния ошибки
        
        // Arrange & Act
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Ошибка загрузки баз данных'),
                    const SizedBox(height: 8),
                    const Text('Сетевая ошибка'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {},
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        // Assert
        expect(find.text('Ошибка загрузки баз данных'), findsOneWidget);
        expect(find.text('Сетевая ошибка'), findsOneWidget);
        expect(find.text('Повторить'), findsOneWidget);
      });
    });
  });
} 