import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:oktoast/oktoast.dart';
import 'package:provider/provider.dart';
import 'screens/schedule_screen.dart';
import 'screens/notes_screen.dart';
import 'screens/pinboard_screen.dart';
import 'screens/profile/account_screen.dart';
import 'screens/collaboration/shared_databases_screen.dart';
import 'providers/auth_provider.dart';
import 'providers/backup_provider.dart';
import 'providers/enhanced_collaborative_provider.dart';
import 'providers/database_provider.dart';
import 'db/database_helper.dart';
import 'screens/auth/login_screen.dart';
import 'services/collaborative_database_service.dart';
import 'services/collaborative_role_service.dart';
import 'services/enhanced_sync_service.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:dio/dio.dart';

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
        ChangeNotifierProvider(create: (_) => DatabaseProvider()),
        // Добавляем улучшенный провайдер совместной работы
        ChangeNotifierProxyProvider2<AuthProvider, DatabaseProvider, EnhancedCollaborativeProvider>(
          create: (context) {
            final authProvider = context.read<AuthProvider>();
            final databaseProvider = context.read<DatabaseProvider>();
            final roleService = CollaborativeRoleService(authProvider.authService);
            final syncService = EnhancedSyncService(authProvider.authService, databaseProvider.dbHelper);
            final dio = Dio();
            final provider = EnhancedCollaborativeProvider(
              roleService,
              syncService,
              authProvider.authService,
              databaseProvider.dbHelper,
              dio,
            );
            provider.setDatabaseProvider(databaseProvider);
            return provider;
          },
          update: (context, auth, database, previous) {
            if (previous == null) {
              final roleService = CollaborativeRoleService(auth.authService);
              final syncService = EnhancedSyncService(auth.authService, database.dbHelper);
              final dio = Dio();
              final provider = EnhancedCollaborativeProvider(
                roleService,
                syncService,
                auth.authService,
                database.dbHelper,
                dio,
              );
              provider.setDatabaseProvider(database);
              return provider;
            }
            previous.setDatabaseProvider(database);
            return previous;
          },
        ),
        ChangeNotifierProxyProvider2<AuthProvider, DatabaseProvider, BackupProvider>(
          create: (context) {
            final provider = BackupProvider(context.read<AuthProvider>());
            provider.setDatabaseProvider(context.read<DatabaseProvider>());
            return provider;
          },
          update: (context, auth, database, previous) {
            final provider = BackupProvider(auth);
            provider.setDatabaseProvider(database);
            return provider;
          },
        ),
      ],
      child: OKToast(
        child: MaterialApp(
          title: 'Notes App',
          theme: ThemeData.dark(),
          locale: const Locale('ru', 'RU'),
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('ru', 'RU'),
            Locale('en', 'US'),
          ],
          home: Consumer<AuthProvider>(
            builder: (context, auth, _) {
              if (auth.isLoading) {
                return const Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              // Если пользователь не аутентифицирован, показываем экран входа
              if (!auth.isAuthenticated) {
                return const LoginScreen();
              }
              // Если пользователь аутентифицирован, показываем главный экран
              return const MainScreen();
            },
          ),
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
  // Делаем список не финальным, чтобы его можно было обновлять
  List<Widget> _widgetOptions = <Widget>[
    const ScheduleScreen(),
    const NotesScreen(),
    const PinboardScreen(),
    const SharedDatabasesScreen(),
  ];
  
  @override
  void initState() {
    super.initState();
    
    // Добавляем слушатель изменений в базе данных
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final dbProvider = Provider.of<DatabaseProvider>(context, listen: false);
      dbProvider.addListener(_handleDatabaseChanges);
      
      final enhancedCollabProvider = Provider.of<EnhancedCollaborativeProvider>(context, listen: false);
      enhancedCollabProvider.addListener(_handleCollaborativeDatabaseChanges);
    });
  }
  
  // Переменные для хранения провайдеров
  DatabaseProvider? _dbProvider;
  EnhancedCollaborativeProvider? _enhancedCollabProvider;
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Сохраняем ссылки на провайдеры для безопасного удаления слушателей в dispose
    _dbProvider = Provider.of<DatabaseProvider>(context, listen: false);
    _enhancedCollabProvider = Provider.of<EnhancedCollaborativeProvider>(context, listen: false);
    
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.wasTokenExpired) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showTokenExpiredDialog();
        auth.resetTokenExpiredFlag();
      });
    }
  }
  
  @override
  void dispose() {
    // Удаляем слушатели при удалении виджета
    try {
      if (_dbProvider != null) {
        _dbProvider!.removeListener(_handleDatabaseChanges);
      }
      
      if (_enhancedCollabProvider != null) {
        _enhancedCollabProvider!.removeListener(_handleCollaborativeDatabaseChanges);
      }
    } catch (e) {
      print('Ошибка при удалении слушателей: $e');
    }
    
    super.dispose();
  }
  
  void _handleDatabaseChanges() {
    // ОПТИМИЗИРОВАНО: Убираем избыточные обновления и логирование
    if (mounted) {
      // Consumer виджеты обновятся автоматически через Provider
      // Дополнительные действия не требуются
    }
  }
  
  void _handleCollaborativeDatabaseChanges() {
    // ОПТИМИЗИРОВАНО: Убираем избыточные обновления и логирование
    if (mounted) {
      // Consumer виджеты обновятся автоматически через Provider
      // Дополнительные действия не требуются
    }
  }

  void _showTokenExpiredDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Срок действия сессии истёк'),
        content: const Text('Ваша сессия завершена. Вы можете продолжить работу в гостевом режиме или войти снова для доступа к облачным функциям.'),
        actions: [
          TextButton(
            onPressed: () {
              final auth = Provider.of<AuthProvider>(context, listen: false);
              auth.enableGuestMode();
              Navigator.of(context).pop();
            },
            child: const Text('Продолжить в гостевом режиме'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
            child: const Text('Войти'),
          ),
        ],
      ),
    );
  }

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
        title: Consumer<EnhancedCollaborativeProvider>(
          builder: (context, enhancedProvider, child) {
            if (enhancedProvider.isUsingSharedDatabase) {
              // Если используется совместная база, показываем её имя
              final currentDbId = enhancedProvider.currentDatabaseId;
              final currentDb = enhancedProvider.databases
                  .where((db) => db.id == currentDbId)
                  .firstOrNull;
              final dbName = currentDb?.name ?? 'Совместная база';
              
              return Row(
                children: [
                  const Text('Notes App'),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: enhancedProvider.isServerAvailable 
                          ? Colors.green.withOpacity(0.2)
                          : Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: enhancedProvider.isServerAvailable 
                            ? Colors.green.withOpacity(0.5)
                            : Colors.orange.withOpacity(0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          enhancedProvider.isServerAvailable 
                              ? Icons.people 
                              : Icons.sync_problem,
                          size: 14,
                          color: enhancedProvider.isServerAvailable 
                              ? Colors.green
                              : Colors.orange,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          dbName,
                          style: TextStyle(
                            fontSize: 12,
                            color: enhancedProvider.isServerAvailable 
                                ? Colors.green
                                : Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            } else {
              // Для личной базы показываем стандартный заголовок
              return const Text('Notes App');
            }
          },
        ),
        leading: IconButton(
          icon: Icon(_isExtended ? Icons.menu_open : Icons.menu),
          onPressed: _toggleNavigationRail,
        ),
        actions: [
          // Кнопка для синхронизации совместной базы
          Consumer<EnhancedCollaborativeProvider>(
            builder: (context, enhancedProvider, child) {
              if (enhancedProvider.isUsingSharedDatabase) {
                return IconButton(
                  icon: const Icon(Icons.sync),
                  tooltip: enhancedProvider.isServerAvailable 
                      ? 'Синхронизировать базу данных'
                      : 'Сервер недоступен',
                  onPressed: enhancedProvider.isServerAvailable
                      ? () {
                          // Запускаем синхронизацию
                          enhancedProvider.syncDatabase();
                        }
                      : null, // Кнопка неактивна, если сервер недоступен
                );
              } else {
                return const SizedBox.shrink();
              }
            },
          ),
          // Кнопка для переключения на личную базу
          Consumer<EnhancedCollaborativeProvider>(
            builder: (context, enhancedProvider, child) {
              if (enhancedProvider.isUsingSharedDatabase) {
                return IconButton(
                  icon: const Icon(Icons.person),
                  tooltip: 'Переключиться на личную базу',
                  onPressed: () {
                    // Переключаемся на личную базу
                    enhancedProvider.switchToPersonalDatabase();
                  },
                );
              } else {
                return const SizedBox.shrink();
              }
            },
          ),
        ],
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
              NavigationRailDestination(
                icon: Icon(Icons.people),
                label: Text('Совместная работа'),
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
                      return Hero(
                        tag: 'profile_button',
                        child: InkWell(
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
                                            ? NetworkImage('${user!.photoURL!}?t=${DateTime.now().millisecondsSinceEpoch}')
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
                                      ? NetworkImage('${user!.photoURL!}?t=${DateTime.now().millisecondsSinceEpoch}')
                                      : null,
                                  child: user?.photoURL == null
                                      ? const Icon(Icons.person)
                                      : null,
                                ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Consumer<DatabaseProvider>(
              builder: (context, databaseProvider, child) {
                return Consumer<EnhancedCollaborativeProvider>(
                  builder: (context, collabProvider, child) {
                    // Используем ключ для принудительного обновления IndexedStack
                    // при изменении базы данных
                    final String databaseId = collabProvider.isUsingSharedDatabase 
                      ? (collabProvider.currentDatabaseId ?? 'unknown')
                      : 'personal';
                    
                    return IndexedStack(
                      key: ValueKey('database_stack_$databaseId'),
                      index: _selectedIndex,
                      children: _widgetOptions,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
