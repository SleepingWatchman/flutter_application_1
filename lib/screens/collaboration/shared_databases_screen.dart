import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/collaboration_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/shared_database.dart';

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
      context.read<CollaborationProvider>().loadSharedDatabases();
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
            onPressed: () {
              if (_createController.text.isNotEmpty) {
                context.read<CollaborationProvider>().createSharedDatabase(
                      _createController.text,
                    );
                _createController.clear();
                Navigator.pop(context);
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
            onPressed: () {
              if (_importController.text.isNotEmpty) {
                context.read<CollaborationProvider>().importSharedDatabase(
                      _importController.text,
                    );
                _importController.clear();
                Navigator.pop(context);
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
        title: const Text('Совместные базы'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showCreateDialog,
          ),
          IconButton(
            icon: const Icon(Icons.import_export),
            onPressed: _showImportDialog,
          ),
        ],
      ),
      body: Consumer<CollaborationProvider>(
        builder: (context, provider, child) {
          final databases = provider.sharedDatabases;
          final currentDatabaseId = provider.currentDatabaseId;
          final isUsingSharedDatabase = provider.isUsingSharedDatabase;

          if (databases.isEmpty) {
            return const Center(
              child: Text('Нет доступных совместных баз'),
            );
          }

          return ListView.builder(
            itemCount: databases.length,
            itemBuilder: (context, index) {
              final database = databases[index];
              final isCurrent = database.id == currentDatabaseId;
              final isOwner = database.ownerId ==
                  context.read<AuthProvider>().user?.id;

              return ListTile(
                title: Text(database.name),
                subtitle: Text(
                  isOwner ? 'Владелец' : 'Участник',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isCurrent)
                      const Icon(Icons.check_circle, color: Colors.green)
                    else
                      IconButton(
                        icon: const Icon(Icons.swap_horiz),
                        onPressed: () =>
                            provider.switchToSharedDatabase(database.id),
                      ),
                    if (isOwner)
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () =>
                            provider.removeSharedDatabase(database.id),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.exit_to_app),
                        onPressed: () =>
                            provider.leaveSharedDatabase(database.id),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: Consumer<CollaborationProvider>(
        builder: (context, provider, child) {
          if (provider.isUsingSharedDatabase) {
            return FloatingActionButton(
              onPressed: () => provider.switchToPersonalDatabase(),
              child: const Icon(Icons.person),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
} 