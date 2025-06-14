import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class ProfileImageCacheService {
  static final ProfileImageCacheService _instance = ProfileImageCacheService._internal();
  factory ProfileImageCacheService() => _instance;
  ProfileImageCacheService._internal();

  static const String _cacheDirName = 'profile_images';
  static const int _maxCacheSize = 50 * 1024 * 1024; // 50 MB
  static const Duration _cacheExpiration = Duration(days: 30);

  Directory? _cacheDir;
  final Map<String, DateTime> _cacheTimestamps = {};

  /// Инициализация кэша
  Future<void> initialize() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _cacheDir = Directory('${appDir.path}/$_cacheDirName');
      
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }
      
      // Загружаем временные метки кэша
      await _loadCacheTimestamps();
      
      // Очищаем устаревшие файлы
      await _cleanupExpiredCache();
      
      print('📸 ProfileImageCacheService инициализирован');
    } catch (e) {
      print('❌ Ошибка инициализации ProfileImageCacheService: $e');
    }
  }

  /// Получение кэшированного изображения
  Widget getCachedProfileImage({
    required String? photoURL,
    required double radius,
    Widget? placeholder,
    Widget? errorWidget,
    BoxFit fit = BoxFit.cover,
  }) {
    if (photoURL == null || photoURL.isEmpty) {
      return CircleAvatar(
        radius: radius,
        child: placeholder ?? const Icon(Icons.person),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundImage: CachedNetworkImageProvider(
        photoURL,
        cacheManager: _getCacheManager(),
      ),
      child: photoURL.isEmpty
          ? (placeholder ?? const Icon(Icons.person))
          : null,
    );
  }

  /// Альтернативный виджет с полным контролем над отображением
  Widget getCachedProfileImageWidget({
    required String? photoURL,
    required double radius,
    Widget? placeholder,
    Widget? errorWidget,
    BoxFit fit = BoxFit.cover,
  }) {
    if (photoURL == null || photoURL.isEmpty) {
      return CircleAvatar(
        radius: radius,
        child: placeholder ?? const Icon(Icons.person),
      );
    }

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: photoURL,
        width: radius * 2,
        height: radius * 2,
        fit: fit,
        cacheManager: _getCacheManager(),
        placeholder: (context, url) => CircleAvatar(
          radius: radius,
          child: placeholder ?? const Icon(Icons.person),
        ),
        errorWidget: (context, url, error) => CircleAvatar(
          radius: radius,
          child: errorWidget ?? const Icon(Icons.person),
        ),
      ),
    );
  }

  /// Предварительная загрузка изображения в кэш
  Future<void> preloadImage(String photoURL) async {
    try {
      final cacheManager = _getCacheManager();
      await cacheManager.downloadFile(photoURL);
      
      // Обновляем временную метку
      final fileName = _getFileName(photoURL);
      _cacheTimestamps[fileName] = DateTime.now();
      await _saveCacheTimestamps();
      
      print('📸 Изображение профиля предзагружено: $photoURL');
    } catch (e) {
      print('❌ Ошибка предзагрузки изображения: $e');
    }
  }

  /// Очистка кэша для конкретного URL
  Future<void> clearImageCache(String photoURL) async {
    try {
      final cacheManager = _getCacheManager();
      await cacheManager.removeFile(photoURL);
      
      final fileName = _getFileName(photoURL);
      _cacheTimestamps.remove(fileName);
      await _saveCacheTimestamps();
      
      print('📸 Кэш изображения очищен: $photoURL');
    } catch (e) {
      print('❌ Ошибка очистки кэша изображения: $e');
    }
  }

  /// Полная очистка кэша
  Future<void> clearAllCache() async {
    try {
      if (_cacheDir != null && await _cacheDir!.exists()) {
        await _cacheDir!.delete(recursive: true);
        await _cacheDir!.create(recursive: true);
      }
      
      _cacheTimestamps.clear();
      await _saveCacheTimestamps();
      
      // Очищаем кэш Flutter
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      
      print('📸 Весь кэш изображений профиля очищен');
    } catch (e) {
      print('❌ Ошибка очистки кэша: $e');
    }
  }

  /// Получение размера кэша
  Future<int> getCacheSize() async {
    try {
      if (_cacheDir == null || !await _cacheDir!.exists()) {
        return 0;
      }

      int totalSize = 0;
      await for (final entity in _cacheDir!.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      
      return totalSize;
    } catch (e) {
      print('❌ Ошибка получения размера кэша: $e');
      return 0;
    }
  }

  /// Получение кастомного CacheManager
  CacheManager _getCacheManager() {
    return DefaultCacheManager();
  }

  /// Генерация имени файла из URL
  String _getFileName(String url) {
    final bytes = utf8.encode(url);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Загрузка временных меток кэша
  Future<void> _loadCacheTimestamps() async {
    try {
      if (_cacheDir == null) return;
      
      final timestampsFile = File('${_cacheDir!.path}/timestamps.json');
      if (await timestampsFile.exists()) {
        final content = await timestampsFile.readAsString();
        final Map<String, dynamic> data = json.decode(content);
        
        _cacheTimestamps.clear();
        data.forEach((key, value) {
          _cacheTimestamps[key] = DateTime.parse(value);
        });
      }
    } catch (e) {
      print('❌ Ошибка загрузки временных меток кэша: $e');
    }
  }

  /// Сохранение временных меток кэша
  Future<void> _saveCacheTimestamps() async {
    try {
      if (_cacheDir == null) return;
      
      final timestampsFile = File('${_cacheDir!.path}/timestamps.json');
      final Map<String, String> data = {};
      
      _cacheTimestamps.forEach((key, value) {
        data[key] = value.toIso8601String();
      });
      
      await timestampsFile.writeAsString(json.encode(data));
    } catch (e) {
      print('❌ Ошибка сохранения временных меток кэша: $e');
    }
  }

  /// Очистка устаревших файлов кэша
  Future<void> _cleanupExpiredCache() async {
    try {
      if (_cacheDir == null || !await _cacheDir!.exists()) return;
      
      final now = DateTime.now();
      final expiredFiles = <String>[];
      
      _cacheTimestamps.forEach((fileName, timestamp) {
        if (now.difference(timestamp) > _cacheExpiration) {
          expiredFiles.add(fileName);
        }
      });
      
      for (final fileName in expiredFiles) {
        final file = File('${_cacheDir!.path}/$fileName');
        if (await file.exists()) {
          await file.delete();
        }
        _cacheTimestamps.remove(fileName);
      }
      
      if (expiredFiles.isNotEmpty) {
        await _saveCacheTimestamps();
        print('📸 Удалено ${expiredFiles.length} устаревших файлов кэша');
      }
      
      // Проверяем размер кэша
      final cacheSize = await getCacheSize();
      if (cacheSize > _maxCacheSize) {
        await _cleanupOldestFiles();
      }
    } catch (e) {
      print('❌ Ошибка очистки устаревшего кэша: $e');
    }
  }

  /// Очистка старых файлов при превышении лимита
  Future<void> _cleanupOldestFiles() async {
    try {
      if (_cacheDir == null) return;
      
      // Сортируем файлы по времени последнего доступа
      final sortedFiles = _cacheTimestamps.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      
      int currentSize = await getCacheSize();
      int deletedCount = 0;
      
      for (final entry in sortedFiles) {
        if (currentSize <= _maxCacheSize) break;
        
        final file = File('${_cacheDir!.path}/${entry.key}');
        if (await file.exists()) {
          final fileSize = await file.length();
          await file.delete();
          currentSize -= fileSize;
          _cacheTimestamps.remove(entry.key);
          deletedCount++;
        }
      }
      
      if (deletedCount > 0) {
        await _saveCacheTimestamps();
        print('📸 Удалено $deletedCount старых файлов для освобождения места');
      }
    } catch (e) {
      print('❌ Ошибка очистки старых файлов: $e');
    }
  }
} 