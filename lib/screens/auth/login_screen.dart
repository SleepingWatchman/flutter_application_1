import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:oktoast/oktoast.dart';
import '../../providers/auth_provider.dart';
import '../../utils/toast_utils.dart';
import 'register_screen.dart';
import '../../widgets/server_status_indicator.dart';
import '../settings_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isRegistering = false;

  // Добавляем переменные для отслеживания состояния полей
  bool _emailHasError = false;
  bool _passwordHasError = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _login() async {
    // Сбрасываем состояния ошибок
    setState(() {
      _emailHasError = false;
      _passwordHasError = false;
    });
    
    // Проверяем поля вручную для подсветки ошибок
    bool hasErrors = false;
    
    if (_emailController.text.trim().isEmpty) {
      setState(() {
        _emailHasError = true;
      });
      hasErrors = true;
    } else if (!_emailController.text.contains('@')) {
      setState(() {
        _emailHasError = true;
      });
      hasErrors = true;
    }
    
    if (_passwordController.text.trim().isEmpty) {
      setState(() {
        _passwordHasError = true;
      });
      hasErrors = true;
    }
    
    if (hasErrors) {
      return; // Не продолжаем, если есть ошибки
    }
    
    if (_formKey.currentState?.validate() ?? false) {
      try {
        final auth = Provider.of<AuthProvider>(context, listen: false);
        await auth.signIn(
          _emailController.text.trim(),
          _passwordController.text.trim(),
          () {
            if (mounted) {
              showCustomToastWithIcon(
                'Данные пользователя успешно восстановлены из резервной копии',
                accentColor: Colors.green,
                fontSize: 14.0,
                icon: const Icon(Icons.check, size: 20, color: Colors.green),
              );
            }
          },
        );
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } catch (e) {
        if (mounted) {
          showCustomToastWithIcon(
            'Ошибка входа: ${e.toString()}',
            accentColor: Colors.red,
            fontSize: 14.0,
            icon: const Icon(Icons.error, size: 20, color: Colors.red),
          );
        }
      }
    }
  }

  void _register() async {
    if (_formKey.currentState?.validate() ?? false) {
      try {
        final auth = Provider.of<AuthProvider>(context, listen: false);
        await auth.register(
          _emailController.text.trim(),
          _passwordController.text.trim(),
          _emailController.text.split('@')[0],
        );
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } catch (e) {
        if (mounted) {
          showCustomToastWithIcon(
            'Ошибка регистрации: ${e.toString()}',
            accentColor: Colors.red,
            fontSize: 14.0,
            icon: const Icon(Icons.error, size: 20, color: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Вход'),
            const SizedBox(width: 10),
            const ServerStatusIndicator(),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Настройки сервера',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                  errorText: _emailHasError ? 'Пожалуйста, введите корректный email' : null,
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Пожалуйста, введите email';
                  }
                  if (!value.contains('@')) {
                    return 'Пожалуйста, введите корректный email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Пароль',
                  border: OutlineInputBorder(),
                  errorText: _passwordHasError ? 'Пожалуйста, введите пароль' : null,
                ),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Пожалуйста, введите пароль';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              Consumer<AuthProvider>(
                builder: (context, auth, _) {
                  return ElevatedButton(
                    onPressed: auth.isLoading ? null : _login,
                    child: auth.isLoading
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 8),
                              Text(
                                auth.isRestoringBackup 
                                    ? 'Восстановление данных...' 
                                    : 'Вход...',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          )
                        : const Text('Войти'),
                  );
                },
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  final auth = Provider.of<AuthProvider>(context, listen: false);
                  auth.enableGuestMode();
                  // Обеспечиваем правильное обновление UI
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    // Consumer в main.dart автоматически переключится на MainScreen
                    // когда auth.isAuthenticated станет true
                  });
                },
                child: const Text('Продолжить в гостевом режиме'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const RegisterScreen()),
                  );
                },
                child: const Text('Нет аккаунта? Зарегистрироваться'),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 