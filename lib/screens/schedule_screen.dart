import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import '../widgets/calendar_grid.dart';
import '../db/database_helper.dart';
import '../models/schedule_entry.dart';
import '../models/dynamic_field_entry.dart';
import '../utils/toast_utils.dart';
import '../providers/database_provider.dart';
import '../providers/enhanced_collaborative_provider.dart';
import '../widgets/tag_input_widget.dart';
import 'dart:math' as math;

/// Вспомогательный класс для работы с событиями и их временными диапазонами
class EventWithTime {
  final ScheduleEntry entry;
  final int startMinute;
  final int endMinute;
  
  EventWithTime({
    required this.entry,
    required this.startMinute,
    required this.endMinute,
  });
}

/// Экран расписания. Если день не выбран (_selectedDate == null), показывается календарная сетка.
/// Если выбран день, отображается детальный режим с интервалами и предпросмотром заметки.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({Key? key}) : super(key: key);

  @override
  _ScheduleScreenState createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> with WidgetsBindingObserver {
  DateTime? _selectedDate; // Если null – показываем календарь
  DateTime? _highlightedDate; // Дата, выбранная первым кликом
  DateTime _currentMonth = DateTime.now(); // Текущий отображаемый месяц
  List<ScheduleEntry> _scheduleEntries = [];
  int? _selectedIndex;
  bool _isActive = true;
  bool _isLoading = false; // ИСПРАВЛЕНИЕ: Флаг для предотвращения повторных загрузок
  bool _isDataLoaded = false; // ИСПРАВЛЕНИЕ: Флаг для отслеживания загрузки данных
  String? _lastLoadedDatabaseId; // ИСПРАВЛЕНИЕ: Отслеживание последней загруженной базы
  
  // ИСПРАВЛЕНИЕ: Сохраняем ссылки на провайдеры для безопасного dispose
  DatabaseProvider? _databaseProvider;
  EnhancedCollaborativeProvider? _enhancedCollaborativeProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Добавляем слушатель изменений для обновления интерфейса при переключении базы данных
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        // Подписываемся на изменения в DatabaseProvider
        final dbProvider = Provider.of<DatabaseProvider>(context, listen: false);
        dbProvider.addListener(_handleDatabaseChanges);
        
        // Подписываемся на изменения в EnhancedCollaborativeProvider
        final collabProvider = Provider.of<EnhancedCollaborativeProvider>(context, listen: false);
        collabProvider.addListener(_handleCollaborativeDatabaseChanges);
      } catch (e) {
        print('Ошибка при добавлении слушателей: $e');
      }
      
      // Загружаем данные расписания при запуске, если выбрана дата
      if (_selectedDate != null) {
        _loadSchedule();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // ИСПРАВЛЕНИЕ: Сохраняем ссылки на провайдеры для безопасного dispose
    _databaseProvider = Provider.of<DatabaseProvider>(context, listen: false);
    _enhancedCollaborativeProvider = Provider.of<EnhancedCollaborativeProvider>(context, listen: false);
    
    // Загружаем данные только если есть флаг обновления
    if (_databaseProvider!.needsUpdate && _selectedDate != null) {
      _forceReloadSchedule();
      _databaseProvider!.resetUpdateFlag();
    }
    
    // ИСПРАВЛЕНИЕ: Загружаем данные только если база изменилась
    if (_selectedDate != null) {
      _loadScheduleIfNeeded();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    
    // ИСПРАВЛЕНИЕ: Безопасное удаление слушателей
    try {
      if (_databaseProvider != null) {
        _databaseProvider!.removeListener(_handleDatabaseChanges);
      }
      
      if (_enhancedCollaborativeProvider != null) {
        _enhancedCollaborativeProvider!.removeListener(_handleCollaborativeDatabaseChanges);
      }
    } catch (e) {
      print('Ошибка при удалении слушателей: $e');
    }
    
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isActive) {
      setState(() {
        _isActive = true;
      });
      if (_selectedDate != null) {
        _loadSchedule();
      }
    } else if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      setState(() {
        _isActive = false;
      });
    }
  }

  // Вызывается при первом клике на день в календарной сетке
  void _onDateHighlighted(DateTime date) {
    setState(() {
      _highlightedDate = date;
    });
  }

  // Вызывается при выборе дня из календарной сетки - второй клик или нажатие кнопки
  void _onDateSelected(DateTime date) {
    setState(() {
      _selectedDate = date;
      _highlightedDate = null;
    });
    _loadSchedule();
  }

  // Возврат к календарю
  void _goBackToCalendar() {
    setState(() {
      _selectedDate = null;
      _highlightedDate = null;
      _scheduleEntries.clear();
      _selectedIndex = null;
    });
  }

  // Обработчик изменений базы данных
  void _handleDatabaseChanges() {
    if (mounted) {
      final databaseProvider = Provider.of<DatabaseProvider>(context, listen: false);
      final enhancedCollabProvider = Provider.of<EnhancedCollaborativeProvider>(context, listen: false);
      final currentDatabaseId = enhancedCollabProvider.isUsingSharedDatabase 
          ? enhancedCollabProvider.currentDatabaseId 
          : null;
      
      // ИСПРАВЛЕНИЕ: Проверяем как изменение базы, так и флаг обновления
      if ((_lastLoadedDatabaseId != currentDatabaseId || databaseProvider.needsUpdate) && _selectedDate != null) {
        // ЗАЩИТА ОТ ЦИКЛОВ: Сбрасываем флаг ПОСЛЕ начала обработки
        final wasUpdateNeeded = databaseProvider.needsUpdate;
        if (wasUpdateNeeded) {
          databaseProvider.resetUpdateFlag();
          print('🔄 ОБНОВЛЕНИЕ: Флаг needsUpdate сброшен для экрана расписания');
        }
        _forceReloadSchedule();
      }
    }
  }
  
  // Обработчик изменений совместной базы данных
  void _handleCollaborativeDatabaseChanges() {
    if (mounted) {
      final databaseProvider = Provider.of<DatabaseProvider>(context, listen: false);
      final enhancedCollabProvider = Provider.of<EnhancedCollaborativeProvider>(context, listen: false);
      final currentDatabaseId = enhancedCollabProvider.isUsingSharedDatabase 
          ? enhancedCollabProvider.currentDatabaseId 
          : null;
      
      // ИСПРАВЛЕНИЕ: Проверяем как изменение базы, так и флаг обновления
      if ((_lastLoadedDatabaseId != currentDatabaseId || databaseProvider.needsUpdate) && _selectedDate != null) {
        // ЗАЩИТА ОТ ЦИКЛОВ: Сбрасываем флаг ПОСЛЕ начала обработки
        final wasUpdateNeeded = databaseProvider.needsUpdate;
        if (wasUpdateNeeded) {
          databaseProvider.resetUpdateFlag();
          print('🤝 КОЛЛАБОРАЦИЯ: Флаг needsUpdate сброшен для экрана расписания');
        }
        _forceReloadSchedule();
      }
    }
  }

  // ИСПРАВЛЕНИЕ: Новый метод для условной загрузки данных
  void _loadScheduleIfNeeded() {
    if (_selectedDate == null) return;
    
    final collabProvider = Provider.of<EnhancedCollaborativeProvider>(context, listen: false);
    final currentDatabaseId = collabProvider.isUsingSharedDatabase 
        ? collabProvider.currentDatabaseId 
        : null;
    
    // Загружаем данные только если база изменилась или данные еще не загружены
    if (!_isDataLoaded || _lastLoadedDatabaseId != currentDatabaseId) {
      _loadSchedule();
    }
  }

  // ИСПРАВЛЕНИЕ: Метод для принудительной перезагрузки
  void _forceReloadSchedule() {
    _isDataLoaded = false;
    _lastLoadedDatabaseId = null;
    if (_selectedDate != null) {
      _loadSchedule();
    }
  }

  Future<void> _loadSchedule() async {
    if (_selectedDate == null) return;
    
    // ИСПРАВЛЕНИЕ: Защита от повторных загрузок
    if (_isLoading) {
      print('Загрузка расписания уже выполняется, пропускаем');
      return;
    }
    
    // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Проверяем блокировку операций с базой данных
    final databaseProvider = Provider.of<DatabaseProvider>(context, listen: false);
    if (databaseProvider.isBlocked) {
      print('⚠️ Загрузка расписания заблокирована во время переключения базы данных');
      return;
    }
    
    setState(() => _isLoading = true);
    
    String dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate!);
    
    try {
      // ИСПРАВЛЕНИЕ: Используем только EnhancedCollaborativeProvider
      final enhancedCollabProvider = Provider.of<EnhancedCollaborativeProvider>(context, listen: false);
      final currentDatabaseId = enhancedCollabProvider.isUsingSharedDatabase 
          ? enhancedCollabProvider.currentDatabaseId 
          : null;
      
      print('Загрузка расписания для базы: ${currentDatabaseId ?? "локальной"}');
      
      final entries = await DatabaseHelper().getScheduleEntries(currentDatabaseId);
      
      // Фильтруем записи, которые непосредственно для выбранной даты
      List<ScheduleEntry> directEntries = entries.where((entry) => entry.date == dateKey).toList();
      
      // Список для повторяющихся событий, которые должны быть показаны на выбранную дату
      List<ScheduleEntry> recurringEntries = [];
      
      // Проверяем повторяющиеся события
      for (var entry in entries) {
        // Пропускаем непосредственные записи для этой даты (уже включены выше)
        if (entry.date == dateKey) continue;
        
        // Пропускаем записи без повторения
        if (entry.recurrence.type == RecurrenceType.none) continue;
        
        // Проверяем, должно ли это повторяющееся событие отображаться в выбранный день
        if (_shouldShowRecurringEntry(entry, _selectedDate!)) {
          // Клонируем запись с датой выбранного дня
          ScheduleEntry clonedEntry = ScheduleEntry(
            id: entry.id,
            time: entry.time,
            date: dateKey,
            note: entry.note,
            dynamicFieldsJson: entry.dynamicFieldsJson,
            recurrence: entry.recurrence,
          );
          recurringEntries.add(clonedEntry);
        }
      }
      
      if (mounted) {
        setState(() {
          // Объединяем прямые записи и повторяющиеся
          _scheduleEntries = [...directEntries, ...recurringEntries];
          
          // Сортируем события по времени начала и окончания
          _scheduleEntries.sort((a, b) {
            final aTimes = a.time.split(' - ');
            final bTimes = b.time.split(' - ');
            
            if (aTimes.length < 2 || bTimes.length < 2) {
              // Обработка некорректного формата времени
              return 0;
            }
            
            final aStart = aTimes[0].split(':');
            final bStart = bTimes[0].split(':');
            
            if (aStart.length < 2 || bStart.length < 2) {
              // Обработка некорректного формата времени
              return 0;
            }
            
            try {
              final aStartMinutes = int.parse(aStart[0]) * 60 + int.parse(aStart[1]);
              final bStartMinutes = int.parse(bStart[0]) * 60 + int.parse(bStart[1]);
              
              if (aStartMinutes != bStartMinutes) {
                return aStartMinutes.compareTo(bStartMinutes);
              }
              
              final aEnd = aTimes[1].split(':');
              final bEnd = bTimes[1].split(':');
              
              if (aEnd.length < 2 || bEnd.length < 2) {
                // Обработка некорректного формата времени
                return 0;
              }
              
              final aEndMinutes = int.parse(aEnd[0]) * 60 + int.parse(aEnd[1]);
              final bEndMinutes = int.parse(bEnd[0]) * 60 + int.parse(bEnd[1]);
              
              return aEndMinutes.compareTo(bEndMinutes);
            } catch (e) {
              print('Ошибка при сортировке записей расписания: $e');
              return 0;
            }
          });
          _selectedIndex = null;
          
          // ИСПРАВЛЕНИЕ: Устанавливаем флаги успешной загрузки
          _isLoading = false;
          _isDataLoaded = true;
          _lastLoadedDatabaseId = currentDatabaseId;
        });
      }
    } catch (e) {
      print('Ошибка при загрузке расписания: $e');
      
      if (mounted) {
        setState(() => _isLoading = false);
        
        // Повторная попытка загрузки данных после небольшой задержки
        Future.delayed(Duration(milliseconds: 500), () {
          if (mounted) {
            _loadSchedule();
          }
        });
      }
    }
  }
  
  // Определяет, должно ли повторяющееся событие отображаться на указанную дату
  bool _shouldShowRecurringEntry(ScheduleEntry entry, DateTime targetDate) {
    // Если запись не является повторяющейся, возвращаем false
    if (entry.recurrence.type == RecurrenceType.none) return false;
    
    // Парсим дату начала события
    DateTime startDate = DateFormat('yyyy-MM-dd').parse(entry.date);
    
    // Проверяем, не превышает ли целевая дата дату окончания
    if (entry.recurrence.endDate != null && targetDate.isAfter(entry.recurrence.endDate!)) {
      return false;
    }
    
    // Интервал повторения
    int interval = entry.recurrence.interval ?? 1;
    
    switch (entry.recurrence.type) {
      case RecurrenceType.daily:
        // Для ежедневного повторения проверяем кратность дней
        int daysDifference = targetDate.difference(startDate).inDays;
        return daysDifference > 0 && daysDifference % interval == 0;
        
      case RecurrenceType.weekly:
        // Для еженедельного повторения проверяем, что день недели совпадает и прошло нужное количество недель
        if (targetDate.weekday != startDate.weekday) return false;
        int weeksDifference = targetDate.difference(startDate).inDays ~/ 7;
        return weeksDifference > 0 && weeksDifference % interval == 0;
        
      case RecurrenceType.monthly:
        // Для ежемесячного повторения проверяем день месяца
        if (targetDate.day != startDate.day) return false;
        
        // Вычисляем количество месяцев между датами
        int monthsDifference = (targetDate.year - startDate.year) * 12 + targetDate.month - startDate.month;
        return monthsDifference > 0 && monthsDifference % interval == 0;
        
      case RecurrenceType.yearly:
        // Для ежегодного повторения проверяем день и месяц
        if (targetDate.day != startDate.day || targetDate.month != startDate.month) return false;
        
        // Вычисляем количество лет между датами
        int yearsDifference = targetDate.year - startDate.year;
        return yearsDifference > 0 && yearsDifference % interval == 0;
        
      default:
        return false;
    }
  }

  bool _checkTimeOverlap(String newTime, {int? excludeIndex}) {
    final newTimes = newTime.split(' - ');
    final newStart = newTimes[0].split(':');
    final newEnd = newTimes[1].split(':');
    final newStartMinutes = int.parse(newStart[0]) * 60 + int.parse(newStart[1]);
    final newEndMinutes = int.parse(newEnd[0]) * 60 + int.parse(newEnd[1]);

    for (int i = 0; i < _scheduleEntries.length; i++) {
      if (excludeIndex != null && i == excludeIndex) continue;
      
      final entry = _scheduleEntries[i];
      final entryTimes = entry.time.split(' - ');
      final entryStart = entryTimes[0].split(':');
      final entryEnd = entryTimes[1].split(':');
      final entryStartMinutes = int.parse(entryStart[0]) * 60 + int.parse(entryStart[1]);
      final entryEndMinutes = int.parse(entryEnd[0]) * 60 + int.parse(entryEnd[1]);

      if ((newStartMinutes >= entryStartMinutes && newStartMinutes < entryEndMinutes) ||
          (newEndMinutes > entryStartMinutes && newEndMinutes <= entryEndMinutes) ||
          (newStartMinutes <= entryStartMinutes && newEndMinutes >= entryEndMinutes)) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _showTimeOverlapDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Предупреждение'),
        content: const Text('Выбранный временной интервал пересекается с существующим событием.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop('cancel');
            },
            child: const Text('Отменить и выбрать другое время'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop('continue');
            },
            child: const Text('Сохранить с текущим временем'),
          ),
        ],
      ),
    );
    return result == 'continue';
  }

  // Метод добавления нового интервала с предустановленной маской для поля времени.
  void _addScheduleEntry() {
    final TextEditingController timeController = TextEditingController();
    final TextEditingController shortNoteController = TextEditingController();
    final timeMaskFormatter = MaskTextInputFormatter(
      mask: '##:## - ##:##',
      filter: {'#': RegExp(r'[0-9]')},
    );
    List<DynamicFieldEntry> dynamicFields = [
      DynamicFieldEntry(key: 'Предмет', value: '')
    ];
    List<String> tags = []; // Добавляем список тегов
    String? timeError;

    // Параметры повторяемости
    Recurrence recurrence = Recurrence();
    final TextEditingController intervalController = TextEditingController(text: '1');
    final TextEditingController countController = TextEditingController();
    DateTime? selectedEndDate;

    // Получаем идентификатор текущей базы данных для правильного сохранения
    String? databaseId;
    try {
      final collabProvider = Provider.of<EnhancedCollaborativeProvider>(context, listen: false);
      if (collabProvider.isUsingSharedDatabase) {
        databaseId = collabProvider.currentDatabaseId;
      }
    } catch (e) {
      print('Ошибка при получении информации о совместной базе: $e');
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
            title: const Text('Добавить в расписание'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  // Поле времени
                    TextField(
                      controller: timeController,
                      inputFormatters: [timeMaskFormatter],
                      decoration: InputDecoration(
                      labelText: 'Время (ЧЧ:ММ - ЧЧ:ММ)',
                        errorText: timeError,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.schedule),
                        onPressed: () {
                          showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.now(),
                          ).then((startTime) {
                            if (startTime != null) {
                              showTimePicker(
                                context: context,
                                initialTime: TimeOfDay(
                                  hour: (startTime.hour + 1) % 24,
                                  minute: startTime.minute,
                        ),
                              ).then((endTime) {
                                if (endTime != null) {
                                  timeController.text = 
                                    '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')} - ${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';
                                }
                              });
                            }
                              });
                            },
                          ),
                    ),
                  ),
                  const SizedBox(height: 16),
                      
                  // Поле краткой заметки
                        TextField(
                    controller: shortNoteController,
                          decoration: const InputDecoration(
                      labelText: 'Краткая заметка',
                          ),
                    maxLines: 3,
                        ),
                  const SizedBox(height: 16),
                    
                    // Динамические поля
                  ...dynamicFields.asMap().entries.map((entry) {
                    int index = entry.key;
                    DynamicFieldEntry field = entry.value;
                        return Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: field.keyController,
                            decoration: const InputDecoration(labelText: 'Название поля'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: field.valueController,
                            decoration: const InputDecoration(labelText: 'Значение'),
                              ),
                            ),
                            IconButton(
                          icon: const Icon(Icons.delete),
                              onPressed: () {
                                setState(() {
                              dynamicFields.removeAt(index);
                                });
                              },
                            ),
                          ],
                        );
                      }).toList(),
                  
                  // Кнопка добавления нового поля
                  TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Добавить поле'),
                        onPressed: () {
                          setState(() {
                        dynamicFields.add(DynamicFieldEntry(key: '', value: ''));
                          });
                        },
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Виджет для работы с тегами
                  const Text('Теги:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TagInputWidget(
                    initialTags: tags,
                    onTagsChanged: (newTags) {
                      tags = newTags;
                    },
                    hintText: 'Добавить тег...',
                    maxTags: 10,
                  ),
                  
                  const SizedBox(height: 16),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('Отмена'),
                ),
                TextButton(
                  onPressed: () async {
                    if (timeController.text.isEmpty ||
                        !RegExp(r'^([0-9]{2}):([0-9]{2}) - ([0-9]{2}):([0-9]{2})$')
                            .hasMatch(timeController.text)) {
                      setState(() {
                        timeError = 'Введите время в формате чч:мм - чч:мм';
                      });
                      return;
                    }

                    // Дополнительная проверка корректности времени
                    String timeStr = timeController.text.trim();
                    List<String> timeParts = timeStr.split(' - ');
                    // Проверка формата уже была выше, но для полноты оставим частичную проверку
                    if (timeParts.length != 2) {
                      setState(() {
                        timeError = 'Неверный формат времени';
                      });
                      return;
                    }

                    // Проверка начального времени
                    List<String> startTimeParts = timeParts[0].split(':');
                    if (startTimeParts.length != 2) {
                      setState(() {
                        timeError = 'Неверный формат времени начала';
                      });
                      return;
                    }

                    int startHour = int.tryParse(startTimeParts[0]) ?? -1;
                    int startMinute = int.tryParse(startTimeParts[1]) ?? -1;
                    
                    if (startHour < 0 || startHour > 23 || startMinute < 0 || startMinute > 59) {
                      setState(() {
                        timeError = 'Время начала должно быть от 00:00 до 23:59';
                      });
                      return;
                    }

                    // Проверка конечного времени
                    List<String> endTimeParts = timeParts[1].split(':');
                    if (endTimeParts.length != 2) {
                      setState(() {
                        timeError = 'Неверный формат времени окончания';
                      });
                      return;
                    }

                    int endHour = int.tryParse(endTimeParts[0]) ?? -1;
                    int endMinute = int.tryParse(endTimeParts[1]) ?? -1;
                    
                    if (endHour < 0 || endHour > 23 || endMinute < 0 || endMinute > 59) {
                      setState(() {
                        timeError = 'Время окончания должно быть от 00:00 до 23:59';
                      });
                      return;
                    }

                    // Сравнение начального и конечного времени
                    final startTimeMinutes = startHour * 60 + startMinute;
                    final endTimeMinutes = endHour * 60 + endMinute;
                    
                    if (startTimeMinutes >= endTimeMinutes) {
                      setState(() {
                        timeError = 'Время начала должно быть раньше времени окончания';
                      });
                      return;
                    }
                    
                    // Сбрасываем ошибку, если все проверки пройдены
                    setState(() {
                      timeError = null;
                    });

                    // Проверяем наложение времени
                    if (_checkTimeOverlap(timeController.text)) {
                      _showTimeOverlapDialog().then((shouldContinue) {
                        if (shouldContinue != true) {
                          return; // Пользователь отменил сохранение
                        }
                        // Продолжаем с сохранением
                      _saveNewScheduleEntry(timeController, shortNoteController, dynamicFields, recurrence, databaseId, tags);
                      });
                    } else {
                      // Нет наложения времени, сохраняем сразу
                    _saveNewScheduleEntry(timeController, shortNoteController, dynamicFields, recurrence, databaseId, tags);
                    }
                  },
                  child: const Text('Сохранить'),
                ),
              ],
            );
          },
      ),
    );
  }

  // Вспомогательный метод для сохранения новой записи расписания
  void _saveNewScheduleEntry(TextEditingController timeController, TextEditingController shortNoteController, 
      List<DynamicFieldEntry> dynamicFields, Recurrence recurrence, String? databaseId, List<String> tags) {
    // Собираем динамические поля
    Map<String, String> dynamicMap = {};
    for (var field in dynamicFields) {
      dynamicMap[field.keyController.text] = field.valueController.text;
    }

    // Создаем объект записи
    ScheduleEntry entry = ScheduleEntry(
      time: timeController.text,
      date: DateFormat('yyyy-MM-dd').format(_selectedDate!),
      note: shortNoteController.text.trim(),
      dynamicFieldsJson: jsonEncode(dynamicMap),
      recurrence: recurrence,
      databaseId: databaseId, // Добавляем ID базы данных
      tags: tags, // Добавляем теги
    );

    print('Создание записи расписания в базе: ${databaseId ?? "локальная"}');
    // Сохраняем запись в БД
    DatabaseHelper().insertScheduleEntry(entry.toMap()).then((_) {
      if (!mounted) return;
      // Обновляем список записей
      setState(() {
        _loadSchedule();
      });
      Navigator.pop(context);
      showCustomToastWithIcon(
        "Запись успешно добавлена",
        accentColor: Colors.green,
        fontSize: 14.0,
        icon: const Icon(Icons.check, size: 20, color: Colors.green),
      );
    });
  }

  // Вспомогательный метод для определения подсказки интервала
  String _getIntervalHelperText(RecurrenceType type) {
    switch (type) {
      case RecurrenceType.daily:
        return 'Повторять каждые X дней';
      case RecurrenceType.weekly:
        return 'Повторять каждые X недель';
      case RecurrenceType.monthly:
        return 'Повторять каждые X месяцев';
      case RecurrenceType.yearly:
        return 'Повторять каждые X лет';
      default:
        return '';
    }
  }

  // Метод редактирования интервала с использованием маски для поля времени.
  void _editScheduleEntry(ScheduleEntry entry) {
    // Находим индекс записи
    final index = _scheduleEntries.indexOf(entry);
    if (index != -1) {
      _editSchedule(index);
    }
  }

  // Метод удаления интервала
  void _deleteScheduleEntryByEntry(ScheduleEntry entry) {
    // Находим индекс записи
    final index = _scheduleEntries.indexOf(entry);
    if (index != -1) {
      _deleteScheduleEntry(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Если дата не выбрана, показываем календарь
    if (_selectedDate == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Расписание")),
        body: CalendarGrid(
          selectedDate: _currentMonth,
          onDateSelected: (date) {
            if (date.month != _currentMonth.month) {
              setState(() {
                _currentMonth = date;
              });
            } else {
              _onDateSelected(date);
            }
          },
          highlightedDate: _highlightedDate,
          onDateHighlighted: _onDateHighlighted,
          onMonthChanged: (date) {
            setState(() {
              _currentMonth = date;
            });
          },
        ),
      );
    }
    
    // Если выбран день, отображаем новую сетку расписания
    return Scaffold(
      appBar: AppBar(
        title: Text(
            "Расписание на ${DateFormat('dd MMMM yyyy', 'ru').format(_selectedDate!)}"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _goBackToCalendar,
        ),
        actions: [
          IconButton(
            onPressed: _addScheduleEntry,
            icon: const Icon(Icons.add),
            tooltip: 'Добавить запись',
          ),
        ],
      ),
      body: _buildDayScheduleView(),
    );
  }

  Widget _buildDayScheduleView() {
    if (_scheduleEntries.isEmpty) {
      return Center(
                    child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
                      children: [
            Icon(
              Icons.schedule,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'На ${DateFormat('d MMMM yyyy', 'ru').format(_selectedDate!)} нет записей',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
                            onPressed: _addScheduleEntry,
                            icon: const Icon(Icons.add),
              label: const Text('Добавить запись'),
            ),
          ],
        ),
      );
    }

    // Сетка расписания с правильной структурой
    return Column(
      children: [
                        Expanded(
          child: _buildScheduleGrid(),
        ),
      ],
    );
  }

  Widget _buildScheduleGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: SizedBox(
            height: 24 * 60.0, // 24 часа по 60 пикселей на час
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Временная шкала (часы)
                _buildTimeScale(),
                
                // Разделитель
                Container(
                  width: 1,
                  height: 24 * 60.0,
                  color: Theme.of(context).dividerColor,
                ),
                
                // Область событий
                Expanded(
                  child: _buildEventsArea(constraints.maxWidth - 61), // Учитываем ширину временной шкалы
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEventsArea(double availableWidth) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: math.max(availableWidth, 6 * 182.0), // Минимум 6 столбцов
        height: 24 * 60.0,
        child: Stack(
          children: [
            // Постоянная сетка разделителей
            _buildGridLines(),
            
            // События
            ..._buildEventWidgets(),
          ],
        ),
      ),
    );
  }

  Widget _buildGridLines() {
    const double columnWidth = 180.0;
    const double leftPadding = 8.0;
    const double columnSpacing = 2.0;
    const int maxVisibleColumns = 6; // Показываем сетку для 6 столбцов
    
    return SizedBox(
      width: 6 * 182.0, // Фиксированная ширина для 6 столбцов
      height: 24 * 60.0, // Фиксированная высота
      child: Stack(
                                      children: [
          // Горизонтальные линии (часы) - постоянно видимые
          Column(
            children: List.generate(24, (hour) {
              return Container(
                height: 60,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).dividerColor.withOpacity(0.5),
                      width: 1.0,
                    ),
                  ),
                ),
              );
            }),
          ),
          
          // Вертикальные линии (столбцы) - постоянно видимые
          Positioned(
            left: leftPadding, // Сдвигаем все столбцы на leftPadding вправо
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(maxVisibleColumns, (columnIndex) {
                return Container(
                  width: columnIndex == 0 
                      ? columnWidth + columnSpacing // Первый столбец: ширина бокса + отступ до следующего
                      : columnWidth + columnSpacing, // Остальные столбцы: ширина бокса + отступ
                  height: 24 * 60.0,
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(
                        color: Theme.of(context).dividerColor.withOpacity(0.4),
                        width: 1.0,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
                                      ],
                                    ),
    );
  }

  Widget _buildTimeScale() {
    return SizedBox(
      width: 60,
      height: 24 * 60.0,
      child: Column(
        children: List.generate(24, (hour) {
          return Container(
            height: 60,
            width: 60,
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${hour.toString().padLeft(2, '0')}:00',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
                                  ),
                                ),
                              );
        }),
      ),
    );
  }

  List<Widget> _buildEventWidgets() {
    List<Widget> eventWidgets = [];
    
    // Создаем список событий с их временными диапазонами
    List<EventWithTime> eventsWithTime = [];
    for (var entry in _scheduleEntries) {
      final timeRange = _parseTimeRange(entry.time);
      if (timeRange != null) {
        eventsWithTime.add(EventWithTime(
          entry: entry,
          startMinute: timeRange['startTotalMinutes'] as int,
          endMinute: timeRange['endTotalMinutes'] as int,
        ));
      }
    }
    
    // Сортируем события по времени начала
    eventsWithTime.sort((a, b) => a.startMinute.compareTo(b.startMinute));
    
    // Алгоритм размещения событий в колонках
    List<List<EventWithTime>> columns = [];
    
    for (var event in eventsWithTime) {
      bool placed = false;
      
      // Пытаемся разместить событие в существующей колонке
      for (var column in columns) {
        // Проверяем, что новое событие не пересекается с последним в колонке
        bool canPlaceInColumn = true;
        for (var existingEvent in column) {
          if (!(event.endMinute <= existingEvent.startMinute || 
                event.startMinute >= existingEvent.endMinute)) {
            canPlaceInColumn = false;
            break;
          }
        }
        
        if (canPlaceInColumn) {
          column.add(event);
          placed = true;
          break;
        }
      }
      
      // Если не удалось разместить, создаем новую колонку
      if (!placed) {
        columns.add([event]);
      }
    }
    
    // Создаем виджеты для каждого события с новой шириной
    for (int columnIndex = 0; columnIndex < columns.length; columnIndex++) {
      for (var event in columns[columnIndex]) {
        final widget = _buildSingleEventWidget(
          event.entry, 
          event.startMinute, 
          event.endMinute,
          columnIndex,
          columns.length,
        );
        if (widget != null) {
          eventWidgets.add(widget);
        }
      }
    }
    
    return eventWidgets;
  }

  Widget? _buildSingleEventWidget(
    ScheduleEntry entry, 
    int startMinute, 
    int endMinute,
    int columnIndex,
    int totalColumns,
  ) {
    final duration = endMinute - startMinute;
    if (duration <= 0) return null;
    
    final topPosition = startMinute.toDouble();
    final height = duration.toDouble();
    
    // Фиксированная ширина каждого столбца для плотной компоновки
    const double columnWidth = 180.0; // Увеличиваем ширину до 180px
    const double leftPadding = 8.0;
    const double columnSpacing = 2.0;
    
    final leftPosition = leftPadding + (columnIndex * (columnWidth + columnSpacing));
    
    return Positioned(
      left: leftPosition,
      top: topPosition,
      width: columnWidth, // Фиксированная ширина 180px
      height: height,
      child: _ScheduleEventCard(
        entry: entry,
        onTap: () => _editScheduleEntry(entry),
        onDelete: () => _deleteScheduleEntryByEntry(entry),
      ),
    );
  }

  Map<String, dynamic>? _parseTimeRange(String timeString) {
    // Парсим строку времени типа "09:00 - 10:30"
    final parts = timeString.split(' - ');
    if (parts.length != 2) return null;
    
    try {
      final startParts = parts[0].trim().split(':');
      final endParts = parts[1].trim().split(':');
      
      if (startParts.length != 2 || endParts.length != 2) return null;
      
      final startHour = int.parse(startParts[0]);
      final startMinute = int.parse(startParts[1]);
      final endHour = int.parse(endParts[0]);
      final endMinute = int.parse(endParts[1]);
      
      final startTotalMinutes = startHour * 60 + startMinute;
      final endTotalMinutes = endHour * 60 + endMinute;
      
      return {
        'startHour': startHour,
        'startMinute': startMinute,
        'endHour': endHour,
        'endMinute': endMinute,
        'startTotalMinutes': startTotalMinutes,
        'endTotalMinutes': endTotalMinutes,
      };
    } catch (e) {
      print('Ошибка парсинга времени: $e');
      return null;
    }
  }

  void _editSchedule(int index) {
    ScheduleEntry entry = _scheduleEntries[index];
    TextEditingController timeController =
        TextEditingController(text: entry.time);
    TextEditingController shortNoteController =
        TextEditingController(text: entry.note ?? '');
    final timeMaskFormatter = MaskTextInputFormatter(
      mask: '##:## - ##:##',
      filter: {'#': RegExp(r'[0-9]')},
    );
    // Применяем форматирование к существующему значению
    timeMaskFormatter.formatEditUpdate(
      const TextEditingValue(text: ''),
      TextEditingValue(text: entry.time),
    );
    List<DynamicFieldEntry> dynamicFields = [];
    if (entry.dynamicFieldsJson != null &&
        entry.dynamicFieldsJson!.isNotEmpty) {
      Map<String, dynamic> decoded = jsonDecode(entry.dynamicFieldsJson!) as Map<String, dynamic>;
      decoded.forEach((key, value) {
        dynamicFields.add(DynamicFieldEntry(key: key, value: value.toString()));
      });
    }
    
    // Инициализируем теги
    List<String> tags = List<String>.from(entry.tags);
    
    String? timeError;
    
    // Параметры повторяемости
    Recurrence recurrence = entry.recurrence;
    final TextEditingController intervalController = TextEditingController(text: '${recurrence.interval ?? 1}');
    final TextEditingController countController = TextEditingController(
      text: recurrence.count != null ? '${recurrence.count}' : ''
    );
    DateTime? selectedEndDate = recurrence.endDate;
    
    showDialog(
      context: context,
      builder: (BuildContext outerContext) {
        return StatefulBuilder(
          builder: (BuildContext innerContext,
              void Function(void Function()) setStateDialog) {
            return AlertDialog(
              title: const Text('Редактировать интервал'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: timeController,
                      inputFormatters: [timeMaskFormatter],
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Время (HH:MM - HH:MM)',
                        errorText: timeError,
                        helperText: 'Допустимые значения: 00:00 - 23:59',
                      ),
                    ),
                    const SizedBox(height: 10),
                    
                    // Секция повторяемости
                    const Divider(),
                    const Text(
                      'Повторяемость',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    
                    // Выбор типа повторения
                    DropdownButtonFormField<RecurrenceType>(
                      value: recurrence.type,
                      decoration: const InputDecoration(
                        labelText: 'Тип повторения',
                      ),
                      items: RecurrenceType.values.map((type) {
                        String label;
                        switch (type) {
                          case RecurrenceType.none:
                            label = 'Без повторения';
                            break;
                          case RecurrenceType.daily:
                            label = 'Ежедневно';
                            break;
                          case RecurrenceType.weekly:
                            label = 'Еженедельно';
                            break;
                          case RecurrenceType.monthly:
                            label = 'Ежемесячно';
                            break;
                          case RecurrenceType.yearly:
                            label = 'Ежегодно';
                            break;
                        }
                        return DropdownMenuItem<RecurrenceType>(
                          value: type,
                          child: Text(label),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setStateDialog(() {
                          recurrence.type = value!;
                        });
                      },
                    ),
                    
                    // Показываем дополнительные настройки только если тип не "Без повторения"
                    if (recurrence.type != RecurrenceType.none) ...[
                      const SizedBox(height: 10),
                      
                      // Интервал
                      TextField(
                        controller: intervalController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Интервал',
                          helperText: _getIntervalHelperText(recurrence.type),
                        ),
                        onChanged: (value) {
                          int? interval = int.tryParse(value);
                          if (interval != null && interval > 0) {
                            recurrence.interval = interval;
                          }
                        },
                      ),
                      
                      const SizedBox(height: 10),
                      
                      // Тип ограничения (по дате или количеству)
                      Row(
                        children: [
                          const Text('Ограничение: '),
                          Radio<String>(
                            value: 'none',
                            groupValue: selectedEndDate != null 
                                ? 'date' 
                                : (recurrence.count != null ? 'count' : 'none'),
                            onChanged: (value) {
                              setStateDialog(() {
                                selectedEndDate = null;
                                recurrence.endDate = null;
                                recurrence.count = null;
                                countController.text = '';
                              });
                            },
                          ),
                          const Text('Без ограничения'),
                          
                          Radio<String>(
                            value: 'date',
                            groupValue: selectedEndDate != null 
                                ? 'date' 
                                : (recurrence.count != null ? 'count' : 'none'),
                            onChanged: (value) {
                              setStateDialog(() {
                                selectedEndDate = DateTime.now().add(const Duration(days: 30));
                                recurrence.endDate = selectedEndDate;
                                recurrence.count = null;
                                countController.text = '';
                              });
                            },
                          ),
                          const Text('По дате'),
                          
                          Radio<String>(
                            value: 'count',
                            groupValue: selectedEndDate != null 
                                ? 'date' 
                                : (recurrence.count != null ? 'count' : 'none'),
                            onChanged: (value) {
                              setStateDialog(() {
                                selectedEndDate = null;
                                recurrence.endDate = null;
                                recurrence.count = 10;
                                countController.text = '10';
                              });
                            },
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 10),
                      
                      // Ввод даты окончания
                      if (selectedEndDate != null)
                        Row(
                          children: [
                            const Text('Дата окончания: '),
                            TextButton(
                              onPressed: () async {
                                final DateTime? picked = await showDatePicker(
                                  context: innerContext,
                                  initialDate: selectedEndDate!,
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime(2100),
                                  locale: const Locale('ru', 'RU'),
                                );
                                if (picked != null && picked != selectedEndDate) {
                                  setStateDialog(() {
                                    selectedEndDate = picked;
                                    recurrence.endDate = picked;
                                  });
                                }
                              },
                              child: Text(
                                DateFormat('dd.MM.yyyy').format(selectedEndDate!),
                              ),
                            ),
                          ],
                        ),
                      
                      // Ввод количества повторений
                      if (recurrence.count != null)
                        TextField(
                          controller: countController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Количество повторений',
                          ),
                          onChanged: (value) {
                            int? count = int.tryParse(value);
                            if (count != null && count > 0) {
                              recurrence.count = count;
                            }
                          },
                        ),
                    ],
                    
                    const Divider(),
                    
                    Column(
                      children: dynamicFields.map((field) {
                        int fieldIndex = dynamicFields.indexOf(field);
                        return Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: field.keyController,
                                decoration:
                                    const InputDecoration(labelText: 'Поле'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 4,
                              child: TextField(
                                controller: field.valueController,
                                decoration: const InputDecoration(
                                    labelText: 'Значение'),
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                setStateDialog(() {
                                  dynamicFields.removeAt(fieldIndex);
                                });
                              },
                              icon: const Icon(Icons.delete),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () {
                          setStateDialog(() {
                            dynamicFields.add(DynamicFieldEntry(
                                key: 'Новое поле', value: ''));
                          });
                        },
                        child: const Text('Добавить поле'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: shortNoteController,
                      decoration:
                          const InputDecoration(labelText: 'Краткая заметка'),
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Виджет для работы с тегами
                    const Text('Теги:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TagInputWidget(
                      initialTags: tags,
                      onTagsChanged: (newTags) {
                        tags = newTags;
                      },
                      hintText: 'Добавить тег...',
                      maxTags: 10,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    // Проверка: если маска не заполнена полностью (т.е. меньше 8 цифр)
                    if (timeMaskFormatter.getUnmaskedText().length < 8) {
                      setStateDialog(() {
                        timeError = 'Заполните время полностью';
                      });
                      return;
                    }

                    // Проверка корректности времени
                    String timeStr = timeController.text.trim();
                    List<String> timeParts = timeStr.split(' - ');
                    if (timeParts.length != 2) {
                      setStateDialog(() {
                        timeError = 'Неверный формат времени';
                      });
                      return;
                    }

                    // Проверка начального времени
                    List<String> startTimeParts = timeParts[0].split(':');
                    if (startTimeParts.length != 2) {
                      setStateDialog(() {
                        timeError = 'Неверный формат времени начала';
                      });
                      return;
                    }

                    int startHour = int.tryParse(startTimeParts[0]) ?? -1;
                    int startMinute = int.tryParse(startTimeParts[1]) ?? -1;
                    
                    if (startHour < 0 || startHour > 23 || startMinute < 0 || startMinute > 59) {
                      setStateDialog(() {
                        timeError = 'Время начала должно быть от 00:00 до 23:59';
                      });
                      return;
                    }

                    // Проверка конечного времени
                    List<String> endTimeParts = timeParts[1].split(':');
                    if (endTimeParts.length != 2) {
                      setStateDialog(() {
                        timeError = 'Неверный формат времени окончания';
                      });
                      return;
                    }

                    int endHour = int.tryParse(endTimeParts[0]) ?? -1;
                    int endMinute = int.tryParse(endTimeParts[1]) ?? -1;
                    
                    if (endHour < 0 || endHour > 23 || endMinute < 0 || endMinute > 59) {
                      setStateDialog(() {
                        timeError = 'Время окончания должно быть от 00:00 до 23:59';
                      });
                      return;
                    }

                    // Сравнение начального и конечного времени
                    final startTimeMinutes = startHour * 60 + startMinute;
                    final endTimeMinutes = endHour * 60 + endMinute;
                    
                    if (startTimeMinutes >= endTimeMinutes) {
                      setStateDialog(() {
                        timeError = 'Время начала должно быть раньше времени окончания';
                      });
                      return;
                    }
                    
                    if (_checkTimeOverlap(timeController.text, excludeIndex: index)) {
                      _showTimeOverlapDialog().then((shouldContinue) {
                        if (shouldContinue != true) {
                          return;
                        }
                        // Продолжаем с сохранением
                        Map<String, String> dynamicMap = {};
                        for (var field in dynamicFields) {
                          String key = field.keyController.text.trim();
                          if (key.isNotEmpty) {
                            dynamicMap[key] = field.valueController.text;
                          }
                        }
                        
                        // Финальное обновление параметров повторяемости
                        if (recurrence.type != RecurrenceType.none) {
                          recurrence.interval = int.tryParse(intervalController.text) ?? 1;
                          if (selectedEndDate != null) {
                            recurrence.endDate = selectedEndDate;
                            recurrence.count = null;
                          } else if (countController.text.isNotEmpty) {
                            recurrence.count = int.tryParse(countController.text);
                            recurrence.endDate = null;
                          }
                        }
                        
                        entry.time = timeController.text;
                        entry.note = shortNoteController.text.trim();
                        entry.dynamicFieldsJson = jsonEncode(dynamicMap);
                        entry.recurrence = recurrence;
                        entry.tags = tags; // Сохраняем теги
                        
                        // Сохраняем существующий databaseId или устанавливаем новый если нужно
                        if (entry.databaseId == null) {
                          try {
                            final collabProvider = Provider.of<EnhancedCollaborativeProvider>(context, listen: false);
                            if (collabProvider.isUsingSharedDatabase) {
                              entry.databaseId = collabProvider.currentDatabaseId;
                              print('Обновление записи расписания с установкой базы: ${entry.databaseId}');
                            }
                          } catch (e) {
                            print('Ошибка при получении информации о совместной базе: $e');
                          }
                        } else {
                          print('Обновление записи расписания в базе: ${entry.databaseId}');
                        }
                        
                        DatabaseHelper().updateScheduleEntry(entry).then((_) {
                          setState(() {
                            _scheduleEntries[index] = entry;
                          });
                          _loadSchedule();
                          showCustomToastWithIcon(
                            "Интервал успешно обновлён",
                            accentColor: Colors.yellow,
                            fontSize: 14.0,
                            icon: const Icon(Icons.edit,
                                size: 20, color: Colors.yellow),
                          );
                          Navigator.of(outerContext).pop();
                        });
                      });
                      return;
                    }

                    // Сохранение при отсутствии наложения
                    Map<String, String> dynamicMap = {};
                    for (var field in dynamicFields) {
                      String key = field.keyController.text.trim();
                      if (key.isNotEmpty) {
                        dynamicMap[key] = field.valueController.text;
                      }
                    }
                    
                    // Финальное обновление параметров повторяемости
                    if (recurrence.type != RecurrenceType.none) {
                      recurrence.interval = int.tryParse(intervalController.text) ?? 1;
                      if (selectedEndDate != null) {
                        recurrence.endDate = selectedEndDate;
                        recurrence.count = null;
                      } else if (countController.text.isNotEmpty) {
                        recurrence.count = int.tryParse(countController.text);
                        recurrence.endDate = null;
                      }
                    } else {
                      recurrence.interval = 1;
                      recurrence.endDate = null;
                      recurrence.count = null;
                    }
                    
                    entry.time = timeController.text;
                    entry.note = shortNoteController.text.trim();
                    entry.dynamicFieldsJson = jsonEncode(dynamicMap);
                    entry.recurrence = recurrence;
                    entry.tags = tags; // Сохраняем теги
                    
                    // Сохраняем существующий databaseId или устанавливаем новый если нужно
                    if (entry.databaseId == null) {
                      try {
                        final collabProvider = Provider.of<EnhancedCollaborativeProvider>(context, listen: false);
                        if (collabProvider.isUsingSharedDatabase) {
                          entry.databaseId = collabProvider.currentDatabaseId;
                          print('Обновление записи расписания с установкой базы: ${entry.databaseId}');
                        }
                      } catch (e) {
                        print('Ошибка при получении информации о совместной базе: $e');
                      }
                    } else {
                      print('Обновление записи расписания в базе: ${entry.databaseId}');
                    }
                    
                    DatabaseHelper().updateScheduleEntry(entry).then((_) {
                      setState(() {
                        _scheduleEntries[index] = entry;
                      });
                      _loadSchedule();
                      showCustomToastWithIcon(
                        "Интервал успешно обновлён",
                        accentColor: Colors.yellow,
                        fontSize: 14.0,
                        icon: const Icon(Icons.edit,
                            size: 20, color: Colors.yellow),
                      );
                      Navigator.of(outerContext).pop();
                    });
                  },
                  child: const Text('Сохранить'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(outerContext).pop();
                    _deleteScheduleEntry(index);
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                  child: const Text('Удалить'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(outerContext).pop(),
                  child: const Text('Отмена'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Удаление интервала
  void _deleteScheduleEntry(int index) {
    ScheduleEntry entry = _scheduleEntries[index];
    
    // Если у события есть повторения, спрашиваем пользователя, что именно удалить
    if (entry.recurrence.type != RecurrenceType.none) {
      showDialog(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Удаление повторяющегося события'),
            content: const Text('Что именно вы хотите удалить?'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  // Удаляем только текущий экземпляр события
                  setState(() {
                    _scheduleEntries.removeAt(index);
                    _selectedIndex = null;
                  });
                  
                  showCustomToastWithIcon(
                    "Текущий экземпляр события удален",
                    accentColor: Colors.yellow,
                    fontSize: 14.0,
                    icon: const Icon(Icons.close, size: 20, color: Colors.yellow),
                  );
                },
                child: const Text('Только это событие'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  // Удаляем все повторения
                  DatabaseHelper().deleteScheduleEntry(entry.id!).then((_) {
                    setState(() {
                      _scheduleEntries.removeAt(index);
                      _selectedIndex = null;
                    });
                    
                    showCustomToastWithIcon(
                      "Все повторения события удалены",
                      accentColor: Colors.red,
                      fontSize: 14.0,
                      icon: const Icon(Icons.close, size: 20, color: Colors.red),
                    );
                  });
                },
                child: const Text('Все повторения'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Отмена'),
              ),
            ],
          );
        },
      );
    } else {
      // Обычное удаление для непосредственного события без повторений
      DatabaseHelper().deleteScheduleEntry(entry.id!).then((_) {
        setState(() {
          _scheduleEntries.removeAt(index);
          _selectedIndex = null;
        });
        
        showCustomToastWithIcon(
          "Интервал успешно удалён",
          accentColor: Colors.red,
          fontSize: 14.0,
          icon: const Icon(Icons.close, size: 20, color: Colors.red),
        );
      });
    }
  }

  // Контекстное меню для интервала
  void _showScheduleContextMenu(
      BuildContext context, int index, Offset position) async {
    final RenderBox? overlay =
        Overlay.of(context)?.context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    await showMenu(
      context: context,
      position: RelativeRect.fromRect(
          position & const Size(40, 40), Offset.zero & overlay.size),
      items: const [
        PopupMenuItem<String>(value: 'edit', child: Text('Редактировать')),
        PopupMenuItem<String>(value: 'delete', child: Text('Удалить')),
      ],
    ).then((value) {
      if (value == 'edit') {
        _editSchedule(index);
      } else if (value == 'delete') {
        _deleteScheduleEntry(index);
      }
    });
  }

  // Метод для определения цвета иконки повторения
  Color _getRecurrenceColor(RecurrenceType type) {
    switch (type) {
      case RecurrenceType.daily:
        return Colors.green;
      case RecurrenceType.weekly:
        return Colors.blue;
      case RecurrenceType.monthly:
        return Colors.orange;
      case RecurrenceType.yearly:
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }
}

// Виджет для отображения события в расписании
class _ScheduleEventCard extends StatefulWidget {
  final ScheduleEntry entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ScheduleEventCard({
    Key? key,
    required this.entry,
    required this.onTap,
    required this.onDelete,
  }) : super(key: key);

  @override
  _ScheduleEventCardState createState() => _ScheduleEventCardState();
}

class _ScheduleEventCardState extends State<_ScheduleEventCard> {
  bool _isHovered = false;
  OverlayEntry? _overlayEntry;
  final GlobalKey _cardKey = GlobalKey();

  void _showTooltip() {
    if (widget.entry.note == null || widget.entry.note!.isEmpty) {
      // Для коротких событий показываем подсказку даже без заметки
      final eventHeight = _calculateEventDuration();
      final isShortEvent = eventHeight < 80;
      if (!isShortEvent) return;
    }
    
    // Получаем позицию карточки
    final RenderBox? renderBox = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    final Offset position = renderBox.localToGlobal(Offset.zero);
    final Size size = renderBox.size;
    
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: position.dx + size.width + 4, // Справа от карточки
        top: position.dy, // На уровне карточки
        child: Material(
          elevation: 100, // Максимальный elevation
          borderRadius: BorderRadius.circular(8),
          color: Colors.transparent,
                  child: Container(
            width: 250,
            constraints: const BoxConstraints(maxHeight: 300),
            padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                width: 1.5,
                    ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.8),
                  blurRadius: 25,
                  offset: const Offset(0, 15),
                  spreadRadius: 8,
                        ),
              ],
            ),
            child: _buildTooltipContent(),
          ),
        ),
      ),
    );
    
    Overlay.of(context).insert(_overlayEntry!);
  }

  Widget _buildTooltipContent() {
    final eventHeight = _calculateEventDuration();
    final isShortEvent = eventHeight < 80;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
                                      children: [
        // Время события
                                              Text(
          'Время: ${widget.entry.time}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                  fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        
        // Динамические поля (для коротких событий)
        if (isShortEvent && widget.entry.dynamicFieldsJson != null) ...[
          _buildTooltipDynamicFields(),
          const SizedBox(height: 8),
        ],
        
        // Теги (для коротких событий)
        if (isShortEvent && widget.entry.tags.isNotEmpty) ...[
          Text(
            'Теги:',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
                                                    ),
                                                  ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 2,
            children: widget.entry.tags.map((tag) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                    width: 0.5,
                  ),
                ),
                                          child: Text(
                  tag,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 10,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
        ],
        
        // Заметка (если есть)
        if (widget.entry.note != null && widget.entry.note!.isNotEmpty) ...[
          Text(
            'Заметка:',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
                                        ),
          ),
          const SizedBox(height: 4),
          Flexible(
            child: SingleChildScrollView(
              child: Text(
                widget.entry.note!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                          ),
                        ),
                      ],
      ],
    );
  }

  Widget _buildTooltipDynamicFields() {
    try {
      final fieldsMap = jsonDecode(widget.entry.dynamicFieldsJson!) as Map<String, dynamic>;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Детали:',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          ...fieldsMap.entries.where((entry) => entry.value.toString().isNotEmpty).map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '${entry.key}: ${entry.value}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            );
          }).toList(),
        ],
      );
    } catch (e) {
      return const SizedBox.shrink();
    }
  }

  @override
  void dispose() {
    _hideTooltip();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Вычисляем высоту события в пикселях из поля time
    final eventHeight = _calculateEventDuration();
    final isShortEvent = eventHeight < 80; // Событие короче 80 пикселей считается коротким
    
    return MouseRegion(
      onEnter: (_) {
        if (mounted) {
          setState(() => _isHovered = true);
          // Показываем подсказку для коротких событий или если есть заметка
          if (isShortEvent || (widget.entry.note != null && widget.entry.note!.isNotEmpty)) {
            _showTooltip();
          }
        }
      },
      onExit: (_) {
        if (mounted) {
          setState(() => _isHovered = false);
          _hideTooltip();
        }
      },
      child: GestureDetector(
        onSecondaryTap: widget.onTap, // Изменено: правая кнопка мыши для редактирования
        child: Container(
          key: _cardKey,
          width: 180, // Строго фиксированная ширина
          height: double.infinity, // ИСПРАВЛЕНИЕ: Растягиваем на всю доступную высоту
          margin: const EdgeInsets.only(right: 2, bottom: 2),
                    decoration: BoxDecoration(
            color: const Color(0xFF22a6b3), // Цвет cyan #22a6b3
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFF22a6b3).withOpacity(0.7),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
                          ),
            ],
                        ),
                            padding: const EdgeInsets.all(8),
          child: isShortEvent ? _buildShortEventContent() : _buildFullEventContent(),
        ),
      ),
    );
  }

  // Вычисляем длительность события в минутах из поля time
  double _calculateEventDuration() {
    try {
      final timeParts = widget.entry.time.split(' - ');
      if (timeParts.length != 2) return 60.0; // По умолчанию 60 минут
      
      final startParts = timeParts[0].split(':');
      final endParts = timeParts[1].split(':');
      
      if (startParts.length != 2 || endParts.length != 2) return 60.0;
      
      final startMinutes = int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
      final endMinutes = int.parse(endParts[0]) * 60 + int.parse(endParts[1]);
      
      return (endMinutes - startMinutes).toDouble();
    } catch (e) {
      return 60.0; // По умолчанию 60 минут при ошибке парсинга
    }
  }

  // Содержимое для коротких событий (только время)
  Widget _buildShortEventContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.max,
      children: [
        // Только временной интервал для коротких событий
        Flexible(
                                    child: Text(
            widget.entry.time,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const Spacer(),
      ],
    );
  }

  // Полное содержимое для обычных событий
  Widget _buildFullEventContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.max,
      children: [
        // Временной интервал (левый верхний угол)
        Text(
          widget.entry.time,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        
        // Динамические поля
        if (widget.entry.dynamicFieldsJson != null) ...[
          Flexible(child: _buildDynamicFields()),
          const SizedBox(height: 4),
        ],
        
        // Теги
        if (widget.entry.tags.isNotEmpty) ...[
          Flexible(child: _buildTags()),
        ],
        
        // Заполнитель для растягивания на всю высоту
        const Spacer(),
      ],
    );
  }

  Widget _buildDynamicFields() {
    try {
      final fieldsMap = jsonDecode(widget.entry.dynamicFieldsJson!) as Map<String, dynamic>;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: fieldsMap.entries.where((entry) => entry.value.toString().isNotEmpty).map((entry) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              '${entry.key}: ${entry.value}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                                    ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
                                  ),
          );
        }).toList(),
      );
    } catch (e) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildTags() {
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: widget.entry.tags.take(3).map((tag) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 0.5,
            ),
          ),
          child: Text(
            tag,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
            ),
      ),
    );
      }).toList(),
    );
  }

  void _hideTooltip() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
} 