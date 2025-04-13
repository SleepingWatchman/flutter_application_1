import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import '../widgets/calendar_grid.dart';
import '../db/database_helper.dart';
import '../models/schedule_entry.dart';
import '../models/dynamic_field_entry.dart';
import '../utils/toast_utils.dart';
import '../providers/database_provider.dart';
import 'package:provider/provider.dart';

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
  List<ScheduleEntry> _schedule = [];
  int? _selectedIndex;
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // При запуске ни один день не выбран – отображается календарь.
    _selectedDate = null;
    _highlightedDate = null;
    _currentMonth = DateTime.now();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Provider.of<DatabaseProvider>(context, listen: false).needsUpdate) {
      if (_selectedDate != null) {
        _loadSchedule();
      }
      Provider.of<DatabaseProvider>(context, listen: false).resetUpdateFlag();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
      _schedule.clear();
      _selectedIndex = null;
    });
  }

  Future<void> _loadSchedule() async {
    if (_selectedDate != null) {
      String dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      List<ScheduleEntry> entries = await DatabaseHelper().getScheduleEntries();
      setState(() {
        _schedule = entries.where((entry) => entry.date == dateKey).toList();
        // Сортируем события по времени начала и окончания
        _schedule.sort((a, b) {
          final aTimes = a.time.split(' - ');
          final bTimes = b.time.split(' - ');
          final aStart = aTimes[0].split(':');
          final bStart = bTimes[0].split(':');
          final aEnd = aTimes[1].split(':');
          final bEnd = bTimes[1].split(':');
          
          final aStartMinutes = int.parse(aStart[0]) * 60 + int.parse(aStart[1]);
          final bStartMinutes = int.parse(bStart[0]) * 60 + int.parse(bStart[1]);
          
          if (aStartMinutes != bStartMinutes) {
            return aStartMinutes.compareTo(bStartMinutes);
          }
          
          final aEndMinutes = int.parse(aEnd[0]) * 60 + int.parse(aEnd[1]);
          final bEndMinutes = int.parse(bEnd[0]) * 60 + int.parse(bEnd[1]);
          
          return aEndMinutes.compareTo(bEndMinutes);
        });
        _selectedIndex = null;
      });
    }
  }

  bool _checkTimeOverlap(String newTime, {int? excludeIndex}) {
    final newTimes = newTime.split(' - ');
    final newStart = newTimes[0].split(':');
    final newEnd = newTimes[1].split(':');
    final newStartMinutes = int.parse(newStart[0]) * 60 + int.parse(newStart[1]);
    final newEndMinutes = int.parse(newEnd[0]) * 60 + int.parse(newEnd[1]);

    for (int i = 0; i < _schedule.length; i++) {
      if (excludeIndex != null && i == excludeIndex) continue;
      
      final entry = _schedule[i];
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
    String? timeError;

    showDialog(
      context: context,
      builder: (BuildContext outerContext) {
        return StatefulBuilder(
          builder: (BuildContext innerContext,
              void Function(void Function()) setStateDialog) {
            return AlertDialog(
              title: const Text('Добавить интервал'),
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
                    // Динамические поля
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
                    // Многострочное поле для краткой заметки
                    TextField(
                      controller: shortNoteController,
                      decoration:
                          const InputDecoration(labelText: 'Краткая заметка'),
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
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

                    if (_checkTimeOverlap(timeController.text)) {
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
                        ScheduleEntry newEntry = ScheduleEntry(
                          time: timeController.text.trim(),
                          date: DateFormat('yyyy-MM-dd').format(_selectedDate!),
                          note: shortNoteController.text.trim(),
                          dynamicFieldsJson: jsonEncode(dynamicMap),
                        );
                        DatabaseHelper().insertScheduleEntry(newEntry.toMap()).then((id) {
                          newEntry.id = id;
                          setState(() {
                            _schedule.add(newEntry);
                          });
                          _loadSchedule();
                          showCustomToastWithIcon(
                            "Интервал успешно создан",
                            accentColor: Colors.green,
                            fontSize: 14.0,
                            icon: const Icon(Icons.check,
                                size: 20, color: Colors.green),
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
                    ScheduleEntry newEntry = ScheduleEntry(
                      time: timeController.text.trim(),
                      date: DateFormat('yyyy-MM-dd').format(_selectedDate!),
                      note: shortNoteController.text.trim(),
                      dynamicFieldsJson: jsonEncode(dynamicMap),
                    );
                    DatabaseHelper().insertScheduleEntry(newEntry.toMap()).then((id) {
                      newEntry.id = id;
                      setState(() {
                        _schedule.add(newEntry);
                      });
                      _loadSchedule();
                      showCustomToastWithIcon(
                        "Интервал успешно создан",
                        accentColor: Colors.green,
                        fontSize: 14.0,
                        icon: const Icon(Icons.check,
                            size: 20, color: Colors.green),
                      );
                      Navigator.of(outerContext).pop();
                    });
                  },
                  child: const Text('Сохранить'),
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

  // Метод редактирования интервала с использованием маски для поля времени.
  void _editSchedule(int index) {
    ScheduleEntry entry = _schedule[index];
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
      Map<String, dynamic> decoded = jsonDecode(entry.dynamicFieldsJson!);
      decoded.forEach((key, value) {
        dynamicFields.add(DynamicFieldEntry(key: key, value: value.toString()));
      });
    }
    String? timeError;
    
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
                        entry.time = timeController.text;
                        entry.note = shortNoteController.text.trim();
                        entry.dynamicFieldsJson = jsonEncode(dynamicMap);
                        DatabaseHelper().updateScheduleEntry(entry).then((_) {
                          setState(() {
                            _schedule[index] = entry;
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
                    entry.time = timeController.text;
                    entry.note = shortNoteController.text.trim();
                    entry.dynamicFieldsJson = jsonEncode(dynamicMap);
                    DatabaseHelper().updateScheduleEntry(entry).then((_) {
                      setState(() {
                        _schedule[index] = entry;
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
    DatabaseHelper().deleteScheduleEntry(_schedule[index].id!).then((_) {
      setState(() {
        _schedule.removeAt(index);
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
        ),
      );
    }
    // Если выбран день, отображаем детальный режим расписания
    return Scaffold(
      appBar: AppBar(
        title: Text(
            "Расписание на ${DateFormat('dd MMMM yyyy', 'ru').format(_selectedDate!)}"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _goBackToCalendar,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                // Список интервалов
                Expanded(
                  flex: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      border: Border.all(color: Colors.cyan.withOpacity(0.3)),
                    ),
                    child: Column(
                      children: [
                        // Кнопка добавления интервала в верхней части списка
                        Container(
                          padding: const EdgeInsets.all(8),
                          child: ElevatedButton.icon(
                            onPressed: _addScheduleEntry,
                            icon: const Icon(Icons.add),
                            label: const Text('Добавить интервал'),
                          ),
                        ),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.all(8),
                            itemCount: _schedule.length,
                            separatorBuilder: (context, index) =>
                                const Divider(color: Colors.cyan),
                            itemBuilder: (context, index) {
                              ScheduleEntry entry = _schedule[index];
                              String dynamicFieldsDisplay = '';
                              if (entry.dynamicFieldsJson != null &&
                                  entry.dynamicFieldsJson!.isNotEmpty) {
                                Map<String, dynamic> decoded =
                                    jsonDecode(entry.dynamicFieldsJson!);
                                dynamicFieldsDisplay = decoded.entries
                                    .map((e) => "${e.key}: ${e.value}")
                                    .join(", ");
                              }
                              return GestureDetector(
                                onSecondaryTapDown: (details) {
                                  _showScheduleContextMenu(
                                      context, index, details.globalPosition);
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: _selectedIndex == index
                                        ? Colors.cyan.withOpacity(0.2)
                                        : null,
                                    border: Border.all(
                                      color: _selectedIndex == index
                                          ? Colors.cyan
                                          : Colors.transparent,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: ListTile(
                                    title: Row(
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            entry.time,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const VerticalDivider(
                                            color: Colors.cyan, thickness: 2),
                                        Expanded(
                                          flex: 5,
                                          child: Text(
                                            dynamicFieldsDisplay,
                                            style:
                                                const TextStyle(color: Colors.white70),
                                          ),
                                        ),
                                      ],
                                    ),
                                    onTap: () {
                                      setState(() {
                                        _selectedIndex = index;
                                      });
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Окно предпросмотра заметки с возможностью изменения размера
                Expanded(
                  flex: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[850],
                      border: Border.all(color: Colors.cyan.withOpacity(0.3)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          child: const Text(
                            'Предпросмотр заметки',
                            style: TextStyle(
                              color: Colors.cyan,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            child: (_selectedIndex == null ||
                                    _selectedIndex! >= _schedule.length)
                                ? const Center(
                                    child: Text('Выберите интервал',
                                        style: TextStyle(color: Colors.white)),
                                  )
                                : SingleChildScrollView(
                                    child: Text(
                                      _schedule[_selectedIndex!].note ?? '',
                                      style: const TextStyle(color: Colors.white70),
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
} 