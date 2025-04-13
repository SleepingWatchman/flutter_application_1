import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/collaboration_provider.dart';
import '../../providers/backup_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';

class CollaborationScreen extends StatefulWidget {
  const CollaborationScreen({super.key});

  @override
  State<CollaborationScreen> createState() => _CollaborationScreenState();
}

class _CollaborationScreenState extends State<CollaborationScreen> {
  static const String _baseUrl = 'http://127.0.0.1:5294/api/collaboration';

  Future<Map<String, dynamic>> uploadDatabase(Map<String, dynamic> backupData, int databaseId) async {
    final token = context.read<AuthProvider>().token;
    if (token == null) {
      throw Exception('Не авторизован');
    }

    final response = await http.post(
      Uri.parse('$_baseUrl/databases/$databaseId/backup'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(backupData),
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка при загрузке базы данных на сервер: ${response.statusCode}');
    }

    return {'databaseId': databaseId};
  }

  Future<Map<String, dynamic>> downloadDatabase(int databaseId) async {
    final token = context.read<AuthProvider>().token;
    if (token == null) {
      throw Exception('Не авторизован');
    }

    final response = await http.get(
      Uri.parse('$_baseUrl/databases/$databaseId/backup'),
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Ошибка при загрузке базы данных: ${response.statusCode}');
    }

    return jsonDecode(response.body);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CollaborationProvider>().loadDatabases();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Совместное редактирование'),
      ),
      body: Consumer<CollaborationProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton(
                      onPressed: () => provider.createNewDatabase(),
                      child: const Text('Создать новую базу данных'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Импорт базы данных'),
                            content: TextField(
                              decoration: const InputDecoration(
                                labelText: 'Введите ID базы данных',
                                hintText: 'ID',
                              ),
                              keyboardType: TextInputType.number,
                              onSubmitted: (value) async {
                                try {
                                  final databaseId = int.parse(value);
                                  final backupData = await downloadDatabase(databaseId);
                                  await provider.createNewDatabase();
                                  await uploadDatabase(backupData, provider.databases.last['id']);

                                  if (context.mounted) {
                                    Navigator.of(context).pop();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('База данных успешно импортирована')),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Ошибка при импорте базы данных: $e')),
                                    );
                                  }
                                }
                              },
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Отмена'),
                              ),
                            ],
                          ),
                        );
                      },
                      child: const Text('Импортировать базу данных'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: provider.databases.length,
                  itemBuilder: (context, index) {
                    final db = provider.databases[index];
                    final createdAt = DateTime.parse(db['createdAt']);
                    return ListTile(
                      title: Row(
                        children: [
                          Text('База данных ID: ${db['id']}'),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 20),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: db['id'].toString()));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('ID скопирован в буфер обмена'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            tooltip: 'Копировать ID',
                          ),
                        ],
                      ),
                      subtitle: Text('Создана: ${createdAt.toString().substring(0, 16)}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.download),
                            onPressed: () async {
                              try {
                                // 1. Создаем резервную копию пользовательской базы данных
                                await context.read<BackupProvider>().uploadBackup();
                                
                                // 2. Загружаем базу данных с сервера и заменяем локальную
                                final backupData = await context.read<CollaborationProvider>().downloadDatabase(db['id']);
                                await context.read<CollaborationProvider>().replaceLocalDatabase(backupData, db['id']);

                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('База данных успешно загружена')),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Ошибка при загрузке базы данных: $e')),
                                  );
                                }
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.sync),
                            onPressed: () async {
                              try {
                                // 1. Загружаем данные из локальной базы на сервер
                                final backupData = await context.read<CollaborationProvider>().downloadDatabase(db['id']);
                                await context.read<CollaborationProvider>().uploadDatabase(backupData, db['id']);
                                
                                // 2. Восстанавливаем пользовательскую базу данных
                                await context.read<BackupProvider>().downloadBackup();

                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('База данных успешно синхронизирована')),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Ошибка при синхронизации базы данных: $e')),
                                  );
                                }
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Удаление базы данных'),
                                  content: const Text('Вы уверены, что хотите удалить эту базу данных?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(context).pop(),
                                      child: const Text('Отмена'),
                                    ),
                                    TextButton(
                                      onPressed: () async {
                                        try {
                                          final token = context.read<AuthProvider>().token;
                                          if (token == null) {
                                            throw Exception('Не авторизован');
                                          }

                                          final response = await http.delete(
                                            Uri.parse('$_baseUrl/databases/${db['id']}'),
                                            headers: {
                                              'Authorization': 'Bearer $token',
                                            },
                                          );

                                          if (response.statusCode != 200) {
                                            throw Exception('Ошибка при удалении базы данных: ${response.statusCode}');
                                          }

                                          if (context.mounted) {
                                            Navigator.of(context).pop();
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('База данных успешно удалена')),
                                            );
                                          }

                                          await provider.loadDatabases();
                                        } catch (e) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Ошибка при удалении базы данных: $e')),
                                            );
                                          }
                                        }
                                      },
                                      child: const Text('Удалить'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
} 