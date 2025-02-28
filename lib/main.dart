import 'package:flutter/material.dart';
import 'dart:math';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

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
    final path = join(databasePath, 'notes_app.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // Пример создания таблицы для заметок.
    await db.execute('''
      CREATE TABLE notes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        content TEXT,
        folder TEXT
      )
    ''');
  }

    // Метод для вставки новой заметки
  Future<int> insertNote(Note note) async {
    final db = await database;
    return await db.insert('notes', note.toMap());
  }

  // Метод для получения всех заметок
  Future<List<Note>> getNotes() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('notes');
    return List.generate(maps.length, (i) => Note.fromMap(maps[i]));
  }

  // Метод для обновления существующей заметки
  Future<int> updateNote(Note note) async {
    final db = await database;
    return await db.update(
      'notes',
      note.toMap(),
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  // Метод для удаления заметки по идентификатору
  Future<int> deleteNote(int id) async {
    final db = await database;
    return await db.delete(
      'notes',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

class WeeklyScheduleGrid extends StatelessWidget {
  final DateTime selectedDay;
  final ValueChanged<DateTime> onDaySelected;

  WeeklyScheduleGrid({required this.selectedDay, required this.onDaySelected});

  // Метод для вычисления дней текущей недели (начало – понедельник)
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
                  DateFormat('EEE', 'ru').format(day), // краткое название дня
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

/// Виджет выбора цвета с помощью слайдеров для R, G, B.
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

/// Класс для работы с динамическими полями в расписании.
class DynamicFieldEntry {
  TextEditingController keyController;
  TextEditingController valueController;
  DynamicFieldEntry({required String key, required String value})
      : keyController = TextEditingController(text: key),
        valueController = TextEditingController(text: value);
}

/// Модель заметки.
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


/// Модель папки.
class Folder {
  int? id;
  String name;
  int backgroundColor; // сохраняется в виде int (ARGB)

  Folder({
    this.id,
    required this.name,
    required this.backgroundColor,
  });

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

class ScheduleEntry {
  int? id;
  String time; // время в формате, например, "HH:MM - HH:MM"
  String date; // дата в формате "yyyy-MM-dd"
  String? note;
  String? dynamicFieldsJson; // дополнительные поля, сериализованные в JSON

  ScheduleEntry({
    this.id,
    required this.time,
    required this.date,
    this.note,
    this.dynamicFieldsJson,
  });

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

class PinboardNote {
  int? id;
  String title;
  String content;
  double posX;
  double posY;
  int backgroundColor; // сохраняется в виде int (ARGB)

  PinboardNote({
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

  factory PinboardNote.fromMap(Map<String, dynamic> map) {
    return PinboardNote(
      id: map['id'],
      title: map['title'],
      content: map['content'],
      posX: map['posX'],
      posY: map['posY'],
      backgroundColor: map['backgroundColor'],
    );
  }
}

class Connection {
  int? id;
  int fromId;
  int toId;

  Connection({
    this.id,
    required this.fromId,
    required this.toId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fromId': fromId,
      'toId': toId,
    };
  }

  factory Connection.fromMap(Map<String, dynamic> map) {
    return Connection(
      id: map['id'],
      fromId: map['fromId'],
      toId: map['toId'],
    );
  }
}


void main() async{
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper().database; // Инициализация базы данных
  await initializeDateFormatting('ru', null); // Инициализация данных для русской локали
  runApp(const NotesApp());
}

class NotesApp extends StatelessWidget {
  const NotesApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notes App',
      theme: ThemeData.dark(),
      home: const MainScreen(),
    );
  }
}

/// Главное окно с NavigationRail для выбора между режимами: Расписание, Заметки, Доска.
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

//
// Окно расписания
//
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
    // Формируем ключ даты для выборки записей
    String dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    List<ScheduleEntry> entries = await DatabaseHelper().getScheduleEntries(dateKey);
    setState(() {
      _schedule = entries;
    });
  }

  @override
  Widget build(BuildContext context) {
    final String selectedDateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    // Фильтрация расписания по выбранной дате
    final List<Map<String, String>> filteredSchedule =
        _schedule.where((entry) => entry['date'] == selectedDateKey).toList();

    return Column(
      children: [
        WeeklyScheduleGrid(
          selectedDay: _selectedDate,
          onDaySelected: (day) {
            setState(() {
              _selectedDate = day;
            });
          },
        ),
        Expanded(
          child: Row(
            children: [
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
                          separatorBuilder: (context, index) =>
                              const Divider(color: Colors.cyan),
                          itemBuilder: (context, index) {
                            // Поиск исходного индекса в полном списке _schedule
                            int originalIndex =
                                _schedule.indexOf(filteredSchedule[index]);
                            return GestureDetector(
                              onSecondaryTapDown: (details) {
                                _showScheduleContextMenu(
                                    context,
                                    originalIndex,
                                    details.globalPosition);
                              },
                              child: ListTile(
                                title: Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        filteredSchedule[index]['time'] ?? '',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const VerticalDivider(
                                        color: Colors.cyan, thickness: 2),
                                    Expanded(
                                      flex: 5,
                                      child: Text(
                                        '${filteredSchedule[index]['Предмет'] ?? ''} - ${filteredSchedule[index].keys.where((k) => k != 'time' && k != 'note' && k != 'date').map((k) => "$k: ${filteredSchedule[index][k]}").join(", ")}',
                                        style: const TextStyle(
                                            color: Colors.white70),
                                      ),
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  setState(() {
                                    _selectedIndex =
                                        _schedule.indexOf(filteredSchedule[index]);
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
              Expanded(
                flex: 1,
                child: Container(
                  color: Colors.grey[850],
                  padding: const EdgeInsets.all(8),
                  alignment: Alignment.topLeft,
                  child: _selectedIndex == null
                      ? const Text('Выберите занятие',
                          style: TextStyle(color: Colors.white))
                      : SingleChildScrollView(
                          child: Text(
                            _schedule[_selectedIndex!]['note'] ?? '',
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

  void _addScheduleEntry() {
  final TextEditingController timeController = TextEditingController();
  // Изначально добавляем одно динамическое поле "Предмет"
  List<DynamicFieldEntry> dynamicFields = [DynamicFieldEntry(key: 'Предмет', value: '')];
  String? timeError;

  showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setStateDialog) {
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
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  // Проверка формата времени
                  RegExp timeRegExp = RegExp(r'^([01]\d|2[0-3]):[0-5]\d\s*-\s*([01]\d|2[0-3]):[0-5]\d$');
                  if (!timeRegExp.hasMatch(timeController.text.trim())) {
                    setStateDialog(() {
                      timeError = 'Неверный формат времени. Используйте HH:MM - HH:MM';
                    });
                    return;
                  }
                  // Формируем новый пункт расписания с автоматически добавленной датой
                  Map<String, String> newEntry = {
                    'time': timeController.text.trim(),
                    'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
                  };
                  for (var field in dynamicFields) {
                    String key = field.keyController.text.trim();
                    if (key.isNotEmpty) {
                      newEntry[key] = field.valueController.text;
                    }
                  }
                  setState(() {
                    _schedule.add(newEntry);
                  });
                  Navigator.of(context).pop();
                },
                child: const Text('Сохранить'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
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
  TextEditingController timeController = TextEditingController(text: _schedule[index]['time']);
  TextEditingController noteController = TextEditingController(text: _schedule[index]['note'] ?? '');
  List<DynamicFieldEntry> dynamicFields = [];

  // Итерируемся по ключам, исключая 'time' и 'note'
  _schedule[index].forEach((key, value) {
    if (key != 'time' && key != 'note') {
      dynamicFields.add(DynamicFieldEntry(key: key, value: value));
    }
  });

  showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setStateDialog) {
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
                  // Отображаем все динамические поля, включая поле "Предмет", если оно существует
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
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(labelText: 'Заметка'),
                    maxLines: 3,
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
                  setState(() {
                    _schedule[index] = {
                      'time': timeController.text,
                      'note': noteController.text,
                      ...dynamicMap,
                    };
                  });
                  Navigator.of(context).pop();
                },
                child: const Text('Сохранить'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
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
    setState(() {
      _schedule.removeAt(index);
      _selectedIndex = null;
    });
  }
  void _showScheduleContextMenu(BuildContext context, int index, Offset position) async {
    final RenderBox? overlay = Overlay.of(context)?.context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    await showMenu(
      context: context,
      position: RelativeRect.fromRect(position & const Size(40, 40), Offset.zero & overlay.size),
      items: [
        const PopupMenuItem<String>(value: 'edit', child: Text('Редактировать')),
        const PopupMenuItem<String>(value: 'delete', child: Text('Удалить')),
      ],
    ).then((value) {
      if (value == 'edit') { _editSchedule(index); }
      else if (value == 'delete') { _deleteScheduleEntry(index); }
    });
  }
}

//
// Окно заметок и папок
//
class NotesScreen extends StatefulWidget {
  NotesScreen({Key? key}) : super(key: key);
  @override
  _NotesScreenState createState() => _NotesScreenState();
}
class _NotesScreenState extends State<NotesScreen> {
  List<Note> _notes = [];
  int? _selectedNoteIndex;
  List<Folder> _folders = [];
  TextEditingController _titleController = TextEditingController();
  TextEditingController _contentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    List<Note> notesFromDb = await DatabaseHelper().getNotes();
    setState(() {
      _notes = notesFromDb;
    });
  }

  void _addNote() async {
    Note newNote = Note();
    // Сохраняем заметку в БД и получаем присвоенный id
    int id = await DatabaseHelper().insertNote(newNote);
    newNote.id = id;
    setState(() {
      _notes.add(newNote);
      _selectedNoteIndex = _notes.length - 1;
    });
  }

  void _deleteNote(int index) async {
    // Удаляем заметку по id
    await DatabaseHelper().deleteNote(_notes[index].id!);
    setState(() {
      _notes.removeAt(index);
      _selectedNoteIndex = null;
    });
  }

  void _updateSelectedNote(String title, String content) async {
    if (_selectedNoteIndex != null) {
      Note updatedNote = _notes[_selectedNoteIndex!];
      updatedNote.title = title;
      updatedNote.content = content;
      // Обновляем запись в БД
      await DatabaseHelper().updateNote(updatedNote);
      setState(() {
        _notes[_selectedNoteIndex!] = updatedNote;
      });
    }
  }

  // Удаление заметки через контекстное меню (правый клик)
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
      if (value == 'delete') { _deleteNote(index); }
    });
  }

  void _selectNote(int index) {
    setState(() {
      _selectedNoteIndex = index;
      _titleController.text = _notes[_selectedNoteIndex!].title;
      _contentController.text = _notes[_selectedNoteIndex!].content;
    });
  }
  void _addFolder() {
    TextEditingController folderController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Создать папку'),
          content: TextField(
            controller: folderController,
            decoration: const InputDecoration(labelText: 'Название папки'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (folderController.text.trim().isNotEmpty) {
                  setState(() {
                    _folders.add(Folder(
                      name: folderController.text.trim(),
                      backgroundColor: Colors.grey[700]!,
                    ));
                  });
                }
                Navigator.of(context).pop();
              },
              child: const Text('Создать'),
            ),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
          ],
        );
      },
    );
  }
  void _deleteFolder(int index) {
    // При удалении папки все заметки из неё становятся "без папки"
    String folderName = _folders[index].name;
    setState(() {
      for (var note in _notes) {
        if (note.folder == folderName) {
          note.folder = null;
        }
      }
      _folders.removeAt(index);
    });
  }
  void _editFolder(int index) {
    TextEditingController nameController = TextEditingController(text: _folders[index].name);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Редактировать папку'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Название папки')),
              const SizedBox(height: 10),
              ColorPicker(
                color: _folders[index].backgroundColor,
                onChanged: (color) {
                  setState(() { _folders[index].backgroundColor = color; });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() { _folders[index].name = nameController.text.trim(); });
                Navigator.of(context).pop();
              },
              child: const Text('Сохранить'),
            ),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
          ],
        );
      },
    );
  }
  // Контекстное меню для папок через правый клик
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
      if (value == 'edit') { _editFolder(index); }
      else if (value == 'delete') { _deleteFolder(index); }
    });
  }
  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    // Формируем список виджетов: сначала заметки без папки, затем группируем заметки по папкам.
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
          onSecondaryTapDown: (details) { _showNoteContextMenu(context, index, details.globalPosition); },
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
          onLongPressStart: (details) { _showFolderContextMenu(context, _folders.indexOf(folder), details.globalPosition); },
          onSecondaryTapDown: (details) { _showFolderContextMenu(context, _folders.indexOf(folder), details.globalPosition); },
          child: Container(
            color: folder.backgroundColor.withOpacity(0.3),
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
            onSecondaryTapDown: (details) { _showNoteContextMenu(context, index, details.globalPosition); },
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
        // Левый блок: список заметок с группировкой по папкам.
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
                  ElevatedButton.icon(onPressed: _addNote, icon: const Icon(Icons.add), label: const Text('Добавить')),
                  ElevatedButton.icon(onPressed: _addFolder, icon: const Icon(Icons.create_new_folder), label: const Text('Папка')),
                ],
              ),
              Expanded(child: ListView(padding: const EdgeInsets.all(8), children: noteItems)),
            ],
          ),
        ),
        const VerticalDivider(width: 1, color: Colors.cyan),
        // Правый блок: редактирование выбранной заметки.
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
                              ..._folders.map((folder) => DropdownMenuItem<String?>(value: folder.name, child: Text(folder.name))),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _notes[_selectedNoteIndex!].folder = value;
                              });
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

//
// Окно доски (Pinboard)
//
class PinboardNote {
  final int id;
  String title;
  String content;
  Offset position;
  Color backgroundColor;
  PinboardNote({
    required this.id,
    this.title = 'Без названия',
    this.content = '',
    this.position = const Offset(20, 20),
    Color? backgroundColor,
  }) : backgroundColor = backgroundColor ?? Colors.grey[700]!;
}
class Connection {
  final int fromId;
  final int toId;
  Connection({required this.fromId, required this.toId});
}
class PinboardScreen extends StatefulWidget {
  PinboardScreen({Key? key}) : super(key: key);
  @override
  _PinboardScreenState createState() => _PinboardScreenState();
}
class _PinboardScreenState extends State<PinboardScreen> {
  final List<PinboardNote> _pinboardNotes = [];
  final List<Connection> _connections = [];
  int _nextId = 0;
  int? _selectedForConnection;
  void _addPinboardNote() {
    setState(() {
      _pinboardNotes.add(PinboardNote(
        id: _nextId++,
        title: 'Новая заметка',
        content: 'Содержимое заметки',
        position: const Offset(20, 20),
      ));
    });
  }
  void _deletePinboardNote(int id) {
    setState(() {
      _pinboardNotes.removeWhere((note) => note.id == id);
      _connections.removeWhere((connection) => connection.fromId == id || connection.toId == id);
      if (_selectedForConnection == id) { _selectedForConnection = null; }
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
          _connections.add(Connection(fromId: _selectedForConnection!, toId: id));
          _selectedForConnection = null;
        } else {
          _selectedForConnection = id;
        }
      }
    });
  }
  void _updatePosition(int id, Offset newPosition) {
    try {
      setState(() {
        int index = _pinboardNotes.indexWhere((note) => note.id == id);
        if (index != -1) {
          _pinboardNotes[index].position = newPosition;
        }
      });
    } catch (e) {
      print('Ошибка при обновлении позиции заметки: $e');
    }
  }
  void _editPinboardNote(int id) {
    int index = _pinboardNotes.indexWhere((note) => note.id == id);
    if (index == -1) {
      print('Заметка с id $id не найдена для редактирования');
      return;
    }
    TextEditingController editTitleController = TextEditingController(text: _pinboardNotes[index].title);
    TextEditingController editContentController = TextEditingController(text: _pinboardNotes[index].content);
    Color selectedColor = _pinboardNotes[index].backgroundColor;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setStateDialog) {
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
                  setState(() {
                    _pinboardNotes[index].title = editTitleController.text.isEmpty ? 'Без названия' : editTitleController.text;
                    _pinboardNotes[index].content = editContentController.text;
                    _pinboardNotes[index].backgroundColor = selectedColor;
                  });
                  Navigator.of(context).pop();
                },
                child: const Text('Сохранить'),
              ),
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
            ],
          );
        });
      },
    );
  }
  void _showNoteContextMenu(BuildContext context, PinboardNote note, Offset position) async {
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
        if (value == 'edit') { _editPinboardNote(note.id); }
        else if (value == 'delete') { _deletePinboardNote(note.id); }
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
              left: note.position.dx,
              top: note.position.dy,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    note.position += details.delta;
                    note.position = Offset(
                      note.position.dx.clamp(0.0, MediaQuery.of(context).size.width - 150),
                      note.position.dy.clamp(0.0, MediaQuery.of(context).size.height - 150),
                    );
                  });
                },
                onTap: () => _selectForConnection(note.id),
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
  Widget _buildNoteWidget(PinboardNote note, {bool isSelected = false}) {
    return Container(
      width: 150,
      height: 150,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: note.backgroundColor,
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

class ConnectionPainter extends CustomPainter {
  final List<PinboardNote> notes;
  final List<Connection> connections;
  ConnectionPainter({required this.notes, required this.connections});
  @override
  void paint(Canvas canvas, Size size) {
    try {
      final Map<int, PinboardNote> notesMap = { for (var note in notes) note.id: note };
      final paint = Paint()
        ..color = Colors.cyan
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      for (var connection in connections) {
        PinboardNote? fromNote = notesMap[connection.fromId];
        PinboardNote? toNote = notesMap[connection.toId];
        if (fromNote != null && toNote != null) {
          Offset from = fromNote.position + const Offset(75, 75);
          Offset to = toNote.position + const Offset(75, 75);
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
