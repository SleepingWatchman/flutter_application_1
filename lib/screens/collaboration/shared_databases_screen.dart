import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/collaborative_database_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/collaborative_database.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../auth/login_screen.dart';

class SharedDatabasesScreen extends StatefulWidget {
  const SharedDatabasesScreen({Key? key}) : super(key: key);

  @override
  _SharedDatabasesScreenState createState() => _SharedDatabasesScreenState();
}

class _SharedDatabasesScreenState extends State<SharedDatabasesScreen> {
  final TextEditingController _importController = TextEditingController();
  final TextEditingController _createController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = context.read<AuthProvider>();
      if (!authProvider.isAuthenticated) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
        return;
      }
      context.read<CollaborativeDatabaseProvider>().loadDatabases();
    });
  }

  @override
  void dispose() {
    _importController.dispose();
    _createController.dispose();
    super.dispose();
  }

  void _showCreateDialog() {
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
                context.read<CollaborativeDatabaseProvider>().createDatabase(_createController.text);
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Импортировать базу данных'),
        content: TextField(
          controller: _importController,
          decoration: const InputDecoration(
            labelText: 'ID базы данных',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              if (_importController.text.isNotEmpty) {
                context.read<CollaborativeDatabaseProvider>().importDatabase(_importController.text);
                _importController.clear();
                Navigator.of(context).pop();
              }
            },
            child: const Text('Импортировать'),
          ),
        ],
      ),
    );
  }

  void _showCollaboratorsDialog(CollaborativeDatabase database) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Соавторы'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(database.ownerId),
              subtitle: const Text('Владелец'),
            ),
            ...database.collaborators.entries.map(
              (entry) => ListTile(
                title: Text(entry.key),
                subtitle: Text(entry.value == CollaborativeDatabaseRole.owner ? 'Владелец' : 'Соавтор'),
                trailing: database.isOwner(context.read<AuthProvider>().user!.id)
                    ? IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () {
                          context.read<CollaborativeDatabaseProvider>().removeCollaborator(
                                database.id,
                                entry.key,
                              );
                          Navigator.of(context).pop();
                        },
                      )
                    : null,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<CollaborativeDatabaseProvider, AuthProvider>(
      builder: (context, provider, auth, _) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
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
                    provider.loadDatabases();
                  },
                  child: const Text('Повторить'),
                ),
              ],
            ),
          );
        }

        final databases = provider.databases;
        
        if (databases.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Нет доступных баз данных',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _showCreateDialog,
                  child: const Text('Создать базу данных'),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Совместные базы данных'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  provider.loadDatabases();
                },
              ),
              IconButton(
                icon: const Icon(Icons.import_export),
                onPressed: _showImportDialog,
              ),
            ],
          ),
          body: ListView.builder(
            itemCount: databases.length,
            itemBuilder: (context, index) {
              final database = databases[index];
              final isOwner = database.isOwner(auth.user!.id);

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  title: Text(database.name),
                  subtitle: Text(
                    isOwner ? 'Владелец' : 'Соавтор',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.people),
                        onPressed: () => _showCollaboratorsDialog(database),
                      ),
                      IconButton(
                        icon: Icon(
                          provider.isUsingSharedDatabase && 
                          provider.currentDatabaseId == database.id
                            ? Icons.check_circle
                            : Icons.swap_horiz,
                          color: provider.isUsingSharedDatabase && 
                                provider.currentDatabaseId == database.id
                            ? Colors.green
                            : null,
                        ),
                        onPressed: () async {
                          if (provider.isUsingSharedDatabase && 
                              provider.currentDatabaseId == database.id) {
                            // Переключение на личную базу
                            await provider.switchToPersonalDatabase();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Переключено на личную базу данных'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } else {
                            // Переключение на совместную базу
                            try {
                              await provider.switchToDatabase(database.id);
                              
                              // Обновляем UI, чтобы отразить изменения
                              setState(() {});
                              
                              // Перезагружаем данные во всех экранах
                              final databaseProvider = context.read<DatabaseProvider>();
                              databaseProvider.setNeedsUpdate(true);
                              
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Переключено на совместную базу данных'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Ошибка переключения базы: ${e.toString()}'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          }
                        },
                      ),
                      if (isOwner)
                        IconButton(
                          icon: const Icon(Icons.delete),
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
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.exit_to_app),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Покинуть базу данных'),
                                content: const Text(
                                  'Вы уверены, что хотите покинуть эту базу данных?',
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
                                    child: const Text('Покинуть'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: _showCreateDialog,
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }
} 