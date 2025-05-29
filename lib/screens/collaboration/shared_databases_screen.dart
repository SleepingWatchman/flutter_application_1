import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/enhanced_collaborative_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/enhanced_collaborative_database.dart';
import '../../models/collaborative_database_role.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../auth/login_screen.dart';
import 'invitations_screen.dart';
import 'invite_user_screen.dart';

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
      context.read<EnhancedCollaborativeProvider>().loadDatabases();
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

  void _showCollaboratorsDialog(EnhancedCollaborativeDatabase database) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Участники'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: database.users.length,
            itemBuilder: (context, index) {
              final user = database.users[index];
              final isOwner = user.role == CollaborativeDatabaseRole.owner;
              final canManage = database.isOwner(context.read<AuthProvider>().user?.id ?? '');
              
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: user.photoURL != null 
                      ? NetworkImage(user.photoURL!) 
                      : null,
                  child: user.photoURL == null 
                      ? Text(user.displayName?.substring(0, 1).toUpperCase() ?? user.email.substring(0, 1).toUpperCase())
                      : null,
                ),
                title: Text(user.displayName ?? user.email),
                subtitle: Text(user.email),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Chip(
                      label: Text(isOwner ? 'Владелец' : 'Участник'),
                      backgroundColor: isOwner ? Colors.orange : Colors.blue,
                    ),
                    if (canManage && !isOwner) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () {
                          context.read<EnhancedCollaborativeProvider>().removeUser(
                                database.id,
                                user.userId,
                              );
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          if (database.isOwner(context.read<AuthProvider>().user?.id ?? '')) ...[
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => InviteUserScreen(database: database),
                  ),
                );
              },
              icon: const Icon(Icons.person_add),
              label: const Text('Пригласить'),
            ),
            const SizedBox(width: 8),
          ],
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
    return Consumer2<EnhancedCollaborativeProvider, AuthProvider>(
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