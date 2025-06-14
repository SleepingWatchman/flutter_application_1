import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/toast_utils.dart';
import 'login_screen.dart';
import '../../widgets/server_status_indicator.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  
  // Добавляем переменные для отслеживания состояния полей
  bool _displayNameHasError = false;
  bool _emailHasError = false;
  bool _passwordHasError = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    // Сбрасываем состояния ошибок
    setState(() {
      _displayNameHasError = false;
      _emailHasError = false;
      _passwordHasError = false;
    });
    
    // Проверяем поля вручную для подсветки ошибок
    bool hasErrors = false;
    
    if (_displayNameController.text.trim().isEmpty) {
      setState(() {
        _displayNameHasError = true;
      });
      hasErrors = true;
    }
    
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
    } else if (_passwordController.text.length < 6) {
      setState(() {
        _passwordHasError = true;
      });
      hasErrors = true;
    }
    
    if (hasErrors) {
      return; // Не продолжаем, если есть ошибки
    }
    
    if (_formKey.currentState!.validate()) {
      try {
        await context.read<AuthProvider>().register(
              _emailController.text.trim(),
              _passwordController.text,
              _displayNameController.text.trim(),
            );
        
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
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
            const Text('Регистрация'),
            const SizedBox(width: 10),
            const ServerStatusIndicator(),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextFormField(
                controller: _displayNameController,
                decoration: InputDecoration(
                  labelText: 'Имя',
                  border: OutlineInputBorder(),
                  errorText: _displayNameHasError ? 'Пожалуйста, введите имя' : null,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Пожалуйста, введите имя';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
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
                  errorText: _passwordHasError ? 'Пароль должен быть не менее 6 символов' : null,
                ),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Пожалуйста, введите пароль';
                  }
                  if (value.length < 6) {
                    return 'Пароль должен быть не менее 6 символов';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              Consumer<AuthProvider>(
                builder: (context, auth, _) {
                  return ElevatedButton(
                    onPressed: auth.isLoading ? null : _register,
                    child: auth.isLoading
                        ? const CircularProgressIndicator()
                        : const Text('Зарегистрироваться'),
                  );
                },
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
                child: const Text('Уже есть аккаунт? Войти'),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 