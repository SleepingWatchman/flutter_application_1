import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/enhanced_collaborative_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/enhanced_collaborative_database.dart';
import '../../models/collaborative_database_role.dart';
import '../../utils/toast_utils.dart';
import 'invite_user_screen.dart';

class DatabaseUsersScreen extends StatefulWidget {
  final EnhancedCollaborativeDatabase database;

  const DatabaseUsersScreen({
    Key? key,
    required this.database,
  }) : super(key: key);

  @override
  _DatabaseUsersScreenState createState() => _DatabaseUsersScreenState();
}

class _DatabaseUsersScreenState extends State<DatabaseUsersScreen> {
  late EnhancedCollaborativeDatabase _database;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _database = widget.database;
    _loadDatabaseUsers();
  }

  Future<void> _loadDatabaseUsers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final provider = context.read<EnhancedCollaborativeProvider>();
      await provider.loadDatabases(); // Обновляем данные о пользователях
      
      // Обновляем локальную копию базы данных
      final updatedDatabase = provider.databases.firstWhere(
        (db) => db.id == _database.id,
        orElse: () => _database,
      );
      
      if (mounted) {
        setState(() {
          _database = updatedDatabase;
        });
      }
    } catch (e) {
      print('Ошибка загрузки пользователей базы данных: $e');
      if (mounted) {
        showCustomToastWithIcon(
          'Ошибка загрузки пользователей',
          accentColor: Colors.red,
          fontSize: 14.0,
          icon: const Icon(Icons.error, size: 20, color: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _removeUser(String userId, String userEmail) async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.user;
    
    if (currentUser == null || !_database.canRemoveUser(currentUser.id, userId)) {
      showCustomToastWithIcon(
        'У вас нет прав на удаление этого пользователя',
        accentColor: Colors.red,
        fontSize: 14.0,
        icon: const Icon(Icons.error, size: 20, color: Colors.red),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить пользователя'),
        content: Text(
          'Вы уверены, что хотите удалить пользователя $userEmail из совместной базы данных "${_database.name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final provider = context.read<EnhancedCollaborativeProvider>();
      await provider.removeUser(_database.id, userId);
      
      await _loadDatabaseUsers(); // Перезагружаем список пользователей
      
      if (mounted) {
        showCustomToastWithIcon(
          'Пользователь успешно удален',
          accentColor: Colors.green,
          fontSize: 14.0,
          icon: const Icon(Icons.check, size: 20, color: Colors.green),
        );
      }
    } catch (e) {
      print('Ошибка удаления пользователя: $e');
      if (mounted) {
        showCustomToastWithIcon(
          'Ошибка удаления пользователя',
          accentColor: Colors.red,
          fontSize: 14.0,
          icon: const Icon(Icons.error, size: 20, color: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _changeUserRole(String userId, String userEmail, CollaborativeDatabaseRole newRole) async {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.user;
    
    if (currentUser == null || !_database.canChangeRoleOf(currentUser.id, userId)) {
      showCustomToastWithIcon(
        'У вас нет прав на изменение роли этого пользователя',
        accentColor: Colors.red,
        fontSize: 14.0,
        icon: const Icon(Icons.error, size: 20, color: Colors.red),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final provider = context.read<EnhancedCollaborativeProvider>();
      await provider.updateUserRole(_database.id, userId, newRole);
      
      await _loadDatabaseUsers(); // Перезагружаем список пользователей
      
      if (mounted) {
        showCustomToastWithIcon(
          'Роль пользователя успешно изменена',
          accentColor: Colors.green,
          fontSize: 14.0,
          icon: const Icon(Icons.check, size: 20, color: Colors.green),
        );
      }
    } catch (e) {
      print('Ошибка изменения роли пользователя: $e');
      if (mounted) {
        showCustomToastWithIcon(
          'Ошибка изменения роли пользователя',
          accentColor: Colors.red,
          fontSize: 14.0,
          icon: const Icon(Icons.error, size: 20, color: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showRoleChangeDialog(String userId, String userEmail, CollaborativeDatabaseRole currentRole) {
    final authProvider = context.read<AuthProvider>();
    final currentUser = authProvider.user;
    final isOriginalOwner = currentUser != null && _database.isOriginalOwner(currentUser.id);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Изменить роль пользователя'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Пользователь: $userEmail'),
            const SizedBox(height: 16),
            const Text('Выберите новую роль:'),
            const SizedBox(height: 8),
            RadioListTile<CollaborativeDatabaseRole>(
              title: const Text('Участник'),
              subtitle: const Text('Может просматривать и редактировать данные'),
              value: CollaborativeDatabaseRole.collaborator,
              groupValue: currentRole,
              onChanged: (value) {
                if (value != null) {
                  Navigator.of(context).pop();
                  _changeUserRole(userId, userEmail, value);
                }
              },
            ),
            if (isOriginalOwner) 
              RadioListTile<CollaborativeDatabaseRole>(
                title: const Text('Владелец'),
                subtitle: const Text('Полные права на управление базой данных'),
                value: CollaborativeDatabaseRole.owner,
                groupValue: currentRole,
                onChanged: (value) {
                  if (value != null) {
                    Navigator.of(context).pop();
                    _changeUserRole(userId, userEmail, value);
                  }
                },
              ),
            if (!isOriginalOwner && currentRole == CollaborativeDatabaseRole.owner)
              Container(
                margin: const EdgeInsets.only(top: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Только создатель базы может изменять роли владельцев',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final currentUser = authProvider.user;
    final canInvite = currentUser != null && _database.canInviteUsers(currentUser.id);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Участники'),
            Text(
              _database.name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          if (canInvite) ...[
            IconButton(
              icon: const Icon(Icons.person_add),
              tooltip: 'Пригласить пользователя',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => InviteUserScreen(database: _database),
                  ),
                ).then((_) {
                  // Обновляем список пользователей после возврата с экрана приглашения
                  _loadDatabaseUsers();
                });
              },
            ),
          ],
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
            onPressed: _loadDatabaseUsers,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _database.users.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 64,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Нет участников',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _database.users.length,
                  itemBuilder: (context, index) {
                    final user = _database.users[index];
                    final isUserOwner = user.role == CollaborativeDatabaseRole.owner;
                    final isCurrentUser = currentUser?.id == user.userId;
                    
                    final canManageThisUser = currentUser != null && 
                        _database.canManageUser(currentUser.id, user.userId);
                    final canRemoveThisUser = currentUser != null && 
                        _database.canRemoveUser(currentUser.id, user.userId);
                    final canChangeRoleOfThisUser = currentUser != null && 
                        _database.canChangeRoleOf(currentUser.id, user.userId);

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundImage: user.photoURL != null && user.photoURL!.isNotEmpty
                              ? NetworkImage(user.photoURL!)
                              : null,
                          child: user.photoURL == null || user.photoURL!.isEmpty
                              ? Text(
                                  user.displayName?.substring(0, 1).toUpperCase() ?? 
                                  user.email.substring(0, 1).toUpperCase(),
                                )
                              : null,
                        ),
                        title: Text(
                          user.displayName ?? user.email,
                          style: TextStyle(
                            fontWeight: isCurrentUser ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user.email),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Chip(
                                  label: Text(
                                    isUserOwner ? 'Владелец' : 'Участник',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  backgroundColor: isUserOwner ? Colors.orange : Colors.blue,
                                  labelStyle: const TextStyle(color: Colors.white),
                                ),
                                if (isCurrentUser) ...[
                                  const SizedBox(width: 8),
                                  const Chip(
                                    label: Text(
                                      'Вы',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    backgroundColor: Colors.green,
                                    labelStyle: TextStyle(color: Colors.white),
                                  ),
                                ],
                                if (_database.isOriginalOwner(user.userId)) ...[
                                  const SizedBox(width: 8),
                                  const Chip(
                                    label: Text(
                                      'Создатель',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    backgroundColor: Colors.purple,
                                    labelStyle: TextStyle(color: Colors.white),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                        trailing: canManageThisUser && !isCurrentUser
                            ? PopupMenuButton<String>(
                                onSelected: (value) {
                                  switch (value) {
                                    case 'change_role':
                                      _showRoleChangeDialog(user.userId, user.email, user.role);
                                      break;
                                    case 'remove':
                                      _removeUser(user.userId, user.email);
                                      break;
                                  }
                                },
                                itemBuilder: (context) => [
                                  if (canChangeRoleOfThisUser)
                                    const PopupMenuItem(
                                      value: 'change_role',
                                      child: Row(
                                        children: [
                                          Icon(Icons.admin_panel_settings),
                                          SizedBox(width: 8),
                                          Text('Изменить роль'),
                                        ],
                                      ),
                                    ),
                                  if (canRemoveThisUser)
                                    const PopupMenuItem(
                                      value: 'remove',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete, color: Colors.red),
                                          SizedBox(width: 8),
                                          Text(
                                            'Удалить',
                                            style: TextStyle(color: Colors.red),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              )
                            : null,
                      ),
                    );
                  },
                ),
    );
  }
} 