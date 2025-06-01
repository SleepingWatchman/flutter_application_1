import 'dart:io';
import 'dart:convert';
import 'dart:math';

/// Утилита для анализа результатов тестирования и покрытия кода
class TestAnalyzer {
  static const String resetColor = '\x1B[0m';
  static const String redColor = '\x1B[31m';
  static const String greenColor = '\x1B[32m';
  static const String yellowColor = '\x1B[33m';
  static const String blueColor = '\x1B[34m';
  static const String cyanColor = '\x1B[36m';
  static const String whiteColor = '\x1B[37m';
  static const String boldColor = '\x1B[1m';

  /// Основной метод анализа
  static Future<void> analyze() async {
    print('${cyanColor}${boldColor}🔍 Анализ результатов тестирования Flutter$resetColor\n');

    try {
      // Анализ результатов тестов
      await _analyzeTestResults();
      
      // Анализ покрытия кода
      await _analyzeCoverage();
      
      // Генерация рекомендаций
      _generateRecommendations();
      
    } catch (e) {
      print('${redColor}❌ Ошибка анализа: $e$resetColor');
      exit(1);
    }
  }

  /// Анализ результатов тестов из JSON файла
  static Future<void> _analyzeTestResults() async {
    final testResultsFile = File('test_results.json');
    if (!testResultsFile.existsSync()) {
      print('${yellowColor}⚠️ Файл test_results.json не найден. Запустите тесты сначала.$resetColor');
      return;
    }

    print('${boldColor}📊 Анализ результатов тестов:$resetColor');

    final content = await testResultsFile.readAsString();
    final lines = content.split('\n').where((line) => line.trim().isNotEmpty);

    final List<TestResult> tests = [];
    final Map<String, int> suiteStats = {};

    for (final line in lines) {
      try {
        final data = jsonDecode(line);
        if (data['type'] == 'testDone') {
          final testResult = TestResult.fromJson(data);
          tests.add(testResult);
          
          // Группировка по test suite
          final suite = testResult.suiteName ?? 'Unknown';
          suiteStats[suite] = (suiteStats[suite] ?? 0) + 1;
        }
      } catch (e) {
        // Игнорируем некорректные JSON строки
      }
    }

    if (tests.isEmpty) {
      print('${yellowColor}⚠️ Тесты не найдены в файле результатов$resetColor');
      return;
    }

    // Статистика по результатам
    final passed = tests.where((t) => t.result == 'success').length;
    final failed = tests.where((t) => t.result == 'failure' || t.result == 'error').length;
    final skipped = tests.where((t) => t.result == 'skip').length;
    final total = tests.length;

    final successRate = total > 0 ? (passed / total * 100).toDouble() : 0.0;

    print('  ${whiteColor}Всего тестов: $total$resetColor');
    print('  ${greenColor}✅ Прошли: $passed$resetColor');
    print('  ${redColor}❌ Не прошли: $failed$resetColor');
    print('  ${yellowColor}⏭️ Пропущено: $skipped$resetColor');
    print('  ${_getColorForPercentage(successRate)}📈 Успешность: ${successRate.toStringAsFixed(1)}%$resetColor');

    if (failed > 0) {
      print('\n${redColor}${boldColor}❌ Неудачные тесты:$resetColor');
      tests.where((t) => t.result == 'failure' || t.result == 'error').forEach((test) {
        print('  ${redColor}✗ ${test.name}$resetColor');
        if (test.error?.isNotEmpty == true) {
          print('    ${redColor}Ошибка: ${test.error}$resetColor');
        }
      });
    }

    // Статистика по test suites
    if (suiteStats.isNotEmpty) {
      print('\n${boldColor}📁 Статистика по файлам тестов:$resetColor');
      suiteStats.entries.forEach((entry) {
        print('  ${cyanColor}${entry.key}: ${entry.value} тестов$resetColor');
      });
    }

    // Самые медленные тесты
    final slowTests = tests
        .where((t) => t.time != null && t.time! > 100)
        .toList()
      ..sort((a, b) => (b.time ?? 0).compareTo(a.time ?? 0));

    if (slowTests.isNotEmpty) {
      print('\n${yellowColor}${boldColor}🐌 Медленные тесты (>100ms):$resetColor');
      slowTests.take(5).forEach((test) {
        print('  ${yellowColor}⏱️ ${test.name}: ${test.time}ms$resetColor');
      });
    }
  }

  /// Анализ покрытия кода
  static Future<void> _analyzeCoverage() async {
    final coverageFile = File('coverage/lcov.info');
    if (!coverageFile.existsSync()) {
      print('\n${yellowColor}⚠️ Файл покрытия не найден. Запустите тесты с --coverage$resetColor');
      return;
    }

    print('\n${boldColor}📊 Анализ покрытия кода:$resetColor');

    final content = await coverageFile.readAsString();
    final records = content.split('end_of_record');
    
    final List<FileCoverage> files = [];
    
    for (final record in records) {
      if (record.trim().isEmpty) continue;
      
      final lines = record.split('\n');
      String? sourceFile;
      int? linesFound;
      int? linesHit;
      
      for (final line in lines) {
        if (line.startsWith('SF:')) {
          sourceFile = line.substring(3);
        } else if (line.startsWith('LF:')) {
          linesFound = int.tryParse(line.substring(3));
        } else if (line.startsWith('LH:')) {
          linesHit = int.tryParse(line.substring(3));
        }
      }
      
      if (sourceFile != null && linesFound != null && linesHit != null) {
        // Фильтруем только lib/ файлы
        if (sourceFile.contains('/lib/')) {
          final relativePath = sourceFile.split('/lib/').last;
          final coverage = linesFound > 0 ? (linesHit / linesFound * 100).toDouble() : 0.0;
          
          files.add(FileCoverage(
            path: 'lib/$relativePath',
            linesTotal: linesFound,
            linesHit: linesHit,
            coverage: coverage,
          ));
        }
      }
    }

    if (files.isEmpty) {
      print('  ${yellowColor}⚠️ Данные покрытия не найдены$resetColor');
      return;
    }

    // Общая статистика
    final totalLines = files.fold<int>(0, (sum, file) => sum + file.linesTotal);
    final totalHit = files.fold<int>(0, (sum, file) => sum + file.linesHit);
    final overallCoverage = totalLines > 0 ? (totalHit / totalLines * 100).toDouble() : 0.0;

    print('  ${_getColorForPercentage(overallCoverage)}�� Общее покрытие: ${overallCoverage.toStringAsFixed(2)}%$resetColor');
    print('  ${whiteColor}📝 Всего строк: $totalLines$resetColor');
    print('  ${greenColor}✅ Покрыто строк: $totalHit$resetColor');

    // Файлы с низким покрытием
    final lowCoverageFiles = files
        .where((f) => f.coverage < 70 && f.linesTotal > 5)
        .toList()
      ..sort((a, b) => a.coverage.compareTo(b.coverage));

    if (lowCoverageFiles.isNotEmpty) {
      print('\n${redColor}${boldColor}⚠️ Файлы с низким покрытием (<70%):$resetColor');
      lowCoverageFiles.take(10).forEach((file) {
        print('  ${redColor}${file.coverage.toStringAsFixed(1)}% - ${file.path} (${file.linesHit}/${file.linesTotal})$resetColor');
      });
    }

    // Файлы с отличным покрытием
    final highCoverageFiles = files
        .where((f) => f.coverage >= 90)
        .toList()
      ..sort((a, b) => b.coverage.compareTo(a.coverage));

    if (highCoverageFiles.isNotEmpty) {
      print('\n${greenColor}${boldColor}🏆 Файлы с отличным покрытием (≥90%):$resetColor');
      highCoverageFiles.take(5).forEach((file) {
        print('  ${greenColor}${file.coverage.toStringAsFixed(1)}% - ${file.path} (${file.linesHit}/${file.linesTotal})$resetColor');
      });
    }

    // Анализ по директориям
    final directoryStats = <String, DirectoryStats>{};
    for (final file in files) {
      final parts = file.path.split('/');
      if (parts.length > 1) {
        final dir = parts.take(2).join('/'); // lib/providers, lib/models, etc.
        if (!directoryStats.containsKey(dir)) {
          directoryStats[dir] = DirectoryStats(directory: dir);
        }
        directoryStats[dir]!.addFile(file);
      }
    }

    if (directoryStats.isNotEmpty) {
      print('\n${boldColor}📁 Покрытие по директориям:$resetColor');
      directoryStats.entries
          .map((e) => e.value)
          .toList()
        ..sort((a, b) => a.coverage.compareTo(b.coverage))
        ..forEach((stat) {
          print('  ${_getColorForPercentage(stat.coverage)}${stat.coverage.toStringAsFixed(1)}% - ${stat.directory} (${stat.filesCount} файлов)$resetColor');
        });
    }
  }

  /// Генерация рекомендаций
  static void _generateRecommendations() {
    print('\n${cyanColor}${boldColor}💡 Рекомендации:$resetColor');
    print('  ${greenColor}• Поддерживайте покрытие кода выше 80%$resetColor');
    print('  ${greenColor}• Исправляйте неудачные тесты в первую очередь$resetColor');
    print('  ${greenColor}• Добавляйте тесты для новых функций$resetColor');
    print('  ${greenColor}• Оптимизируйте медленные тесты$resetColor');
    print('  ${greenColor}• Регулярно анализируйте покрытие кода$resetColor');
  }

  static String _getColorForPercentage(double percentage) {
    if (percentage >= 80) return greenColor;
    if (percentage >= 60) return yellowColor;
    return redColor;
  }
}

/// Модель результата теста
class TestResult {
  final String name;
  final String result;
  final int? time;
  final String? error;
  final String? suiteName;

  TestResult({
    required this.name,
    required this.result,
    this.time,
    this.error,
    this.suiteName,
  });

  factory TestResult.fromJson(Map<String, dynamic> json) {
    return TestResult(
      name: json['test']?['name'] ?? 'Unknown Test',
      result: json['result'] ?? 'unknown',
      time: json['time'],
      error: json['error'],
      suiteName: json['test']?['suite']?['platform'],
    );
  }
}

/// Модель покрытия файла
class FileCoverage {
  final String path;
  final int linesTotal;
  final int linesHit;
  final double coverage;

  FileCoverage({
    required this.path,
    required this.linesTotal,
    required this.linesHit,
    required this.coverage,
  });
}

/// Статистика покрытия директории
class DirectoryStats {
  final String directory;
  int _totalLines = 0;
  int _hitLines = 0;
  int _filesCount = 0;

  DirectoryStats({required this.directory});

  void addFile(FileCoverage file) {
    _totalLines += file.linesTotal;
    _hitLines += file.linesHit;
    _filesCount++;
  }

  double get coverage => _totalLines > 0 ? (_hitLines / _totalLines * 100) : 0;
  int get filesCount => _filesCount;
}

/// Точка входа
void main() async {
  await TestAnalyzer.analyze();
} 