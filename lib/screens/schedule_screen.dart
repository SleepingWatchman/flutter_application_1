import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import '../widgets/calendar_grid.dart';
import '../db/database_helper.dart';
import '../models/schedule_entry.dart';
import '../models/dynamic_field_entry.dart';
import '../utils/toast_utils.dart';

/// Экран расписания. Если день не выбран (_selectedDate == null), показывается календарная сетка.
/// Если выбран день, отображается детальный режим с интервалами и предпросмотром заметки.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({Key? key}) : super(key: key);

  @override
  _ScheduleScreenState createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  DateTime? _selectedDate; // Если null – показываем календарь
  List<ScheduleEntry> _schedule = [];
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    // При запуске ни один день не выбран – отображается календарь.
    _selectedDate = null;
  }

  // Вызывается при выборе дня из календарной сетки
  void _onDateSelected(DateTime date) {
    setState(() {
      _selectedDate = date;
    });
    _loadSchedule();
  }

  // Возврат к календарю
  void _goBackToCalendar() {
    setState(() {
      _selectedDate = null;
      _schedule.clear();
      _selectedIndex = null;
    });
  }

  Future<void> _loadSchedule() async {
    if (_selectedDate != null) {
      String dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      List<ScheduleEntry> entries =
          await DatabaseHelper().getScheduleEntries(dateKey);
      setState(() {
        _schedule = entries;
        _selectedIndex = null;
      });
    }
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
                    DatabaseHelper().insertScheduleEntry(newEntry).then((id) {
                      newEntry.id = id;
                      setState(() {
                        _schedule.add(newEntry);
                      });
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
                      decoration: const InputDecoration(
                          labelText: 'Время (HH:MM - HH:MM)'),
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
                      showCustomToastWithIcon(
                        "Интервал успешно обновлён",
                        accentColor: Colors.yellow,
                        fontSize: 14.0,
                        icon: const Icon(Icons.error_outline,
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
          selectedDate: DateTime.now(),
          onDateSelected: _onDateSelected,
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
          ElevatedButton(
            onPressed: _addScheduleEntry,
            child: const Text('Добавить интервал'),
          ),
          Expanded(
            child: Row(
              children: [
                // Список интервалов
                Expanded(
                  flex: 2,
                  child: Container(
                    color: Colors.grey[900],
                    child: ListView.separated(
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
                        );
                      },
                    ),
                  ),
                ),
                // Окно предпросмотра заметки
                Expanded(
                  flex: 1,
                  child: Container(
                    color: Colors.grey[850],
                    padding: const EdgeInsets.all(8),
                    alignment: Alignment.topLeft,
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
        ],
      ),
    );
  }
} 