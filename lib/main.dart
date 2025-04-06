import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:oktoast/oktoast.dart';
import 'package:provider/provider.dart';
import 'screens/schedule_screen.dart';
import 'screens/notes_screen.dart';
import 'screens/pinboard_screen.dart';
import 'screens/profile/account_screen.dart';
import 'providers/auth_provider.dart';
import 'providers/backup_provider.dart';
import 'db/database_helper.dart';

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
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProxyProvider<AuthProvider, BackupProvider>(
          create: (context) => BackupProvider(context.read<AuthProvider>()),
          update: (context, auth, previous) => BackupProvider(auth),
        ),
      ],
      child: OKToast(
        child: MaterialApp(
          title: 'Notes App',
          theme: ThemeData.dark(),
          home: const MainScreen(),
          debugShowCheckedModeBanner: false,
        ),
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
  bool _isExtended = false;
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

  void _toggleNavigationRail() {
    setState(() {
      _isExtended = !_isExtended;
    });
  }

  void _openAccountScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AccountScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes App'),
        leading: IconButton(
          icon: Icon(_isExtended ? Icons.menu_open : Icons.menu),
          onPressed: _toggleNavigationRail,
        ),
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            extended: _isExtended,
            onDestinationSelected: _onItemTapped,
            labelType: NavigationRailLabelType.none,
            useIndicator: true,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.schedule),
                label: Text('Расписание'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.note),
                label: Text('Заметки'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.dashboard),
                label: Text('Доска'),
              ),
            ],
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Consumer<AuthProvider>(
                    builder: (context, auth, _) {
                      if (auth.isLoading) {
                        return const SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(),
                        );
                      }

                      final user = auth.user;
                      return InkWell(
                        onTap: () => _openAccountScreen(context),
                        child: _isExtended
                            ? Container(
                                width: 200,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundImage: user?.photoURL != null
                                          ? NetworkImage(user!.photoURL!)
                                          : null,
                                      child: user?.photoURL == null
                                          ? const Icon(Icons.person)
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Flexible(
                                      child: Text(
                                        user != null 
                                            ? (user.displayName ?? user.email)
                                            : 'Гость',
                                        style: Theme.of(context).textTheme.bodyMedium,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : CircleAvatar(
                                radius: 20,
                                backgroundImage: user?.photoURL != null
                                    ? NetworkImage(user!.photoURL!)
                                    : null,
                                child: user?.photoURL == null
                                    ? const Icon(Icons.person)
                                    : null,
                              ),
                      );
                    },
                  ),
                ),
              ),
            ),
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
