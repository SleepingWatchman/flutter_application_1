import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/auth_provider.dart';
import '../../services/file_service.dart';
import '../../utils/toast_utils.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({Key? key}) : super(key: key);

  @override
  _EditProfileScreenState createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _fileService = FileService();
  File? _imageFile;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    if (user != null) {
      _displayNameController.text = user.displayName ?? '';
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });
    }
  }

  Future<String?> _uploadImage() async {
    if (_imageFile == null) return null;

    try {
      final auth = context.read<AuthProvider>();
      final token = auth.token;
      if (token == null) {
        throw Exception('Не авторизован');
      }

      final url = await _fileService.uploadFile(_imageFile!, token);
      print('Uploaded image URL: $url');
      return url;
    } catch (e) {
      print('Error uploading image: $e');
      rethrow; // Пробрасываем ошибку выше для обработки в _updateProfile
    }
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      String? photoURL;
      if (_imageFile != null) {
        try {
          photoURL = await _uploadImage();
        } catch (e) {
          if (mounted) {
            showCustomToastWithIcon(
              'Ошибка загрузки изображения: $e',
              accentColor: Colors.red,
              fontSize: 14.0,
              icon: const Icon(Icons.error, size: 20, color: Colors.red),
            );
          }
          return;
        }
      }

      final auth = context.read<AuthProvider>();
      await auth.updateProfile(
        displayName: _displayNameController.text.trim(),
        photoURL: photoURL,
      );

      if (mounted) {
        Navigator.of(context).pop();
        showCustomToastWithIcon(
          'Профиль успешно обновлен',
          accentColor: Colors.green,
          fontSize: 14.0,
          icon: const Icon(Icons.check, size: 20, color: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        showCustomToastWithIcon(
          'Ошибка обновления профиля: $e',
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
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Редактировать профиль'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              GestureDetector(
                onTap: _pickImage,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundImage: _imageFile != null
                          ? FileImage(_imageFile!)
                          : (user?.photoURL != null
                              ? NetworkImage('${user!.photoURL!}?t=${DateTime.now().millisecondsSinceEpoch}')
                              : null) as ImageProvider?,
                      child: (_imageFile == null && user?.photoURL == null)
                          ? const Icon(Icons.person, size: 50)
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _displayNameController,
                decoration: const InputDecoration(
                  labelText: 'Имя пользователя',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Пожалуйста, введите имя пользователя';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _updateProfile,
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text('Сохранить'),
              ),
              const SizedBox(height: 16),
              Consumer<AuthProvider>(
                builder: (context, auth, _) {
                  return TextButton(
                    onPressed: _isLoading || auth.isCreatingBackupOnSignOut
                        ? null
                        : () {
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
                    child: auth.isCreatingBackupOnSignOut
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text('Создание бэкапа...'),
                            ],
                          )
                        : const Text('Выйти из аккаунта'),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
} 