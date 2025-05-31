import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'dart:io' show Platform, exit;
import '../../providers/auth_provider.dart';
import '../../providers/backup_provider.dart';
import '../../utils/toast_utils.dart';
import 'edit_profile_screen.dart';
import '../auth/login_screen.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({Key? key}) : super(key: key);

  void _openLoginScreen(BuildContext context) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
    );
    
    // Если вход был успешным, закрываем экран аккаунта
    if (result == true) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AuthProvider, BackupProvider>(
      builder: (context, auth, backup, _) {
        final user = auth.user;
        
        return Scaffold(
          appBar: AppBar(
            title: const Text('Аккаунт'),
          ),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Hero(
                  tag: 'profile_button',
                  child: CircleAvatar(
                    radius: 50,
                    backgroundImage: user?.photoURL != null && user!.photoURL!.isNotEmpty
                        ? NetworkImage('${user!.photoURL!}?t=${DateTime.now().millisecondsSinceEpoch}')
                        : null,
                    child: user?.photoURL == null || user!.photoURL!.isEmpty
                        ? const Icon(Icons.person, size: 50)
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  user != null 
                      ? (user.displayName ?? user.email)
                      : 'Гость',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                if (user != null) ...[
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const EditProfileScreen(),
                        ),
                      );
                    },
                    child: const Text('Редактировать профиль'),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Резервное копирование'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ElevatedButton(
                                onPressed: () async {
                                  try {
                                    await backup.uploadBackup();
                                    if (context.mounted) {
                                      Navigator.of(context).pop();
                                      showCustomToastWithIcon(
                                        'Резервная копия успешно загружена',
                                        accentColor: Colors.green,
                                        fontSize: 14.0,
                                        icon: const Icon(Icons.check, size: 20, color: Colors.green),
                                      );
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      Navigator.of(context).pop();
                                      showCustomToastWithIcon(
                                        'Ошибка загрузки резервной копии: $e',
                                        accentColor: Colors.red,
                                        fontSize: 14.0,
                                        icon: const Icon(Icons.error, size: 20, color: Colors.red),
                                      );
                                    }
                                  }
                                },
                                child: const Text('Загрузить данные на сервер'),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: () async {
                                  try {
                                    await backup.downloadBackup();
                                    if (context.mounted) {
                                      Navigator.of(context).pop();
                                      showCustomToastWithIcon(
                                        'Резервная копия успешно восстановлена',
                                        accentColor: Colors.green,
                                        fontSize: 14.0,
                                        icon: const Icon(Icons.check, size: 20, color: Colors.green),
                                      );
                                      
                                      // Если требуется перезагрузка, показываем диалог
                                      if (backup.needsReload) {
                                        if (context.mounted) {
                                          showDialog(
                                            context: context,
                                            barrierDismissible: false,
                                            builder: (context) => AlertDialog(
                                              title: const Text('Перезагрузка требуется'),
                                              content: const Text('Для корректного отображения данных необходимо перезапустить приложение. Приложение будет закрыто, и вам нужно будет запустить его снова вручную.'),
                                              actions: [
                                                TextButton(
                                                  onPressed: () {
                                                    // Сбрасываем флаг перезагрузки
                                                    backup.resetReloadFlag();
                                                    Navigator.of(context).pop();
                                                  },
                                                  child: const Text('Позже'),
                                                ),
                                                TextButton(
                                                  onPressed: () {
                                                    // Перезапускаем приложение
                                                    Navigator.of(context).pop();
                                                    
                                                    // Безопасный способ перезапуска приложения
                                                    if (Platform.isWindows) {
                                                      // На Windows используем exit(0), чтобы закрыть приложение
                                                      // Пользователь может запустить его снова вручную
                                                      exit(0);
                                                    } else {
                                                      // На других платформах используем SystemNavigator
                                                      SystemNavigator.pop();
                                                    }
                                                  },
                                                  child: const Text('Закрыть сейчас'),
                                                ),
                                              ],
                                            ),
                                          );
                                        }
                                      }
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      Navigator.of(context).pop();
                                      showCustomToastWithIcon(
                                        'Ошибка восстановления резервной копии: $e',
                                        accentColor: Colors.red,
                                        fontSize: 14.0,
                                        icon: const Icon(Icons.error, size: 20, color: Colors.red),
                                      );
                                    }
                                  }
                                },
                                child: const Text('Выгрузить данные с сервера'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    child: const Text('Резервное копирование'),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () {
                      auth.signOut(() {
                        if (context.mounted) {
                          showCustomToastWithIcon(
                            'Резервная копия создана перед выходом из аккаунта',
                            accentColor: Colors.green,
                            fontSize: 14.0,
                            icon: const Icon(Icons.check, size: 20, color: Colors.green),
                          );
                        }
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: auth.isCreatingBackupOnSignOut
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text('Создание бэкапа...'),
                            ],
                          )
                        : const Text('Выйти'),
                  ),
                ] else ...[
                  ElevatedButton(
                    onPressed: () => _openLoginScreen(context),
                    child: const Text('Войти в аккаунт'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
} 