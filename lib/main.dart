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
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper().database;
  await initializeDateFormatting('ru', null);
  runApp(const NotesApp());
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
    ScheduleScreen(),
    NotesScreen(),
    PinboardScreen(),
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
