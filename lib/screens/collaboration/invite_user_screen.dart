import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/enhanced_collaborative_provider.dart';
import '../../models/enhanced_collaborative_database.dart';
import '../../models/collaborative_database_role.dart';
import '../../utils/toast_utils.dart';
import '../../providers/auth_provider.dart';

class InviteUserScreen extends StatefulWidget {
  final EnhancedCollaborativeDatabase database;

  const InviteUserScreen({
    Key? key,
    required this.database,
  }) : super(key: key);

  @override
  _InviteUserScreenState createState() => _InviteUserScreenState();
}

class _InviteUserScreenState extends State<InviteUserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  CollaborativeDatabaseRole _selectedRole = CollaborativeDatabaseRole.collaborator;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendInvitation() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final provider = context.read<EnhancedCollaborativeProvider>();
      await provider.inviteUser(
        widget.database.id,
        _emailController.text.trim(),
        _selectedRole,
      );

      if (mounted) {
        Navigator.of(context).pop();
        showCustomToastWithIcon(
          'Приглашение отправлено',
          accentColor: Colors.green,
          fontSize: 14.0,
          icon: const Icon(Icons.check, size: 20, color: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        showCustomToastWithIcon(
          'Ошибка отправки приглашения: $e',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Пригласить пользователя'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'База данных',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.database.name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Email пользователя',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  hintText: 'example@email.com',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Введите email пользователя';
                  }
                  if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim())) {
                    return 'Введите корректный email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              Text(
                'Роль пользователя',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Consumer<AuthProvider>(
                builder: (context, authProvider, child) {
                  final currentUser = authProvider.user;
                  final isOriginalOwner = currentUser != null && widget.database.isOriginalOwner(currentUser.id);
                  
                  return Card(
                    child: Column(
                      children: [
                        RadioListTile<CollaborativeDatabaseRole>(
                          title: const Text('Участник'),
                          subtitle: const Text('Может просматривать и редактировать данные'),
                          value: CollaborativeDatabaseRole.collaborator,
                          groupValue: _selectedRole,
                          onChanged: (value) {
                            setState(() {
                              _selectedRole = value!;
                            });
                          },
                        ),
                        if (isOriginalOwner) ...[
                          const Divider(height: 1),
                          RadioListTile<CollaborativeDatabaseRole>(
                            title: const Text('Владелец'),
                            subtitle: const Text('Полный доступ, включая управление пользователями'),
                            value: CollaborativeDatabaseRole.owner,
                            groupValue: _selectedRole,
                            onChanged: (value) {
                              setState(() {
                                _selectedRole = value!;
                              });
                            },
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _sendInvitation,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Отправить приглашение'),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                color: Colors.blue.withOpacity(0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.blue[700],
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Информация',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Colors.blue[700],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Consumer<AuthProvider>(
                        builder: (context, authProvider, child) {
                          final currentUser = authProvider.user;
                          final isOriginalOwner = currentUser != null && widget.database.isOriginalOwner(currentUser.id);
                          
                          return Text(
                            isOriginalOwner 
                              ? '• Пользователь получит приглашение по email\n'
                                '• Он сможет принять или отклонить приглашение\n'
                                '• После принятия получит доступ к совместной базе данных\n'
                                '• Роль можно изменить позже в настройках базы данных\n'
                                '• Только создатель базы может назначать роль владельца'
                              : '• Пользователь получит приглашение по email\n'
                                '• Он сможет принять или отклонить приглашение\n'
                                '• После принятия получит доступ к совместной базе данных\n'
                                '• Роль можно изменить позже в настройках базы данных\n'
                                '• Приглашенные владельцы могут приглашать только участников',
                            style: const TextStyle(fontSize: 14),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 