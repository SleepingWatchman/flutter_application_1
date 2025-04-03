import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:oktoast/oktoast.dart';
import 'db/database_helper.dart';
import 'screens/schedule_screen.dart';
import 'screens/notes_screen.dart';
import 'screens/pinboard_screen.dart';

/// Функция main: инициализация БД и запуск приложения
void main() async {
  try {
    // Инициализация Flutter
    WidgetsFlutterBinding.ensureInitialized();
    
    // Инициализация базы данных
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    
    // Инициализация локализации
    await initializeDateFormatting('ru', null);
    
    // Инициализация базы данных
    final dbHelper = DatabaseHelper();
    final db = await dbHelper.database;
    
    // Проверяем, что база данных создана и доступна
    if (db == null) {
      throw Exception('Не удалось инициализировать базу данных');
    }
    
    // Запуск приложения
    runApp(const NotesApp());
  } catch (e) {
    print('Ошибка инициализации приложения: $e');
    // Показываем ошибку пользователю
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Ошибка запуска приложения: $e'),
          ),
        ),
      ),
    );
  }
}

class NotesApp extends StatelessWidget {
  const NotesApp({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return OKToast(
      child: MaterialApp(
        title: 'Notes App',
        theme: ThemeData.dark(),
        home: const MainScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

/// Главное окно с NavigationRail
class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);
  
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final List<Widget> _widgetOptions = <Widget>[
    const ScheduleScreen(),
    const NotesScreen(),
    const PinboardScreen(),
  ];
  
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _onItemTapped,
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                  icon: Icon(Icons.schedule), label: Text('Расписание')),
              NavigationRailDestination(
                  icon: Icon(Icons.note), label: Text('Заметки')),
              NavigationRailDestination(
                  icon: Icon(Icons.dashboard), label: Text('Доска')),
            ],
          ),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: _widgetOptions,
            ),
          ),
        ],
      ),
    );
  }
}
