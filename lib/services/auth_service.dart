import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';

class AuthService {
  static const String baseUrl = 'http://127.0.0.1:5294/api/auth';
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

  Future<void> loadSavedData() async {
    try {
      final prefs = await _prefs;
      _token = prefs.getString('auth_token');
      final userJson = prefs.getString('user_data');
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
      if (_token != null) {
        await prefs.setString('auth_token', _token!);
      } else {
        await prefs.remove('auth_token');
      }
      
      if (_currentUser != null) {
        await prefs.setString('user_data', json.encode(_currentUser!.toJson()));
      } else {
        await prefs.remove('user_data');
      }
      
      _userController.add(_currentUser);
    } catch (e) {
      print('Error saving data: $e');
    }
  }

  Future<UserModel> register(String email, String password, String displayName) async {
    try {
      print('Attempting to register with URL: $baseUrl/register');
      
      final response = await http.post(
        Uri.parse('$baseUrl/register'),
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

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _token = data['token'];
        _currentUser = UserModel.fromJson(data['user']);
        await _saveData();
        return _currentUser!;
      } else {
        final error = json.decode(response.body);
        throw Exception(error['message'] ?? 'Failed to register');
      }
    } catch (e) {
      print('Registration error: $e');
      throw Exception('Connection error: $e');
    }
  }

  Future<UserModel> login(String email, String password) async {
    try {
      print('Attempting to login with URL: $baseUrl/login');
      
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
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
        return _currentUser!;
      } else {
        final error = json.decode(response.body);
        throw Exception(error['message'] ?? 'Failed to login');
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
      final response = await http.put(
        Uri.parse('$baseUrl/profile'),
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
        return _currentUser!;
      } else {
        final error = json.decode(response.body);
        throw Exception(error['message'] ?? 'Failed to update profile');
      }
    } catch (e) {
      throw Exception('Connection error: $e');
    }
  }

  void dispose() {
    _userController.close();
  }
} 