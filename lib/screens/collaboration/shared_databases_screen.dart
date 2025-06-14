import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/enhanced_collaborative_provider.dart';
import '../../providers/auth_provider.dart';
import '../auth/login_screen.dart';
import 'invitations_screen.dart';
import 'database_users_screen.dart';

class SharedDatabasesScreen extends StatefulWidget {
  const SharedDatabasesScreen({Key? key}) : super(key: key);

  @override
  _SharedDatabasesScreenState createState() => _SharedDatabasesScreenState();
}

class _SharedDatabasesScreenState extends State<SharedDatabasesScreen> {
  final TextEditingController _importController = TextEditingController();
  final TextEditingController _createController = TextEditingController();
  bool _wasInGuestMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = context.read<AuthProvider>();
      
      _wasInGuestMode = authProvider.isGuestMode;
      
      if (!authProvider.isAuthenticated) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
        return;
      }
      
      if (authProvider.isGuestMode) {
        print('🚫 ИНИЦИАЛИЗАЦИЯ: Гостевой режим - загрузка баз данных пропущена');
        return;
      }
      
      _loadDatabases();
    });
  }

  @override
  void dispose() {
    _importController.dispose();
    _createController.dispose();
    super.dispose();
  }

  Future<void> _loadDatabases() async {
    final authProvider = context.read<AuthProvider>();
    if (authProvider.isGuestMode) {
      print('🚫 ЗАГРУЗКА: Загрузка баз данных заблокирована в гостевом режиме');
      return;
    }
    
    final provider = context.read<EnhancedCollaborativeProvider>();
    await provider.loadDatabases();
  }

  void _showCreateDialog() {
    final authProvider = context.read<AuthProvider>();
    if (authProvider.isGuestMode) {
      print('🚫 СОЗДАНИЕ: Создание баз данных заблокировано в гостевом режиме');
      return;
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Создать совместную базу данных'),
        content: TextField(
          controller: _createController,
          decoration: const InputDecoration(
            labelText: 'Название базы данных',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              if (_createController.text.isNotEmpty) {
                context.read<EnhancedCollaborativeProvider>().createDatabase(_createController.text);
                _createController.clear();
                Navigator.of(context).pop();
              }
            },
            child: const Text('Создать'),
          ),
        ],
      ),
    );
  }

  void _showImportDialog() {
    final authProvider = context.read<AuthProvider>();
    if (authProvider.isGuestMode) {
      print('🚫 ИМПОРТ: Импорт баз данных заблокирован в гостевом режиме');
      return;
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Присоединиться к базе данных'),
        content: const Text('Для присоединения к базе данных используйте приглашения.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<EnhancedCollaborativeProvider, AuthProvider>(
      builder: (context, provider, auth, _) {
        if (_wasInGuestMode && !auth.isGuestMode && auth.isAuthenticated) {
          print('🔄 ПЕРЕХОД: Обнаружен переход из гостевого режима в авторизованный - загружаем базы данных');
          _wasInGuestMode = false;
          
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _loadDatabases();
          });
        }
        
        if (!_wasInGuestMode && auth.isGuestMode) {
          _wasInGuestMode = true;
        }
        
        if (auth.isGuestMode) {
          return Scaffold(
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
          );
        }
        
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!provider.isServerAvailable) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Совместные базы данных'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    _loadDatabases();
                  },
                ),
              ],
            ),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.wifi_off,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Нет соединения с сервером',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Проверьте подключение к интернету\nи попробуйте обновить страницу',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      _loadDatabases();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Обновить'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (provider.error != null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Ошибка загрузки баз данных',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  provider.error!,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    _loadDatabases();
                  },
                  child: const Text('Повторить'),
                ),
              ],
            ),
          );
        }

        final databases = provider.databases;
        
        return Scaffold(
          appBar: AppBar(
            title: const Text('Совместные базы данных'),
            actions: [
              Consumer<EnhancedCollaborativeProvider>(
                builder: (context, provider, _) {
                  final invitationsCount = provider.pendingInvitations.length;
                  return Stack(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.mail),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const InvitationsScreen(),
                            ),
                          );
                        },
                      ),
                      if (invitationsCount > 0)
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
                            child: Text(
                              '$invitationsCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  _loadDatabases();
                },
              ),
              IconButton(
                icon: const Icon(Icons.import_export),
                onPressed: _showImportDialog,
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: databases.isEmpty
                    ? Center(
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
                            SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: _showCreateDialog,
                              icon: Icon(Icons.add),
                              label: Text('Создать новую базу данных'),
                              style: ElevatedButton.styleFrom(
                                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: databases.length,
                        itemBuilder: (context, index) {
                          final database = databases[index];
                          final isCurrentDatabase = provider.currentDatabaseId == database.id;
                          final currentUser = auth.user;
                          final isOwner = currentUser != null && 
                              database.ownerId == currentUser.id;

                          return Card(
                            margin: const EdgeInsets.all(8.0),
                            color: isCurrentDatabase 
                                ? Colors.blue.withOpacity(0.2)
                                : null,
                            child: ListTile(
                              title: Text(database.name),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Создана: ${database.createdAt.toLocal().toString().split(' ')[0]}'),
                                  Text('Участников: ${database.users.length}'),
                                  if (isCurrentDatabase)
                                    const Text(
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
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => DatabaseUsersScreen(database: database),
                                        ),
                                      ).then((_) {
                                        _loadDatabases();
                                      });
                                    },
                                  ),
                                  if (!isCurrentDatabase)
                                    IconButton(
                                      icon: const Icon(Icons.login),
                                      tooltip: 'Переключиться на эту базу',
                                      onPressed: () {
                                        provider.switchToDatabase(database.id);
                                      },
                                    ),
                                  if (isCurrentDatabase)
                                    IconButton(
                                      icon: const Icon(Icons.logout),
                                      tooltip: 'Переключиться на личную базу',
                                      onPressed: () {
                                        provider.switchToPersonalDatabase();
                                      },
                                    ),
                                  if (!isOwner)
                                    IconButton(
                                      icon: const Icon(Icons.exit_to_app),
                                      tooltip: 'Покинуть совместную базу',
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text('Покинуть базу данных'),
                                            content: const Text(
                                              'Вы уверены, что хотите покинуть эту совместную базу данных? Вы потеряете доступ к ней.',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.of(context).pop(),
                                                child: const Text('Отмена'),
                                              ),
                                              ElevatedButton(
                                                onPressed: () {
                                                  provider.leaveDatabase(database.id);
                                                  Navigator.of(context).pop();
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.orange,
                                                ),
                                                child: const Text('Покинуть'),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  if (isOwner)
                                    IconButton(
                                      icon: const Icon(Icons.delete),
                                      tooltip: 'Удалить базу данных',
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text('Удалить базу данных'),
                                            content: const Text(
                                              'Вы уверены, что хотите удалить эту базу данных? Это действие нельзя отменить.',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.of(context).pop(),
                                                child: const Text('Отмена'),
                                              ),
                                              ElevatedButton(
                                                onPressed: () {
                                                  provider.deleteDatabase(database.id);
                                                  Navigator.of(context).pop();
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.red,
                                                ),
                                                child: const Text('Удалить'),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                ],
                              ),
                              onTap: isCurrentDatabase ? null : () {
                                provider.switchToDatabase(database.id);
                              },
                            ),
                          );
                        },
                      ),
              ),
              if (databases.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _showCreateDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('Создать новую базу данных'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16.0),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
} 