import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import 'server_config_service.dart';
import 'profile_image_cache_service.dart';

class AuthService {
  String? _token;
  UserModel? _currentUser;
  late Future<SharedPreferences> _prefs;
  final _userController = StreamController<UserModel?>.broadcast();

  UserModel? get currentUser => _currentUser;
  String? get token => _token;
  Stream<UserModel?> get userStream => _userController.stream;

  AuthService() {
    _prefs = SharedPreferences.getInstance();
    loadSavedData();
  }

  String? getCurrentUserId() {
    if (_currentUser != null) {
      return _currentUser!.id;
    }
    
    if (_token != null) {
      try {
        // Декодируем JWT токен
        final parts = _token!.split('.');
        if (parts.length != 3) return null;
        
        // Декодируем payload часть токена
        final payload = json.decode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))
        );
        
        // Получаем ID пользователя из claims
        return payload['nameid'] as String?;
      } catch (e) {
        print('Ошибка при получении ID пользователя из токена: $e');
        return null;
      }
    }
    
    return null;
  }

  bool isTokenExpired() {
    if (_token == null) return true;
    try {
      final parts = _token!.split('.');
      if (parts.length != 3) return true;
      final payload = json.decode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload['exp'] == null) return true;
      final exp = payload['exp'] is int
          ? payload['exp']
          : int.tryParse(payload['exp'].toString());
      if (exp == null) return true;
      final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      return DateTime.now().isAfter(expiry);
    } catch (e) {
      print('Ошибка при проверке срока действия токена: $e');
      return true;
    }
  }

  Future<void> loadSavedData() async {
    try {
      final prefs = await _prefs;
      _token = prefs.getString('auth_token');
      final userJson = prefs.getString('user_data');
      if (_token != null && isTokenExpired()) {
        print('Токен истёк, выполняется автоматический выход');
        await signOut();
        return;
      }
      if (userJson != null) {
        _currentUser = UserModel.fromJson(json.decode(userJson));
      }
    } catch (e) {
      print('Error loading saved data: $e');
    }
  }

  Future<void> _saveData() async {
    try {
      final prefs = await _prefs;
      print('Сохранение данных авторизации');
      print('Токен: $_token');
      
      if (_token != null) {
        await prefs.setString('auth_token', _token!);
        print('Токен успешно сохранен');
      } else {
        await prefs.remove('auth_token');
        print('Токен удален');
      }
      
      if (_currentUser != null) {
        await prefs.setString('user_data', json.encode(_currentUser!.toJson()));
        print('Данные пользователя сохранены');
      } else {
        await prefs.remove('user_data');
        print('Данные пользователя удалены');
      }
      
      _userController.add(_currentUser);
    } catch (e) {
      print('Ошибка сохранения данных: $e');
      throw Exception('Ошибка сохранения данных авторизации: $e');
    }
  }

  Future<UserModel> register(String email, String password, String displayName) async {
    try {
      final dynamicBaseUrl = await ServerConfigService.getBaseUrl();
      print('Attempting to register with URL: ' + dynamicBaseUrl + '/api/auth/register');
      
      final response = await http.post(
        Uri.parse(dynamicBaseUrl + '/api/auth/register'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode({
          'email': email,
          'password': password,
          'displayName': displayName,
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Connection timeout');
        },
      );

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        _token = data['token'];
        _currentUser = UserModel.fromJson(data['user']);
        await _saveData();
        return _currentUser!;
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? error['message'] ?? 'Failed to register');
      }
    } catch (e) {
      print('Registration error: $e');
      throw Exception('Connection error: $e');
    }
  }

  Future<UserModel> login(String email, String password) async {
    try {
      final dynamicBaseUrl = await ServerConfigService.getBaseUrl();
      print('Attempting to login with URL: ' + dynamicBaseUrl + '/api/auth/login');
      
      final response = await http.post(
        Uri.parse(dynamicBaseUrl + '/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'password': password,
        }),
      );

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _token = data['token'];
        _currentUser = UserModel.fromJson(data['user']);
        await _saveData();
        
        // Предварительно загружаем фото профиля в кэш
        if (_currentUser?.photoURL != null && _currentUser!.photoURL!.isNotEmpty) {
          try {
            await ProfileImageCacheService().preloadImage(_currentUser!.photoURL!);
          } catch (e) {
            print('Ошибка предзагрузки фото профиля: $e');
          }
        }
        
        return _currentUser!;
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? error['message'] ?? 'Failed to login');
      }
    } catch (e) {
      print('Login error: $e');
      throw Exception('Connection error: $e');
    }
  }

  Future<void> signOut() async {
    _token = null;
    _currentUser = null;
    await _saveData();
  }

  Future<UserModel> updateProfile({String? displayName, String? photoURL}) async {
    if (_token == null) throw Exception('Not authenticated');

    try {
      final dynamicBaseUrl = await ServerConfigService.getBaseUrl();
      final response = await http.put(
        Uri.parse(dynamicBaseUrl + '/api/auth/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: json.encode({
          'displayName': displayName,
          'photoUrl': photoURL,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _currentUser = UserModel.fromJson(data);
        await _saveData();
        
        // Предварительно загружаем новое фото профиля в кэш
        if (photoURL != null && photoURL.isNotEmpty) {
          try {
            await ProfileImageCacheService().preloadImage(photoURL);
          } catch (e) {
            print('Ошибка предзагрузки фото профиля: $e');
          }
        }
        
        return _currentUser!;
      } else {
        final error = json.decode(response.body);
        throw Exception(error['message'] ?? 'Failed to update profile');
      }
    } catch (e) {
      throw Exception('Connection error: $e');
    }
  }

  Future<String?> getToken() async {
    if (_token == null) {
      await loadSavedData();
    }
    if (_token != null && isTokenExpired()) {
      await signOut();
      return null;
    }
    return _token;
  }

  void dispose() {
    _userController.close();
  }

  Future<Uri> _getAuthUri(String path) async {
    final dynamicBaseUrl = await ServerConfigService.getBaseUrl();
    return Uri.parse(dynamicBaseUrl + '/api/auth$path');
  }
} 