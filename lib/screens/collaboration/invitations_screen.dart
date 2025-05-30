import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/enhanced_collaborative_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/collaborative_database_role.dart';
import '../../utils/toast_utils.dart';

class InvitationsScreen extends StatefulWidget {
  const InvitationsScreen({Key? key}) : super(key: key);

  @override
  _InvitationsScreenState createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends State<InvitationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EnhancedCollaborativeProvider>().loadDatabases();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Приглашения'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<EnhancedCollaborativeProvider>().loadDatabases();
            },
          ),
        ],
      ),
      body: Consumer2<EnhancedCollaborativeProvider, AuthProvider>(
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
                    'Ошибка загрузки приглашений',
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

          final invitations = provider.pendingInvitations;

          if (invitations.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.mail_outline,
                    size: 64,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Нет приглашений',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Когда вас пригласят в совместную базу данных,\nприглашения появятся здесь',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: invitations.length,
            itemBuilder: (context, index) {
              final invitation = invitations[index];
              final databaseName = invitation['database_name'] as String? ?? 'Неизвестная база';
              final inviterEmail = invitation['inviter_email'] as String? ?? 'Неизвестный пользователь';
              final role = invitation['role'] as String? ?? 'collaborator';
              final invitationId = invitation['id']?.toString() ?? '';
              final createdAt = invitation['created_at'] as String?;
              
              DateTime? invitationDate;
              if (createdAt != null) {
                try {
                  invitationDate = DateTime.parse(createdAt);
                } catch (e) {
                  print('Ошибка парсинга даты: $e');
                }
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.people,
                            color: Colors.blue,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              databaseName,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Chip(
                            label: Text(
                              role == 'owner' ? 'Владелец' : 'Участник',
                              style: const TextStyle(fontSize: 12),
                            ),
                            backgroundColor: role == 'owner' ? Colors.orange : Colors.blue,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Приглашение от: $inviterEmail',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (invitationDate != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Дата: ${_formatDate(invitationDate)}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () async {
                              try {
                                await _declineInvitation(invitationId);
                              } catch (e) {
                                if (context.mounted) {
                                  showCustomToastWithIcon(
                                    'Ошибка отклонения приглашения: $e',
                                    accentColor: Colors.red,
                                    fontSize: 14.0,
                                    icon: const Icon(Icons.error, size: 20, color: Colors.red),
                                  );
                                }
                              }
                            },
                            child: const Text('Отклонить'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () async {
                              try {
                                await _acceptInvitation(invitationId);
                              } catch (e) {
                                if (context.mounted) {
                                  showCustomToastWithIcon(
                                    'Ошибка принятия приглашения: $e',
                                    accentColor: Colors.red,
                                    fontSize: 14.0,
                                    icon: const Icon(Icons.error, size: 20, color: Colors.red),
                                  );
                                }
                              }
                            },
                            child: const Text('Принять'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Сегодня в ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Вчера в ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} дн. назад';
    } else {
      return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    }
  }

  Future<void> _acceptInvitation(String invitationId) async {
    try {
      final provider = context.read<EnhancedCollaborativeProvider>();
      await provider.acceptInvitation(invitationId);
      
      if (mounted) {
        showCustomToastWithIcon(
          'Приглашение принято',
          accentColor: Colors.green,
          fontSize: 14.0,
          icon: const Icon(Icons.check, size: 20, color: Colors.green),
        );
        context.read<EnhancedCollaborativeProvider>().loadDatabases();
      }
    } catch (e) {
      if (mounted) {
        showCustomToastWithIcon(
          'Ошибка принятия приглашения: $e',
          accentColor: Colors.red,
          fontSize: 14.0,
          icon: const Icon(Icons.error, size: 20, color: Colors.red),
        );
      }
    }
  }

  Future<void> _declineInvitation(String invitationId) async {
    try {
      final provider = context.read<EnhancedCollaborativeProvider>();
      await provider.declineInvitation(invitationId);
      
      if (mounted) {
        showCustomToastWithIcon(
          'Приглашение отклонено',
          accentColor: Colors.orange,
          fontSize: 14.0,
          icon: const Icon(Icons.close, size: 20, color: Colors.orange),
        );
        context.read<EnhancedCollaborativeProvider>().loadDatabases();
      }
    } catch (e) {
      if (mounted) {
        showCustomToastWithIcon(
          'Ошибка отклонения приглашения: $e',
          accentColor: Colors.red,
          fontSize: 14.0,
          icon: const Icon(Icons.error, size: 20, color: Colors.red),
        );
      }
    }
  }
} 