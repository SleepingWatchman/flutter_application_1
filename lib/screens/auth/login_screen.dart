import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:oktoast/oktoast.dart';
import '../../providers/auth_provider.dart';
import '../../utils/toast_utils.dart';
import 'register_screen.dart';

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

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _login() async {
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
        title: const Text('Вход'),
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
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
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
                decoration: const InputDecoration(
                  labelText: 'Пароль',
                  border: OutlineInputBorder(),
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