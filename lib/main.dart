import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:oktoast/oktoast.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';

IconData getIconData(String iconKey) {
  switch (iconKey) {
    case 'person':
      return Icons.person;
    case 'check':
      return Icons.check;
    case 'tree':
      return Icons.park; // или Icons.park – по вашему выбору
    case 'home':
      return Icons.home;
    case 'car':
      return Icons.directions_car;
    case 'close':
      return Icons.close;
    default:
      return Icons.help_outline;
  }
}

// Добавьте этот фрагмент в начало файла main.dart (после импортов),
// чтобы функция была доступна во всём приложении.
void showCustomToastWithIcon(String message,
    {Color accentColor = Colors.green, double fontSize = 14.0, Widget? icon}) {
  Future.delayed(const Duration(milliseconds: 300), () {
    try {
      showToastWidget(
        Align(
          alignment: Alignment.bottomRight,
          child: Container(
            margin: const EdgeInsets.only(right: 20, bottom: 20),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 41, 41, 41).withOpacity(0.8),
              borderRadius: BorderRadius.circular(8),
            ),
            constraints: const BoxConstraints(maxWidth: 250),
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
                // Если задана иконка, выводим Row с иконкой и текстом
                icon != null
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          icon,
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              message,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: fontSize, color: Colors.white),
                            ),
                          ),
                        ],
                      )
                    : Text(
                        message,
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(fontSize: fontSize, color: Colors.white),
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

/// Виджет для отображения календарной сетки, масштабируемой под размер окна.
class CalendarGrid extends StatefulWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateSelected;

  const CalendarGrid({
    Key? key,
    required this.selectedDate,
    required this.onDateSelected,
  }) : super(key: key);

  @override
  _CalendarGridState createState() => _CalendarGridState();
}

class _CalendarGridState extends State<CalendarGrid> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    // Инициализируем собственный ScrollController
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    // Освобождаем ресурсы
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Текущее время и расчёт дней месяца
    DateTime now = DateTime.now();
    DateTime firstDay = DateTime(now.year, now.month, 1);
    DateTime lastDay = DateTime(now.year, now.month + 1, 0);
    int totalDays = lastDay.day;
    int startingWeekday =
        firstDay.weekday; // 1 = понедельник, ... 7 = воскресенье

    // Заголовок дней недели
    List<Widget> headerCells = [];
    List<String> weekDays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    for (String day in weekDays) {
      headerCells.add(
        Expanded(
          child: Container(
            alignment: Alignment.center,
            child: Text(
              day,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ),
      );
    }

    // Ячейки с числами
    List<Widget> dayCells = [];
    // Пустые ячейки до первого числа месяца
    for (int i = 1; i < startingWeekday; i++) {
      dayCells.add(Container());
    }
    // Добавляем ячейки для каждого дня месяца
    for (int d = 1; d <= totalDays; d++) {
      DateTime currentDay = DateTime(now.year, now.month, d);
      bool isSelected = currentDay.year == widget.selectedDate.year &&
          currentDay.month == widget.selectedDate.month &&
          currentDay.day == widget.selectedDate.day;

      dayCells.add(
        GestureDetector(
          onTap: () => widget.onDateSelected(currentDay),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: isSelected ? Colors.cyan : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: Text(
              d.toString(),
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? Colors.black : Colors.white,
              ),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Определяем ширину для расчёта размера ячеек
        double width = (constraints.hasBoundedWidth &&
                constraints.maxWidth != double.infinity)
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;

        if (width <= 0) return Container();
        double cellSize = width / 7;

        return Column(
          children: [
            // Заголовок дней недели (одна строка)
            Container(
              height: cellSize,
              child: Row(children: headerCells),
            ),
            // Прокручиваемая сетка для дней
            Expanded(
              child: Scrollbar(
                controller: _scrollController, // привязываем ScrollController
                thumbVisibility:
                    true, // чтобы полоса прокрутки всегда была видна (по желанию)
                child: GridView.builder(
                  controller:
                      _scrollController, // передаём контроллер в GridView
                  padding: EdgeInsets.zero,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    childAspectRatio: 1, // квадратные ячейки
                  ),
                  itemCount: dayCells.length,
                  itemBuilder: (context, index) {
                    return dayCells[index];
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
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
        backgroundColor INTEGER,
        icon TEXT
      )
    ''');

    // Таблица соединений заметок
    await db.execute('''
      CREATE TABLE connections(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fromId INTEGER,
        toId INTEGER,
        name TEXT,
        connectionColor INTEGER
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
    return await db
        .update('notes', note.toMap(), where: 'id = ?', whereArgs: [note.id]);
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

  Future<int> updateConnection(ConnectionDB connection) async {
    final db = await database;
    return await db.update(
      'connections',
      connection.toMap(),
      where: 'id = ?',
      whereArgs: [connection.id],
    );
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
  ScheduleEntry(
      {this.id,
      required this.time,
      required this.date,
      this.note,
      this.dynamicFieldsJson});
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
  String icon; // новое поле

  PinboardNoteDB({
    this.id,
    this.title = 'Без названия',
    this.content = '',
    required this.posX,
    required this.posY,
    required this.backgroundColor,
    this.icon = 'person', // дефолтное значение
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'posX': posX,
      'posY': posY,
      'backgroundColor': backgroundColor,
      'icon': icon, // сохраняем значок
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
      icon: map['icon'] ?? 'person',
    );
  }
}

/// Модель соединения заметок (для работы с БД)
class ConnectionDB {
  int? id;
  int fromId;
  int toId;
  String name;
  int connectionColor; // цвет в формате ARGB

  ConnectionDB({
    this.id,
    required this.fromId,
    required this.toId,
    this.name = "",
    this.connectionColor = 0xFF00FFFF, // например, дефолтный – ярко-циановый
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fromId': fromId,
      'toId': toId,
      'name': name,
      'connectionColor': connectionColor,
    };
  }

  factory ConnectionDB.fromMap(Map<String, dynamic> map) {
    return ConnectionDB(
      id: map['id'],
      fromId: map['fromId'],
      toId: map['toId'],
      name: map['name'] ?? "",
      connectionColor: map['connectionColor'] ?? 0xFF00FFFF,
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
    setState(() {
      _selectedIndex = index;
    });
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
              NavigationRailDestination(
                  icon: Icon(Icons.schedule), label: Text('Расписание')),
              NavigationRailDestination(
                  icon: Icon(Icons.note), label: Text('Заметки')),
              NavigationRailDestination(
                  icon: Icon(Icons.dashboard), label: Text('Доска')),
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
/// Экран расписания, который сначала показывает календарь, а затем — детальный режим для выбранного дня.
/// Экран расписания. Если день не выбран (_selectedDate == null), показывается календарная сетка.
/// Если выбран день, отображается детальный режим с интервалами и предпросмотром заметки.
class ScheduleScreen extends StatefulWidget {
  ScheduleScreen({Key? key}) : super(key: key);

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
    showCustomToastWithIcon(
      "Заметка успешно создана",
      accentColor: Colors.green,
      fontSize: 14.0,
      icon: const Icon(Icons.check, size: 20, color: Colors.green),
    );
  }

  void _deleteNote(int index) async {
    if (_notes[index].id != null) {
      await DatabaseHelper().deleteNote(_notes[index].id!);
      setState(() {
        _notes.removeAt(index);
        _selectedNoteIndex = null;
      });
      showCustomToastWithIcon(
        "Заметка успешно удалена",
        accentColor: Colors.red,
        fontSize: 14.0,
        icon: const Icon(Icons.close, size: 20, color: Colors.red),
      );
    }
  }

  void _updateSelectedNote(String title, String content,
      [String? folder]) async {
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
          builder: (BuildContext innerContext,
              void Function(void Function()) setStateDialog) {
            return AlertDialog(
              title: const Text('Создать папку'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: folderController,
                    decoration:
                        const InputDecoration(labelText: 'Название папки'),
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
                      showCustomToastWithIcon(
                        "Папка успешно создана",
                        accentColor: Colors.green,
                        fontSize: 14.0,
                        icon: const Icon(Icons.check,
                            size: 20, color: Colors.green),
                      );
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
      showCustomToastWithIcon(
        "Папка успешно удалена",
        accentColor: Colors.red,
        fontSize: 14.0,
        icon: const Icon(Icons.close, size: 20, color: Colors.red),
      );
    }
  }

  void _editFolder(int index) {
    Folder folderToEdit = _folders[index];
    TextEditingController nameController =
        TextEditingController(text: folderToEdit.name);
    Color selectedColor = Color(folderToEdit.backgroundColor);
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext innerContext,
              void Function(void Function()) setStateDialog) {
            return AlertDialog(
              title: const Text('Редактировать папку'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration:
                        const InputDecoration(labelText: 'Название папки'),
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
                    showCustomToastWithIcon(
                      "Папка успешно обновлена",
                      accentColor: Colors.yellow,
                      fontSize: 14.0,
                      icon: const Icon(Icons.error_outline,
                          size: 20, color: Colors.yellow),
                    );
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

  void _showFolderContextMenu(
      BuildContext context, int index, Offset position) async {
    final RenderBox? overlay =
        Overlay.of(context)?.context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    await showMenu(
      context: context,
      position: RelativeRect.fromRect(
          position & const Size(40, 40), Offset.zero & overlay.size),
      items: [
        const PopupMenuItem<String>(
            value: 'edit', child: Text('Редактировать папку')),
        const PopupMenuItem<String>(
            value: 'delete', child: Text('Удалить папку')),
      ],
    ).then((value) {
      if (value == 'edit') {
        _editFolder(index);
      } else if (value == 'delete') {
        _deleteFolder(index);
      }
    });
  }

  void _showNoteContextMenu(
      BuildContext context, int index, Offset position) async {
    final RenderBox? overlay =
        Overlay.of(context)?.context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    await showMenu(
      context: context,
      position: RelativeRect.fromRect(
          position & const Size(40, 40), Offset.zero & overlay.size),
      items: [
        const PopupMenuItem<String>(
            value: 'delete', child: Text('Удалить заметку')),
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
        child: Text('Без папки',
            style: TextStyle(color: Colors.white70, fontSize: 16)),
      ));
      noteItems.addAll(ungrouped.map((note) {
        int index = _notes.indexOf(note);
        return GestureDetector(
          onSecondaryTapDown: (details) =>
              _showNoteContextMenu(context, index, details.globalPosition),
          child: ListTile(
            title:
                Text(note.title, style: const TextStyle(color: Colors.white70)),
            onTap: () => _selectNote(index),
          ),
        );
      }));
    }
    for (var folder in _folders) {
      noteItems.add(
        GestureDetector(
          onLongPressStart: (details) => _showFolderContextMenu(
              context, _folders.indexOf(folder), details.globalPosition),
          onSecondaryTapDown: (details) => _showFolderContextMenu(
              context, _folders.indexOf(folder), details.globalPosition),
          child: Container(
            color: Color(folder.backgroundColor).withOpacity(0.3),
            padding: const EdgeInsets.all(8),
            child: Text(folder.name,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
          ),
        ),
      );
      List<Note> groupNotes =
          _notes.where((note) => note.folder == folder.name).toList();
      if (groupNotes.isNotEmpty) {
        noteItems.addAll(groupNotes.map((note) {
          int index = _notes.indexOf(note);
          return GestureDetector(
            onSecondaryTapDown: (details) =>
                _showNoteContextMenu(context, index, details.globalPosition),
            child: ListTile(
              title: Text(note.title,
                  style: const TextStyle(color: Colors.white70)),
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
                child: Text('Заметки',
                    style: TextStyle(
                        color: Colors.cyan[200],
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
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
                ? const Center(
                    child: Text('Выберите заметку или добавьте новую',
                        style: TextStyle(color: Colors.white70, fontSize: 18)))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _titleController,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          labelText: 'Заголовок',
                          labelStyle:
                              TextStyle(color: Colors.cyan, fontSize: 16),
                          border: UnderlineInputBorder(),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _notes[_selectedNoteIndex!].title =
                                value.isEmpty ? 'Без названия' : value;
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Text('Папка:',
                              style:
                                  TextStyle(color: Colors.cyan, fontSize: 16)),
                          const SizedBox(width: 10),
                          DropdownButton<String?>(
                            value: _folders.any((folder) =>
                                    folder.name ==
                                    _notes[_selectedNoteIndex!].folder)
                                ? _notes[_selectedNoteIndex!].folder
                                : null,
                            hint: const Text("Без папки",
                                style: TextStyle(color: Colors.white70)),
                            dropdownColor: Colors.grey[800],
                            items: [
                              const DropdownMenuItem<String?>(
                                  value: null, child: Text("Без папки")),
                              ..._folders
                                  .map((folder) => DropdownMenuItem<String?>(
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
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 16),
                          decoration: const InputDecoration(
                            labelText: 'Содержимое',
                            labelStyle:
                                TextStyle(color: Colors.cyan, fontSize: 16),
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
      showCustomToastWithIcon(
        "Заметка на доске успешно создана",
        accentColor: Colors.green,
        fontSize: 14.0,
        icon: const Icon(Icons.check, size: 20, color: Colors.green),
      );
    });
  }

  void _deletePinboardNote(int id) {
    DatabaseHelper().deletePinboardNote(id).then((_) {
      setState(() {
        _pinboardNotes.removeWhere((note) => note.id == id);
        _connections
            .removeWhere((conn) => conn.fromId == id || conn.toId == id);
        if (_selectedForConnection == id) {
          _selectedForConnection = null;
        }
      });
      showCustomToastWithIcon(
        "Заметка на доске успешно удалена",
        accentColor: Colors.red,
        fontSize: 14.0,
        icon: const Icon(Icons.close, size: 20, color: Colors.red),
      );
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
          ConnectionDB newConn =
              ConnectionDB(fromId: _selectedForConnection!, toId: id);
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
    TextEditingController editTitleController =
        TextEditingController(text: _pinboardNotes[index].title);
    TextEditingController editContentController =
        TextEditingController(text: _pinboardNotes[index].content);
    // Значение выбранного значка
    String selectedIcon = _pinboardNotes[index].icon;
    // Выбор цвета заметки осуществляется с помощью существующего ColorPicker
    Color selectedColor = Color(_pinboardNotes[index].backgroundColor);
    showDialog(
      context: context,
      builder: (BuildContext outerContext) {
        return StatefulBuilder(
          builder: (BuildContext innerContext,
              void Function(void Function()) setStateDialog) {
            return AlertDialog(
              title: const Text('Редактировать заметку'),
              content: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(
                      controller: editTitleController,
                      decoration: const InputDecoration(labelText: 'Заголовок'),
                    ),
                    TextField(
                      controller: editContentController,
                      decoration:
                          const InputDecoration(labelText: 'Содержимое'),
                      maxLines: 5,
                    ),
                    const SizedBox(height: 10),
                    const Text('Выберите значок:'),
                    Wrap(
                      spacing: 8,
                      children: [
                        'person',
                        'check',
                        'tree',
                        'home',
                        'car',
                        'close'
                      ].map((iconKey) {
                        return ChoiceChip(
                          label: Icon(getIconData(iconKey),
                              size: 20, color: Colors.white),
                          selected: selectedIcon == iconKey,
                          onSelected: (selected) {
                            setStateDialog(() {
                              selectedIcon = iconKey;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    const Text('Выберите цвет заметки:'),
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
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _pinboardNotes[index].title =
                        editTitleController.text.isEmpty
                            ? 'Без названия'
                            : editTitleController.text;
                    _pinboardNotes[index].content = editContentController.text;
                    _pinboardNotes[index].backgroundColor = selectedColor.value;
                    _pinboardNotes[index].icon =
                        selectedIcon; // сохраняем выбранный значок
                    DatabaseHelper()
                        .updatePinboardNote(_pinboardNotes[index])
                        .then((_) {
                      setState(() {});
                    });
                    showCustomToastWithIcon(
                      "Заметка на доске успешно обновлена",
                      accentColor: Colors.yellow,
                      fontSize: 14.0,
                      icon: const Icon(Icons.error_outline,
                          size: 20, color: Colors.yellow),
                    );
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

  void _showNoteContextMenu(
      BuildContext context, PinboardNoteDB note, Offset position) async {
    final overlay = Overlay.of(context);
    if (overlay == null) return;
    final RenderBox overlayBox =
        overlay.context.findRenderObject() as RenderBox;
    try {
      await showMenu(
        context: context,
        position: RelativeRect.fromRect(
            position & const Size(40, 40), Offset.zero & overlayBox.size),
        items: [
          PopupMenuItem<String>(
              value: 'edit', child: const Text('Редактировать')),
          PopupMenuItem<String>(value: 'delete', child: const Text('Удалить')),
        ],
      ).then((value) {
        if (value == 'edit') {
          _editPinboardNote(note.id!);
        } else if (value == 'delete') {
          _deletePinboardNote(note.id!);
        }
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
            painter: ConnectionPainter(
                notes: _pinboardNotes, connections: _connections),
          ),
          // Заметки на доске (как ранее)
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
                onSecondaryTapDown: (details) =>
                    _showNoteContextMenu(context, note, details.globalPosition),
                child: _buildNoteWidget(note,
                    isSelected: _selectedForConnection == note.id),
              ),
            );
          }).toList(),
          // Оверлеи для редактирования связей
          ..._buildConnectionOverlays(),
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
      width: 180,
      height: 150,
      decoration: BoxDecoration(
        border: Border.all(
          color: isSelected ? Colors.cyan : Colors.transparent,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Левая панель для значка с фиксированным темным фоном
          Container(
            width: 30,
            height: double.infinity,
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.black, // фиксированный темный фон
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Icon(
                getIconData(note.icon),
                size: 20,
                color: Color(note
                    .backgroundColor), // значок окрашивается по выбранному цвету
              ),
            ),
          ),
          // Правая панель с основным содержимым заметки и фоном, равным выбранному цвету
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color:
                    Color(note.backgroundColor), // фон заметки – выбранный цвет
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Text(
                        note.content,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildConnectionOverlays() {
    List<Widget> overlays = [];
    final Map<int, PinboardNoteDB> notesMap = {
      for (var note in _pinboardNotes) note.id!: note
    };
    for (var connection in _connections) {
      PinboardNoteDB? fromNote = notesMap[connection.fromId];
      PinboardNoteDB? toNote = notesMap[connection.toId];
      if (fromNote != null && toNote != null) {
        Offset from =
            Offset(fromNote.posX, fromNote.posY) + const Offset(75, 75);
        Offset to = Offset(toNote.posX, toNote.posY) + const Offset(75, 75);
        Offset midpoint = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
        overlays.add(
          Positioned(
            // Располагаем контейнер так, чтобы его центр был в середине линии связи
            left: midpoint.dx,
            top: midpoint.dy,
            child: GestureDetector(
              onTap: () => _editConnection(connection),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  connection.name,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        );
      }
    }
    return overlays;
  }

  void _editConnection(ConnectionDB connection) {
    TextEditingController nameController =
        TextEditingController(text: connection.name);
    Color selectedColor = Color(connection.connectionColor);
    showDialog(
      context: context,
      builder: (BuildContext outerContext) {
        return StatefulBuilder(
          builder: (BuildContext innerContext,
              void Function(void Function()) setStateDialog) {
            return AlertDialog(
              title: const Text('Редактировать связь'),
              content: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(
                      controller: nameController,
                      decoration:
                          const InputDecoration(labelText: 'Название связи'),
                    ),
                    const SizedBox(height: 10),
                    const Text('Выберите цвет связи:'),
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
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    connection.name = nameController.text.trim();
                    connection.connectionColor = selectedColor.value;
                    DatabaseHelper().updateConnection(connection).then((_) {
                      _loadPinboardData();
                    });
                    Navigator.of(outerContext).pop();
                  },
                  child: const Text('Сохранить'),
                ),
                TextButton(
                  onPressed: () {
                    DatabaseHelper().deleteConnection(connection.id!).then((_) {
                      _loadPinboardData();
                    });
                    Navigator.of(outerContext).pop();
                  },
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
}

/// Класс для отрисовки соединений между заметками на доске
class ConnectionPainter extends CustomPainter {
  final List<PinboardNoteDB> notes;
  final List<ConnectionDB> connections;
  ConnectionPainter({required this.notes, required this.connections});
  @override
  void paint(Canvas canvas, Size size) {
    try {
      final Map<int, PinboardNoteDB> notesMap = {
        for (var note in notes) note.id!: note
      };
      for (var connection in connections) {
        PinboardNoteDB? fromNote = notesMap[connection.fromId];
        PinboardNoteDB? toNote = notesMap[connection.toId];
        if (fromNote != null && toNote != null) {
          final Paint paint = Paint()
            ..color = Color(connection.connectionColor)
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke;
          Offset from =
              Offset(fromNote.posX, fromNote.posY) + const Offset(75, 75);
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
