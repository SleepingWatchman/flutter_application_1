import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:oktoast/oktoast.dart';

// Добавьте этот фрагмент в начало файла main.dart (после импортов),
// чтобы функция была доступна во всём приложении.
void showCustomToast(String message,
    {Color accentColor = Colors.green, double fontSize = 14.0}) {  // fontSize изменен на 14.0
  Future.delayed(const Duration(milliseconds: 300), () {
    try {
      showToastWidget(
        Align(
          alignment: Alignment.bottomRight,
          child: Container(
            margin: const EdgeInsets.only(right: 20, bottom: 20),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // уменьшены отступы
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 40, 40, 40).withOpacity(0.8), // фон с opacity 0.6 для более светлого фона
              borderRadius: BorderRadius.circular(8),
            ),
            constraints: const BoxConstraints(maxWidth: 250), // можно уменьшить ширину
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Верхняя полоса с акцентным цветом
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: fontSize, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
        duration: const Duration(seconds: 2),
        dismissOtherToast: true,
      );
    } catch (e) {
      debugPrint("Ошибка при показе toast: $e");
    }
  });
}




/// Класс для работы с базой данных, реализующий CRUD-операции для всех сущностей.
class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = p.join(databasePath, 'notes_app.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Таблица заметок
    await db.execute('''
      CREATE TABLE notes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        content TEXT,
        folder TEXT
      )
    ''');

    // Таблица расписания
    await db.execute('''
      CREATE TABLE schedule(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        time TEXT,
        date TEXT,
        note TEXT,
        dynamicFields TEXT
      )
    ''');

    // Таблица заметок на доске
    await db.execute('''
      CREATE TABLE pinboard_notes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        content TEXT,
        posX REAL,
        posY REAL,
        backgroundColor INTEGER
      )
    ''');

    // Таблица соединений заметок
    await db.execute('''
      CREATE TABLE connections(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fromId INTEGER,
        toId INTEGER
      )
    ''');

    // Таблица папок
    await db.execute('''
      CREATE TABLE folders(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        backgroundColor INTEGER
      )
    ''');
  }

  // Методы для работы с заметками
  Future<int> insertNote(Note note) async {
    final db = await database;
    return await db.insert('notes', note.toMap());
  }

  Future<List<Note>> getNotes() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('notes');
    return List.generate(maps.length, (i) => Note.fromMap(maps[i]));
  }

  Future<int> updateNote(Note note) async {
    final db = await database;
    return await db.update('notes', note.toMap(),
        where: 'id = ?', whereArgs: [note.id]);
  }

  Future<int> deleteNote(int id) async {
    final db = await database;
    return await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  // Методы для работы с расписанием
  Future<int> insertScheduleEntry(ScheduleEntry entry) async {
    final db = await database;
    return await db.insert('schedule', entry.toMap());
  }

  Future<List<ScheduleEntry>> getScheduleEntries(String date) async {
    final db = await database;
    final List<Map<String, dynamic>> maps =
        await db.query('schedule', where: 'date = ?', whereArgs: [date]);
    return List.generate(maps.length, (i) => ScheduleEntry.fromMap(maps[i]));
  }

  Future<int> updateScheduleEntry(ScheduleEntry entry) async {
    final db = await database;
    return await db.update('schedule', entry.toMap(),
        where: 'id = ?', whereArgs: [entry.id]);
  }

  Future<int> deleteScheduleEntry(int id) async {
    final db = await database;
    return await db.delete('schedule', where: 'id = ?', whereArgs: [id]);
  }

  // Методы для работы с заметками на доске
  Future<int> insertPinboardNote(PinboardNoteDB note) async {
    final db = await database;
    return await db.insert('pinboard_notes', note.toMap());
  }

  Future<List<PinboardNoteDB>> getPinboardNotes() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('pinboard_notes');
    return List.generate(maps.length, (i) => PinboardNoteDB.fromMap(maps[i]));
  }

  Future<int> updatePinboardNote(PinboardNoteDB note) async {
    final db = await database;
    return await db.update('pinboard_notes', note.toMap(),
        where: 'id = ?', whereArgs: [note.id]);
  }

  Future<int> deletePinboardNote(int id) async {
    final db = await database;
    return await db.delete('pinboard_notes', where: 'id = ?', whereArgs: [id]);
  }

  // Методы для работы с соединениями заметок
  Future<int> insertConnection(ConnectionDB connection) async {
    final db = await database;
    return await db.insert('connections', connection.toMap());
  }

  Future<List<ConnectionDB>> getConnections() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('connections');
    return List.generate(maps.length, (i) => ConnectionDB.fromMap(maps[i]));
  }

  Future<int> deleteConnection(int id) async {
    final db = await database;
    return await db.delete('connections', where: 'id = ?', whereArgs: [id]);
  }

  // Методы для работы с папками
  Future<int> insertFolder(Folder folder) async {
    final db = await database;
    return await db.insert('folders', folder.toMap());
  }

  Future<List<Folder>> getFolders() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('folders');
    return List.generate(maps.length, (i) => Folder.fromMap(maps[i]));
  }

  Future<int> updateFolder(Folder folder) async {
    final db = await database;
    return await db.update('folders', folder.toMap(),
        where: 'id = ?', whereArgs: [folder.id]);
  }

  Future<int> deleteFolder(int id) async {
    final db = await database;
    return await db.delete('folders', where: 'id = ?', whereArgs: [id]);
  }
}

/// Виджет для отображения дней недели
class WeeklyScheduleGrid extends StatelessWidget {
  final DateTime selectedDay;
  final ValueChanged<DateTime> onDaySelected;

  WeeklyScheduleGrid({required this.selectedDay, required this.onDaySelected});

  List<DateTime> _getWeekDays(DateTime currentDate) {
    int currentWeekday = currentDate.weekday;
    DateTime monday = currentDate.subtract(Duration(days: currentWeekday - 1));
    return List.generate(7, (index) => monday.add(Duration(days: index)));
  }

  @override
  Widget build(BuildContext context) {
    final weekDays = _getWeekDays(DateTime.now());
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: weekDays.map((day) {
          bool isSelected = day.year == selectedDay.year &&
              day.month == selectedDay.month &&
              day.day == selectedDay.day;
          return GestureDetector(
            onTap: () => onDaySelected(day),
            child: Column(
              children: [
                Text(
                  DateFormat('EEE', 'ru').format(day),
                  style: TextStyle(
                    color: isSelected ? Colors.cyan : Colors.white70,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  DateFormat('dd.MM').format(day),
                  style: TextStyle(
                    color: isSelected ? Colors.cyan : Colors.white70,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Виджет выбора цвета с помощью слайдеров
class ColorPicker extends StatefulWidget {
  final Color color;
  final ValueChanged<Color> onChanged;
  const ColorPicker({Key? key, required this.color, required this.onChanged})
      : super(key: key);
  @override
  _ColorPickerState createState() => _ColorPickerState();
}
class _ColorPickerState extends State<ColorPicker> {
  late double r;
  late double g;
  late double b;
  @override
  void initState() {
    super.initState();
    r = widget.color.red.toDouble();
    g = widget.color.green.toDouble();
    b = widget.color.blue.toDouble();
  }
  void _updateColor() {
    widget.onChanged(Color.fromARGB(255, r.toInt(), g.toInt(), b.toInt()));
  }
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const Text("R"),
            Expanded(
              child: Slider(
                min: 0,
                max: 255,
                value: r,
                onChanged: (value) {
                  setState(() {
                    r = value;
                    _updateColor();
                  });
                },
              ),
            ),
          ],
        ),
        Row(
          children: [
            const Text("G"),
            Expanded(
              child: Slider(
                min: 0,
                max: 255,
                value: g,
                onChanged: (value) {
                  setState(() {
                    g = value;
                    _updateColor();
                  });
                },
              ),
            ),
          ],
        ),
        Row(
          children: [
            const Text("B"),
            Expanded(
              child: Slider(
                min: 0,
                max: 255,
                value: b,
                onChanged: (value) {
                  setState(() {
                    b = value;
                    _updateColor();
                  });
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Класс для работы с динамическими полями в расписании
class DynamicFieldEntry {
  TextEditingController keyController;
  TextEditingController valueController;
  DynamicFieldEntry({required String key, required String value})
      : keyController = TextEditingController(text: key),
        valueController = TextEditingController(text: value);
}

/// Модель заметки
class Note {
  int? id;
  String title;
  String content;
  String? folder;
  Note({this.id, this.title = 'Без названия', this.content = '', this.folder});
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'folder': folder,
    };
  }
  factory Note.fromMap(Map<String, dynamic> map) {
    return Note(
      id: map['id'],
      title: map['title'],
      content: map['content'],
      folder: map['folder'],
    );
  }
}

/// Модель папки
class Folder {
  int? id;
  String name;
  int backgroundColor; // хранится как int (ARGB)
  Folder({this.id, required this.name, required this.backgroundColor});
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'backgroundColor': backgroundColor,
    };
  }
  factory Folder.fromMap(Map<String, dynamic> map) {
    return Folder(
      id: map['id'],
      name: map['name'],
      backgroundColor: map['backgroundColor'],
    );
  }
}

/// Модель записи расписания
class ScheduleEntry {
  int? id;
  String time;
  String date;
  String? note;
  String? dynamicFieldsJson;
  ScheduleEntry({this.id, required this.time, required this.date, this.note, this.dynamicFieldsJson});
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'time': time,
      'date': date,
      'note': note,
      'dynamicFields': dynamicFieldsJson,
    };
  }
  factory ScheduleEntry.fromMap(Map<String, dynamic> map) {
    return ScheduleEntry(
      id: map['id'],
      time: map['time'],
      date: map['date'],
      note: map['note'],
      dynamicFieldsJson: map['dynamicFields'],
    );
  }
}

/// Модель заметки для доски (для работы с БД)
class PinboardNoteDB {
  int? id;
  String title;
  String content;
  double posX;
  double posY;
  int backgroundColor;
  PinboardNoteDB({
    this.id,
    this.title = 'Без названия',
    this.content = '',
    required this.posX,
    required this.posY,
    required this.backgroundColor,
  });
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'posX': posX,
      'posY': posY,
      'backgroundColor': backgroundColor,
    };
  }
  factory PinboardNoteDB.fromMap(Map<String, dynamic> map) {
    return PinboardNoteDB(
      id: map['id'],
      title: map['title'],
      content: map['content'],
      posX: map['posX'],
      posY: map['posY'],
      backgroundColor: map['backgroundColor'],
    );
  }
}

/// Модель соединения заметок (для работы с БД)
class ConnectionDB {
  int? id;
  int fromId;
  int toId;
  ConnectionDB({this.id, required this.fromId, required this.toId});
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fromId': fromId,
      'toId': toId,
    };
  }
  factory ConnectionDB.fromMap(Map<String, dynamic> map) {
    return ConnectionDB(
      id: map['id'],
      fromId: map['fromId'],
      toId: map['toId'],
    );
  }
}

/// Функция main: инициализация БД и запуск приложения
void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper().database;
  await initializeDateFormatting('ru', null);
  runApp(const NotesApp());
}

class NotesApp extends StatelessWidget {
  const NotesApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return OKToast(
      child: MaterialApp(
        title: 'Notes App',
        theme: ThemeData.dark(),
        home: const MainScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

/// Главное окно с NavigationRail
class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);
  @override
  _MainScreenState createState() => _MainScreenState();
}
class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final List<Widget> _widgetOptions = <Widget>[
    ScheduleScreen(),
    NotesScreen(),
    PinboardScreen(),
  ];
  void _onItemTapped(int index) {
    setState(() { _selectedIndex = index; });
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _onItemTapped,
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.schedule), label: Text('Расписание')),
              NavigationRailDestination(icon: Icon(Icons.note), label: Text('Заметки')),
              NavigationRailDestination(icon: Icon(Icons.dashboard), label: Text('Доска')),
            ],
          ),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: _widgetOptions,
            ),
          ),
        ],
      ),
    );
  }
}

/// Экран расписания с использованием БД
class ScheduleScreen extends StatefulWidget {
  ScheduleScreen({Key? key}) : super(key: key);
  @override
  _ScheduleScreenState createState() => _ScheduleScreenState();
}
class _ScheduleScreenState extends State<ScheduleScreen> {
  List<ScheduleEntry> _schedule = [];
  DateTime _selectedDate = DateTime.now();
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _loadSchedule();
  }

  Future<void> _loadSchedule() async {
    String dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    List<ScheduleEntry> entries = await DatabaseHelper().getScheduleEntries(dateKey);
    setState(() {
      _schedule = entries;
      _selectedIndex = null; // сброс выбранного элемента при загрузке нового расписания
    });
  }

  void _addScheduleEntry() {
    final TextEditingController timeController = TextEditingController();
    final TextEditingController shortNoteController = TextEditingController();
    List<DynamicFieldEntry> dynamicFields = [DynamicFieldEntry(key: 'Предмет', value: '')];
    String? timeError;

    showDialog(
      context: context,
      builder: (BuildContext outerContext) {
        return StatefulBuilder(
          builder: (BuildContext innerContext, void Function(void Function()) setStateDialog) {
            return AlertDialog(
              title: const Text('Добавить занятие'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: timeController,
                      decoration: InputDecoration(
                        labelText: 'Время (Формат HH:MM - HH:MM)',
                        errorText: timeError,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Динамические поля (отображаются в списке расписания)
                    Column(
                      children: dynamicFields.map((field) {
                        int fieldIndex = dynamicFields.indexOf(field);
                        return Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: field.keyController,
                                decoration: const InputDecoration(labelText: 'Поле'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 4,
                              child: TextField(
                                controller: field.valueController,
                                decoration: const InputDecoration(labelText: 'Значение'),
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
                            dynamicFields.add(DynamicFieldEntry(key: 'Новое поле', value: ''));
                          });
                        },
                        child: const Text('Добавить поле'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Многострочное поле для краткой заметки (для предпросмотра)
                    TextField(
                      controller: shortNoteController,
                      decoration: const InputDecoration(labelText: 'Краткая заметка'),
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    RegExp timeRegExp = RegExp(
                        r'^([01]\d|2[0-3]):[0-5]\d\s*-\s*([01]\d|2[0-3]):[0-5]\d$');
                    if (!timeRegExp.hasMatch(timeController.text.trim())) {
                      setStateDialog(() {
                        timeError = 'Неверный формат времени. Используйте HH:MM - HH:MM';
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
                      date: DateFormat('yyyy-MM-dd').format(_selectedDate),
                      note: shortNoteController.text.trim(), // краткая заметка
                      dynamicFieldsJson: jsonEncode(dynamicMap), // динамические поля
                    );
                    DatabaseHelper().insertScheduleEntry(newEntry).then((id) {
                      newEntry.id = id;
                      setState(() {
                        _schedule.add(newEntry);
                      });
                        showCustomToast("Занятие успешно создано", accentColor: Colors.green, fontSize: 18.0);
                        Navigator.of(outerContext).pop();
                    });
                    Navigator.of(outerContext).pop();
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

  void _editSchedule(int index) {
    ScheduleEntry entry = _schedule[index];
    TextEditingController timeController = TextEditingController(text: entry.time);
    TextEditingController shortNoteController = TextEditingController(text: entry.note ?? '');
    List<DynamicFieldEntry> dynamicFields = [];
    if (entry.dynamicFieldsJson != null && entry.dynamicFieldsJson!.isNotEmpty) {
      Map<String, dynamic> decoded = jsonDecode(entry.dynamicFieldsJson!);
      decoded.forEach((key, value) {
        dynamicFields.add(DynamicFieldEntry(key: key, value: value.toString()));
      });
    }

    showDialog(
      context: context,
      builder: (BuildContext outerContext) {
        return StatefulBuilder(
          builder: (BuildContext innerContext, void Function(void Function()) setStateDialog) {
            return AlertDialog(
              title: const Text('Редактировать занятие'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: timeController,
                      decoration: const InputDecoration(labelText: 'Время'),
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
                                decoration: const InputDecoration(labelText: 'Поле'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 4,
                              child: TextField(
                                controller: field.valueController,
                                decoration: const InputDecoration(labelText: 'Значение'),
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
                            dynamicFields.add(DynamicFieldEntry(key: 'Новое поле', value: ''));
                          });
                        },
                        child: const Text('Добавить поле'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Многострочное поле для краткой заметки
                    TextField(
                      controller: shortNoteController,
                      decoration: const InputDecoration(labelText: 'Краткая заметка'),
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
                        showCustomToast("Занятие успешно обновлено", accentColor: Colors.yellow, fontSize: 18.0);
                        Navigator.of(outerContext).pop();
                    });
                    Navigator.of(outerContext).pop();
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

  void _deleteScheduleEntry(int index) {
    DatabaseHelper().deleteScheduleEntry(_schedule[index].id!).then((_) {
      setState(() {
        _schedule.removeAt(index);
        _selectedIndex = null;
      });
      showCustomToast("Занятие успешно удалено", accentColor: Colors.red, fontSize: 18.0);
    });
  }

  void _showScheduleContextMenu(BuildContext context, int index, Offset position) async {
    final RenderBox? overlay = Overlay.of(context)?.context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    await showMenu(
      context: context,
      position: RelativeRect.fromRect(position & const Size(40, 40), Offset.zero & overlay.size),
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
    String selectedDateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    List<ScheduleEntry> filteredSchedule =
        _schedule.where((entry) => entry.date == selectedDateKey).toList();

    return Column(
      children: [
        WeeklyScheduleGrid(
          selectedDay: _selectedDate,
          onDaySelected: (day) {
            setState(() {
              _selectedDate = day;
              _selectedIndex = null; // сбрасываем выбранный элемент при смене дня
            });
            _loadSchedule();
          },
        ),
        Expanded(
          child: Row(
            children: [
              // Левый блок: список расписания
              Expanded(
                flex: 2,
                child: Container(
                  color: Colors.grey[900],
                  child: Column(
                    children: [
                      ElevatedButton(
                        onPressed: _addScheduleEntry,
                        child: const Text('Добавить интервал'),
                      ),
                      Expanded(
                        child: ListView.separated(
                          itemCount: filteredSchedule.length,
                          separatorBuilder: (context, index) => const Divider(color: Colors.cyan),
                          itemBuilder: (context, index) {
                            ScheduleEntry entry = filteredSchedule[index];
                            String dynamicFieldsDisplay = '';
                            if (entry.dynamicFieldsJson != null && entry.dynamicFieldsJson!.isNotEmpty) {
                              Map<String, dynamic> decoded = jsonDecode(entry.dynamicFieldsJson!);
                              dynamicFieldsDisplay = decoded.entries.map((e) => "${e.key}: ${e.value}").join(", ");
                            }
                            return GestureDetector(
                              onSecondaryTapDown: (details) {
                                _showScheduleContextMenu(context, _schedule.indexOf(entry), details.globalPosition);
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
                                    const VerticalDivider(color: Colors.cyan, thickness: 2),
                                    Expanded(
                                      flex: 5,
                                      child: Text(
                                        dynamicFieldsDisplay,
                                        style: const TextStyle(color: Colors.white70),
                                      ),
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  setState(() {
                                    _selectedIndex = _schedule.indexOf(entry);
                                  });
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Правый блок: предпросмотр краткой заметки
              Expanded(
                flex: 1,
                child: Container(
                  color: Colors.grey[850],
                  padding: const EdgeInsets.all(8),
                  alignment: Alignment.topLeft,
                  child: (_selectedIndex == null || _selectedIndex! >= _schedule.length)
                      ? const Text('Выберите занятие', style: TextStyle(color: Colors.white))
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
    );
  }
}

/// Экран заметок и папок с использованием БД для заметок
class NotesScreen extends StatefulWidget {
  NotesScreen({Key? key}) : super(key: key);
  @override
  _NotesScreenState createState() => _NotesScreenState();
}
class _NotesScreenState extends State<NotesScreen> {
  List<Note> _notes = [];
  List<Folder> _folders = [];
  int? _selectedNoteIndex;
  TextEditingController _titleController = TextEditingController();
  TextEditingController _contentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadNotes();
    _loadFolders();
  }

  Future<void> _loadNotes() async {
    List<Note> notesFromDb = await DatabaseHelper().getNotes();
    setState(() {
      _notes = notesFromDb;
    });
  }

  Future<void> _loadFolders() async {
    List<Folder> foldersFromDb = await DatabaseHelper().getFolders();
    setState(() {
      _folders = foldersFromDb;
    });
  }

  void _addNote() async {
    Note newNote = Note();
    int id = await DatabaseHelper().insertNote(newNote);
    newNote.id = id;
    setState(() {
      _notes.add(newNote);
      _selectedNoteIndex = _notes.length - 1;
    });
    showCustomToast("Заметка успешно создана", accentColor: Colors.green, fontSize: 18.0);
  }

  void _deleteNote(int index) async {
    if (_notes[index].id != null) {
      await DatabaseHelper().deleteNote(_notes[index].id!);
      setState(() {
        _notes.removeAt(index);
        _selectedNoteIndex = null;
      });
      showCustomToast("Заметка успешно удалена", accentColor: Colors.red, fontSize: 18.0);
    }
  }

  void _updateSelectedNote(String title, String content, [String? folder]) async {
    if (_selectedNoteIndex != null) {
      Note updatedNote = _notes[_selectedNoteIndex!];
      updatedNote.title = title;
      updatedNote.content = content;
      updatedNote.folder = folder;
      await DatabaseHelper().updateNote(updatedNote);
      setState(() {
        _notes[_selectedNoteIndex!] = updatedNote;
      });
    }
  }

  // Добавление новой папки через диалог
  void _addFolder() {
    TextEditingController folderController = TextEditingController();
    Color selectedColor = Colors.grey[700]!;
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext innerContext, void Function(void Function()) setStateDialog) {
            return AlertDialog(
              title: const Text('Создать папку'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: folderController,
                    decoration: const InputDecoration(labelText: 'Название папки'),
                  ),
                  const SizedBox(height: 10),
                  ColorPicker(
                    color: selectedColor,
                    onChanged: (color) {
                      setStateDialog(() {
                        selectedColor = color;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    if (folderController.text.trim().isNotEmpty) {
                      Folder newFolder = Folder(
                        name: folderController.text.trim(),
                        backgroundColor: selectedColor.value,
                      );
                      int id = await DatabaseHelper().insertFolder(newFolder);
                      newFolder.id = id;
                      setState(() {
                        _folders.add(newFolder);
                      });
                      showCustomToast("Папка успешно создана", accentColor: Colors.green, fontSize: 18.0);
                    }
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Создать'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Отмена'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _deleteFolder(int index) async {
    Folder folderToDelete = _folders[index];
    if (folderToDelete.id != null) {
      await DatabaseHelper().deleteFolder(folderToDelete.id!);
      setState(() {
        _folders.removeAt(index);
        // Обновляем заметки: если заметка принадлежала удалённой папке, сбрасываем значение
        for (var note in _notes) {
          if (note.folder == folderToDelete.name) {
            note.folder = null;
            DatabaseHelper().updateNote(note);
          }
        }
      });
      showCustomToast("Папка успешно удалена", accentColor: Colors.red, fontSize: 18.0);
    }
  }

  void _editFolder(int index) {
    Folder folderToEdit = _folders[index];
    TextEditingController nameController = TextEditingController(text: folderToEdit.name);
    Color selectedColor = Color(folderToEdit.backgroundColor);
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext innerContext, void Function(void Function()) setStateDialog) {
            return AlertDialog(
              title: const Text('Редактировать папку'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Название папки'),
                  ),
                  const SizedBox(height: 10),
                  ColorPicker(
                    color: selectedColor,
                    onChanged: (color) {
                      setStateDialog(() {
                        selectedColor = color;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    folderToEdit.name = nameController.text.trim();
                    folderToEdit.backgroundColor = selectedColor.value;
                    await DatabaseHelper().updateFolder(folderToEdit);
                    setState(() {
                      _folders[index] = folderToEdit;
                    });
                    showCustomToast("Папка успешно обновлена", accentColor: Colors.yellow, fontSize: 18.0);
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Сохранить'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Отмена'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showFolderContextMenu(BuildContext context, int index, Offset position) async {
    final RenderBox? overlay = Overlay.of(context)?.context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    await showMenu(
      context: context,
      position: RelativeRect.fromRect(position & const Size(40, 40), Offset.zero & overlay.size),
      items: [
        const PopupMenuItem<String>(value: 'edit', child: Text('Редактировать папку')),
        const PopupMenuItem<String>(value: 'delete', child: Text('Удалить папку')),
      ],
    ).then((value) {
      if (value == 'edit') {
        _editFolder(index);
      } else if (value == 'delete') {
        _deleteFolder(index);
      }
    });
  }

  void _showNoteContextMenu(BuildContext context, int index, Offset position) async {
    final RenderBox? overlay = Overlay.of(context)?.context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    await showMenu(
      context: context,
      position: RelativeRect.fromRect(position & const Size(40, 40), Offset.zero & overlay.size),
      items: [
        const PopupMenuItem<String>(value: 'delete', child: Text('Удалить заметку')),
      ],
    ).then((value) {
      if (value == 'delete') {
        _deleteNote(index);
      }
    });
  }

  void _selectNote(int index) {
    setState(() {
      _selectedNoteIndex = index;
      _titleController.text = _notes[_selectedNoteIndex!].title;
      _contentController.text = _notes[_selectedNoteIndex!].content;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Формируем список заметок: сначала без папок, затем группируем по папкам
    List<Widget> noteItems = [];
    List<Note> ungrouped = _notes.where((note) => note.folder == null).toList();
    if (ungrouped.isNotEmpty) {
      noteItems.add(const Padding(
        padding: EdgeInsets.all(8.0),
        child: Text('Без папки', style: TextStyle(color: Colors.white70, fontSize: 16)),
      ));
      noteItems.addAll(ungrouped.map((note) {
        int index = _notes.indexOf(note);
        return GestureDetector(
          onSecondaryTapDown: (details) => _showNoteContextMenu(context, index, details.globalPosition),
          child: ListTile(
            title: Text(note.title, style: const TextStyle(color: Colors.white70)),
            onTap: () => _selectNote(index),
          ),
        );
      }));
    }
    for (var folder in _folders) {
      noteItems.add(
        GestureDetector(
          onLongPressStart: (details) => _showFolderContextMenu(context, _folders.indexOf(folder), details.globalPosition),
          onSecondaryTapDown: (details) => _showFolderContextMenu(context, _folders.indexOf(folder), details.globalPosition),
          child: Container(
            color: Color(folder.backgroundColor).withOpacity(0.3),
            padding: const EdgeInsets.all(8),
            child: Text(folder.name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ),
      );
      List<Note> groupNotes = _notes.where((note) => note.folder == folder.name).toList();
      if (groupNotes.isNotEmpty) {
        noteItems.addAll(groupNotes.map((note) {
          int index = _notes.indexOf(note);
          return GestureDetector(
            onSecondaryTapDown: (details) => _showNoteContextMenu(context, index, details.globalPosition),
            child: ListTile(
              title: Text(note.title, style: const TextStyle(color: Colors.white70)),
              onTap: () => _selectNote(index),
            ),
          );
        }));
      }
    }
    return Row(
      children: [
        // Левый блок: список заметок с группировкой по папкам
        Container(
          width: 250,
          color: Colors.grey[900],
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text('Заметки', style: TextStyle(color: Colors.cyan[200], fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _addNote,
                    icon: const Icon(Icons.add),
                    label: const Text('Добавить'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _addFolder,
                    icon: const Icon(Icons.create_new_folder),
                    label: const Text('Папка'),
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(8),
                  children: noteItems,
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1, color: Colors.cyan),
        // Правый блок: редактирование выбранной заметки
        Expanded(
          child: Container(
            color: Colors.grey[850],
            padding: const EdgeInsets.all(16),
            child: _selectedNoteIndex == null
                ? const Center(child: Text('Выберите заметку или добавьте новую', style: TextStyle(color: Colors.white70, fontSize: 18)))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _titleController,
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          labelText: 'Заголовок',
                          labelStyle: TextStyle(color: Colors.cyan, fontSize: 16),
                          border: UnderlineInputBorder(),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _notes[_selectedNoteIndex!].title = value.isEmpty ? 'Без названия' : value;
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Text('Папка:', style: TextStyle(color: Colors.cyan, fontSize: 16)),
                          const SizedBox(width: 10),
                          DropdownButton<String?>(
                            value: _folders.any((folder) => folder.name == _notes[_selectedNoteIndex!].folder)
                                ? _notes[_selectedNoteIndex!].folder
                                : null,
                            hint: const Text("Без папки", style: TextStyle(color: Colors.white70)),
                            dropdownColor: Colors.grey[800],
                            items: [
                              const DropdownMenuItem<String?>(value: null, child: Text("Без папки")),
                              ..._folders.map((folder) => DropdownMenuItem<String?>(
                                    value: folder.name,
                                    child: Text(folder.name),
                                  )),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _notes[_selectedNoteIndex!].folder = value;
                              });
                              _updateSelectedNote(
                                _notes[_selectedNoteIndex!].title,
                                _notes[_selectedNoteIndex!].content,
                                value,
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: TextField(
                          controller: _contentController,
                          style: const TextStyle(color: Colors.white70, fontSize: 16),
                          decoration: const InputDecoration(
                            labelText: 'Содержимое',
                            labelStyle: TextStyle(color: Colors.cyan, fontSize: 16),
                            border: InputBorder.none,
                          ),
                          maxLines: null,
                          expands: true,
                          onChanged: (value) {
                            setState(() {
                              _notes[_selectedNoteIndex!].content = value;
                            });
                            _updateSelectedNote(
                              _notes[_selectedNoteIndex!].title,
                              value,
                              _notes[_selectedNoteIndex!].folder,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

/// Экран доски с использованием БД для заметок и соединений
class PinboardScreen extends StatefulWidget {
  PinboardScreen({Key? key}) : super(key: key);
  @override
  _PinboardScreenState createState() => _PinboardScreenState();
}
class _PinboardScreenState extends State<PinboardScreen> {
  List<PinboardNoteDB> _pinboardNotes = [];
  List<ConnectionDB> _connections = [];
  int? _selectedForConnection;

  @override
  void initState() {
    super.initState();
    _loadPinboardData();
  }

  Future<void> _loadPinboardData() async {
    List<PinboardNoteDB> notes = await DatabaseHelper().getPinboardNotes();
    List<ConnectionDB> connections = await DatabaseHelper().getConnections();
    setState(() {
      _pinboardNotes = notes;
      _connections = connections;
    });
  }

  void _addPinboardNote() {
    PinboardNoteDB newNote = PinboardNoteDB(
      posX: 20,
      posY: 20,
      title: 'Новая заметка',
      content: 'Содержимое заметки',
      backgroundColor: Colors.grey[700]!.value,
    );
    DatabaseHelper().insertPinboardNote(newNote).then((id) {
      newNote.id = id;
      setState(() {
        _pinboardNotes.add(newNote);
      });
      showCustomToast("Заметка на доске успешно создана", accentColor: Colors.green, fontSize: 18.0);
    });
  }

  void _deletePinboardNote(int id) {
    DatabaseHelper().deletePinboardNote(id).then((_) {
      setState(() {
        _pinboardNotes.removeWhere((note) => note.id == id);
        _connections.removeWhere((conn) => conn.fromId == id || conn.toId == id);
        if (_selectedForConnection == id) { _selectedForConnection = null; }
      });
      showCustomToast("Заметка на доске успешно удалена", accentColor: Colors.red, fontSize: 18.0);
    });
  }

  void _selectForConnection(int id) {
    setState(() {
      if (_selectedForConnection == id) {
        _selectedForConnection = null;
      } else {
        if (_selectedForConnection != null &&
            _selectedForConnection != id &&
            !_connections.any((conn) =>
                (conn.fromId == _selectedForConnection! && conn.toId == id) ||
                (conn.fromId == id && conn.toId == _selectedForConnection!))) {
          ConnectionDB newConn = ConnectionDB(fromId: _selectedForConnection!, toId: id);
          DatabaseHelper().insertConnection(newConn).then((_) {
            _loadPinboardData();
          });
          _selectedForConnection = null;
        } else {
          _selectedForConnection = id;
        }
      }
    });
  }

  void _editPinboardNote(int id) {
    int index = _pinboardNotes.indexWhere((note) => note.id == id);
    if (index == -1) {
      print('Заметка с id $id не найдена для редактирования');
      return;
    }
    TextEditingController editTitleController = TextEditingController(text: _pinboardNotes[index].title);
    TextEditingController editContentController = TextEditingController(text: _pinboardNotes[index].content);
    Color selectedColor = Color(_pinboardNotes[index].backgroundColor);
    showDialog(
      context: context,
      builder: (BuildContext outerContext) {
        return StatefulBuilder(builder: (BuildContext innerContext, void Function(void Function()) setStateDialog) {
          return AlertDialog(
            title: const Text('Редактировать заметку'),
            content: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(controller: editTitleController, decoration: const InputDecoration(labelText: 'Заголовок')),
                  TextField(controller: editContentController, decoration: const InputDecoration(labelText: 'Содержимое'), maxLines: 5),
                  const SizedBox(height: 10),
                  const Text('Цвет фона:'),
                  ColorPicker(
                    color: selectedColor,
                    onChanged: (color) {
                      setStateDialog(() { selectedColor = color; });
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _pinboardNotes[index].title = editTitleController.text.isEmpty ? 'Без названия' : editTitleController.text;
                  _pinboardNotes[index].content = editContentController.text;
                  _pinboardNotes[index].backgroundColor = selectedColor.value;
                  DatabaseHelper().updatePinboardNote(_pinboardNotes[index]).then((_) {
                    setState(() {});
                  });
                  showCustomToast("Заметка на доске успешно обновлена", accentColor: Colors.yellow, fontSize: 18.0);
                  Navigator.of(outerContext).pop();
                },
                child: const Text('Сохранить'),
              ),
              TextButton(onPressed: () => Navigator.of(outerContext).pop(), child: const Text('Отмена')),
            ],
          );
        });
      },
    );
  }

  void _showNoteContextMenu(BuildContext context, PinboardNoteDB note, Offset position) async {
    final overlay = Overlay.of(context);
    if (overlay == null) return;
    final RenderBox overlayBox = overlay.context.findRenderObject() as RenderBox;
    try {
      await showMenu(
        context: context,
        position: RelativeRect.fromRect(position & const Size(40, 40), Offset.zero & overlayBox.size),
        items: [
          PopupMenuItem<String>(value: 'edit', child: const Text('Редактировать')),
          PopupMenuItem<String>(value: 'delete', child: const Text('Удалить')),
        ],
      ).then((value) {
        if (value == 'edit') { _editPinboardNote(note.id!); }
        else if (value == 'delete') { _deletePinboardNote(note.id!); }
      });
    } catch (e) {
      print('Ошибка при вызове контекстного меню: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[850],
      body: Stack(
        children: [
          CustomPaint(
            size: MediaQuery.of(context).size,
            painter: ConnectionPainter(notes: _pinboardNotes, connections: _connections),
          ),
          ..._pinboardNotes.map((note) {
            return Positioned(
              key: ValueKey(note.id),
              left: note.posX,
              top: note.posY,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    note.posX += details.delta.dx;
                    note.posY += details.delta.dy;
                  });
                  DatabaseHelper().updatePinboardNote(note);
                },
                onTap: () => _selectForConnection(note.id!),
                onSecondaryTapDown: (details) => _showNoteContextMenu(context, note, details.globalPosition),
                child: _buildNoteWidget(note, isSelected: _selectedForConnection == note.id),
              ),
            );
          }).toList(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addPinboardNote,
        tooltip: 'Добавить заметку на доску',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildNoteWidget(PinboardNoteDB note, {bool isSelected = false}) {
    return Container(
      width: 150,
      height: 150,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Color(note.backgroundColor),
        borderRadius: BorderRadius.circular(8),
        border: isSelected ? Border.all(color: Colors.cyan, width: 2) : null,
        boxShadow: [
          BoxShadow(color: Colors.black54, blurRadius: 4, offset: const Offset(2, 2)),
        ],
      ),
      child: Column(
        children: [
          Text(note.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Expanded(
            child: SingleChildScrollView(
              child: Text(note.content, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
            ),
          ),
        ],
      ),
    );
  }
}

/// Класс для отрисовки соединений между заметками на доске
class ConnectionPainter extends CustomPainter {
  final List<PinboardNoteDB> notes;
  final List<ConnectionDB> connections;
  ConnectionPainter({required this.notes, required this.connections});
  @override
  void paint(Canvas canvas, Size size) {
    try {
      final Map<int, PinboardNoteDB> notesMap = { for (var note in notes) note.id!: note };
      final paint = Paint()
        ..color = Colors.cyan
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      for (var connection in connections) {
        PinboardNoteDB? fromNote = notesMap[connection.fromId];
        PinboardNoteDB? toNote = notesMap[connection.toId];
        if (fromNote != null && toNote != null) {
          Offset from = Offset(fromNote.posX, fromNote.posY) + const Offset(75, 75);
          Offset to = Offset(toNote.posX, toNote.posY) + const Offset(75, 75);
          canvas.drawLine(from, to, paint);
        }
      }
    } catch (e) {
      print('Ошибка в ConnectionPainter: $e');
    }
  }
  @override
  bool shouldRepaint(covariant ConnectionPainter oldDelegate) {
    return oldDelegate.notes != notes || oldDelegate.connections != connections;
  }
}
