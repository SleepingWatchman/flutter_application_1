import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:flutter_application_1/providers/auth_provider.dart';

enum ServerStatus {
  online,
  offline,
  unknown,
}

class ServerHealthService {
  static final ServerHealthService _instance = ServerHealthService._internal();
  factory ServerHealthService() => _instance;
  ServerHealthService._internal();

  Timer? _healthCheckTimer;
  ServerStatus _currentStatus = ServerStatus.unknown;
  bool _isInitialized = false;
  String? _baseUrl;
  String? _token;
  
  // Колбеки для уведомления об изменении статуса
  final List<Function(ServerStatus)> _statusListeners = [];

  ServerStatus get currentStatus => _currentStatus;
  bool get isOnline => _currentStatus == ServerStatus.online;
  bool get isOffline => _currentStatus == ServerStatus.offline;

  /// Инициализация сервиса проверки здоровья сервера
  void initialize(BuildContext context) {
    if (_isInitialized) return;
    
    print('🏥 HEALTH: Инициализация сервиса проверки здоровья сервера');
    
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    // Используем базовый URL из сервиса аутентификации или стандартный
    _baseUrl = 'http://localhost:8080'; // Можно сделать настраиваемым
    _token = authProvider.token;
    _isInitialized = true;
    
    // Выполняем первоначальную проверку
    _performHealthCheck(context);
    
    // Запускаем периодические проверки каждые 5 минут
    _startPeriodicHealthChecks(context);
    
    print('🏥 HEALTH: Сервис инициализирован и запущен');
  }

  /// Добавить слушатель изменения статуса сервера
  void addStatusListener(Function(ServerStatus) listener) {
    _statusListeners.add(listener);
  }

  /// Удалить слушатель изменения статуса сервера
  void removeStatusListener(Function(ServerStatus) listener) {
    _statusListeners.remove(listener);
  }

  /// Уведомить всех слушателей об изменении статуса
  void _notifyStatusListeners(ServerStatus status) {
    for (final listener in _statusListeners) {
      try {
        listener(status);
      } catch (e) {
        print('🏥 HEALTH: Ошибка при уведомлении слушателя: $e');
      }
    }
  }

  /// Запуск периодических проверок состояния сервера
  void _startPeriodicHealthChecks(BuildContext context) {
    _healthCheckTimer?.cancel();
    
    _healthCheckTimer = Timer.periodic(
      const Duration(minutes: 5), 
      (_) => _performHealthCheck(context)
    );
    
    print('🏥 HEALTH: Запущены периодические проверки каждые 5 минут');
  }

  /// Выполнение проверки состояния сервера
  Future<void> _performHealthCheck(BuildContext context) async {
    if (_baseUrl == null) {
      print('🏥 HEALTH: Базовый URL не установлен, пропускаем проверку');
      return;
    }

    try {
      print('🏥 HEALTH: Выполнение проверки состояния сервера...');
      
      // Простая проверка доступности сервера через API
      final response = await http.get(
        Uri.parse('$_baseUrl/api/collaboration/databases'),
        headers: {
          'Content-Type': 'application/json',
          if (_token != null) 'Authorization': 'Bearer $_token',
        },
      ).timeout(const Duration(seconds: 10));

      final newStatus = (response.statusCode == 200 || response.statusCode == 401) 
          ? ServerStatus.online 
          : ServerStatus.offline;
      
      _updateServerStatus(newStatus);
      
    } catch (e) {
      print('🏥 HEALTH: Ошибка проверки сервера: $e');
      _updateServerStatus(ServerStatus.offline);
    }
  }

  /// Принудительная проверка состояния сервера
  Future<void> forceHealthCheck(BuildContext context) async {
    print('🏥 HEALTH: Принудительная проверка состояния сервера');
    await _performHealthCheck(context);
  }

  /// Обновление статуса сервера (без toast уведомлений)
  void _updateServerStatus(ServerStatus newStatus) {
    final previousStatus = _currentStatus;
    _currentStatus = newStatus;
    
    // Уведомляем слушателей об изменении статуса (обновляет индикатор в AppBar)
    _notifyStatusListeners(newStatus);
    
    print('🏥 HEALTH: Статус сервера обновлен: ${_getStatusText(newStatus)}');
  }

  /// Получение текстового описания статуса
  String _getStatusText(ServerStatus status) {
    switch (status) {
      case ServerStatus.online:
        return 'Онлайн';
      case ServerStatus.offline:
        return 'Офлайн';
      case ServerStatus.unknown:
        return 'Неизвестно';
    }
  }

  /// Получение иконки для статуса
  IconData getStatusIcon(ServerStatus status) {
    switch (status) {
      case ServerStatus.online:
        return Icons.cloud_done;
      case ServerStatus.offline:
        return Icons.cloud_off;
      case ServerStatus.unknown:
        return Icons.cloud_queue;
    }
  }

  /// Получение цвета для статуса
  Color getStatusColor(ServerStatus status) {
    switch (status) {
      case ServerStatus.online:
        return Colors.green;
      case ServerStatus.offline:
        return Colors.red;
      case ServerStatus.unknown:
        return Colors.orange;
    }
  }

  /// Обновление токена аутентификации
  void updateToken(String? newToken) {
    _token = newToken;
    print('🏥 HEALTH: Токен аутентификации обновлен');
  }

  /// Обновление базового URL сервера
  void updateBaseUrl(String? newBaseUrl) {
    _baseUrl = newBaseUrl;
    print('🏥 HEALTH: Базовый URL обновлен: $newBaseUrl');
  }

  /// Остановка сервиса
  void dispose() {
    print('🏥 HEALTH: Остановка сервиса проверки здоровья сервера');
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
    _statusListeners.clear();
    _isInitialized = false;
  }

  /// Перезапуск сервиса с новыми параметрами
  void restart(BuildContext context) {
    print('🏥 HEALTH: Перезапуск сервиса проверки здоровья сервера');
    dispose();
    initialize(context);
  }
} 