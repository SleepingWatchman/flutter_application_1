import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/collaboration_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/shared_database.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

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
      context.read<CollaborationProvider>().loadDatabases();
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
        title: const Text('Создать совместную базу'),
        content: TextField(
          controller: _createController,
          decoration: const InputDecoration(
            labelText: 'Название базы',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () async {
              if (_createController.text.isNotEmpty) {
                try {
                  await context.read<CollaborationProvider>().createDatabase(_createController.text);
                  _createController.clear();
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('База данных успешно создана')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Ошибка при создании базы данных: $e')),
                    );
                  }
                }
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
        title: const Text('Импорт совместной базы'),
        content: TextField(
          controller: _importController,
          decoration: const InputDecoration(
            labelText: 'ID базы',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () async {
              if (_importController.text.isNotEmpty) {
                try {
                  await context.read<CollaborationProvider>().importDatabase(_importController.text);
                  _importController.clear();
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('База данных успешно импортирована'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Ошибка при импорте базы данных: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            child: const Text('Импорт'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Совместные базы данных'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<CollaborationProvider>().loadDatabases();
            },
          ),
          IconButton(
            icon: const Icon(Icons.import_export),
            onPressed: _showImportDialog,
          ),
        ],
      ),
      body: Consumer2<CollaborationProvider, AuthProvider>(
        builder: (context, collaborationProvider, authProvider, _) {
          if (collaborationProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (collaborationProvider.error != null) {
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
                    collaborationProvider.error!,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      collaborationProvider.loadDatabases();
                    },
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            );
          }

          final databases = collaborationProvider.databases;
          
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

          return ListView.builder(
            itemCount: databases.length,
            itemBuilder: (context, index) {
              final database = databases[index];
              final isOwner = database.ownerId == authProvider.user?.id;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  title: Text(database.name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('ID: ${database.id}'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 16),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: database.id));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('ID скопирован в буфер обмена'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      Text('Создана: ${database.createdAt.toLocal()}'),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          collaborationProvider.isUsingSharedDatabase && 
                          collaborationProvider.currentDatabaseId == database.id
                            ? Icons.check_circle
                            : Icons.swap_horiz,
                          color: collaborationProvider.isUsingSharedDatabase && 
                                collaborationProvider.currentDatabaseId == database.id
                            ? Colors.green
                            : null,
                        ),
                        onPressed: () async {
                          if (collaborationProvider.isUsingSharedDatabase && 
                              collaborationProvider.currentDatabaseId == database.id) {
                            // Переключение на личную базу
                            await collaborationProvider.switchToPersonalDatabase();
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
                            await collaborationProvider.switchToSharedDatabase(database.id);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Переключено на совместную базу данных'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          }
                        },
                      ),
                      IconButton(
                        icon: Icon(
                          isOwner ? Icons.delete : Icons.exit_to_app,
                          color: isOwner ? Colors.red : null,
                        ),
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text(
                                isOwner
                                    ? 'Удалить базу данных?'
                                    : 'Выйти из базы данных?',
                              ),
                              content: Text(
                                isOwner
                                    ? 'База данных будет удалена для всех пользователей'
                                    : 'Вы потеряете доступ к этой базе данных',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('Отмена'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: Text(
                                    isOwner ? 'Удалить' : 'Выйти',
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          );

                          if (confirmed == true) {
                            try {
                              if (isOwner) {
                                await collaborationProvider.removeDatabase(database.id);
                              } else {
                                await collaborationProvider.leaveDatabase(database.id);
                              }
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      isOwner
                                          ? 'База данных удалена'
                                          : 'Вы вышли из базы данных',
                                    ),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Ошибка: $e'),
                                  ),
                                );
                              }
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
} 