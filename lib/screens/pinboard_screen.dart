import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/pinboard_note.dart';
import '../models/connection.dart';
import '../utils/toast_utils.dart';
import '../utils/icon_utils.dart';
import '../widgets/color_picker.dart';
import '../widgets/connection_painter.dart';
import '../providers/database_provider.dart';
import 'package:provider/provider.dart';

/// Экран доски с использованием БД для заметок и соединений
class PinboardScreen extends StatefulWidget {
  const PinboardScreen({Key? key}) : super(key: key);

  @override
  _PinboardScreenState createState() => _PinboardScreenState();
}

class _PinboardScreenState extends State<PinboardScreen> with WidgetsBindingObserver {
  List<PinboardNoteDB> _pinboardNotes = [];
  List<ConnectionDB> _connections = [];
  int? _selectedForConnection;
  List<String> _availableIcons = ['person', 'check', 'tree', 'home', 'car', 'close'];
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPinboardData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Provider.of<DatabaseProvider>(context, listen: false).needsUpdate) {
      _loadPinboardData();
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
      _loadPinboardData();
    } else if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      setState(() {
        _isActive = false;
      });
    }
  }

  Future<void> _loadPinboardData() async {
    List<PinboardNoteDB> notes = await DatabaseHelper().getPinboardNotes();
    List<ConnectionDB> connections = await DatabaseHelper().getConnectionsDB();
    setState(() {
      _pinboardNotes = notes;
      _connections = connections;
    });
  }

  void _addNote() {
    final newNote = PinboardNoteDB(
      title: '',
      content: '',
      posX: 100,
      posY: 100,
      backgroundColor: 0xFF424242,
      icon: 'person',
    );

    DatabaseHelper().insertPinboardNote(newNote.toMap()).then((_) {
      _loadPinboardData();
      showCustomToastWithIcon(
        "Заметка успешно создана",
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
        "Заметка успешно удалена",
        accentColor: Colors.red,
        fontSize: 14.0,
        icon: const Icon(Icons.delete, size: 20, color: Colors.red),
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
          DatabaseHelper().insertConnection(newConn.toMap()).then((_) {
            _loadPinboardData();
          });
          _selectedForConnection = null;
        } else {
          _selectedForConnection = id;
        }
      }
    });
  }

  IconData getIconData(String iconKey) {
    switch (iconKey) {
      case 'person':
        return Icons.person;
      case 'check':
        return Icons.check_circle;
      case 'tree':
        return Icons.forest;
      case 'home':
        return Icons.home;
      case 'car':
        return Icons.directions_car;
      case 'close':
        return Icons.close;
      default:
        return Icons.person;
    }
  }

  void _selectIcon(PinboardNoteDB note) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выберите иконку'),
        content: SizedBox(
          height: 60,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _availableIcons.length,
            itemBuilder: (context, index) {
              final iconKey = _availableIcons[index];
              final isSelected = note.icon == iconKey;
              return Padding(
                padding: const EdgeInsets.all(4),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      note.icon = iconKey;
                    });
                    _updateNote(note);
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isSelected ? Colors.blue : Colors.transparent,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(getIconData(iconKey)),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _editPinboardNote(PinboardNoteDB note) {
    final titleController = TextEditingController(text: note.title);
    final contentController = TextEditingController(text: note.content);
    String selectedIcon = note.icon;
    Color selectedColor = Color(note.backgroundColor);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Редактировать заметку'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Заголовок',
                      hintText: 'Введите заголовок',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: contentController,
                    decoration: const InputDecoration(
                      labelText: 'Содержимое',
                      hintText: 'Введите содержимое заметки',
                    ),
                    maxLines: 5,
                  ),
                  const SizedBox(height: 16),
                  const Text('Выберите иконку:'),
                  SizedBox(
                    height: 60,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _availableIcons.length,
                      itemBuilder: (context, index) {
                        final iconKey = _availableIcons[index];
                        final isSelected = selectedIcon == iconKey;
                        return Padding(
                          padding: const EdgeInsets.all(4),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                selectedIcon = iconKey;
                              });
                            },
                            child: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: isSelected ? Colors.blue : Colors.transparent,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(getIconData(iconKey)),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Выберите цвет заметки:'),
                  ColorPicker(
                    color: selectedColor,
                    onChanged: (color) {
                      setState(() {
                        selectedColor = color;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  note.title = titleController.text;
                  note.content = contentController.text;
                  note.icon = selectedIcon;
                  note.backgroundColor = selectedColor.value;
                });
                _updateNote(note);
                Navigator.pop(context);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  void _showNoteContextMenu(BuildContext context, PinboardNoteDB note, Offset position) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect positionRect = RelativeRect.fromRect(
      Rect.fromPoints(position, position),
      Offset.zero & overlay.size,
    );

    showMenu(
      context: context,
      position: positionRect,
      items: [
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              const Icon(Icons.edit),
              const SizedBox(width: 8),
              const Text('Редактировать'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete),
              const SizedBox(width: 8),
              const Text('Удалить'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'edit') {
        _editPinboardNote(note);
      } else if (value == 'delete') {
        _deletePinboardNote(note.id!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DatabaseProvider>(
      builder: (context, databaseProvider, child) {
        if (databaseProvider.needsUpdate) {
          _loadPinboardData();
          databaseProvider.resetUpdateFlag();
        }

        return Scaffold(
          backgroundColor: Colors.grey[850],
          body: Stack(
            children: [
              CustomPaint(
                size: MediaQuery.of(context).size,
                painter: ConnectionPainter(
                    notes: _pinboardNotes, connections: _connections),
              ),
              // Заметки на доске
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
            onPressed: _addNote,
            tooltip: 'Добавить заметку на доску',
            child: const Icon(Icons.add),
          ),
        );
      },
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
        Offset from = Offset(fromNote.posX, fromNote.posY) + const Offset(75, 75);
        Offset to = Offset(toNote.posX, toNote.posY) + const Offset(75, 75);
        Offset midpoint = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
        overlays.add(
          Positioned(
            left: midpoint.dx,
            top: midpoint.dy,
            child: GestureDetector(
              onSecondaryTapDown: (details) => _showConnectionContextMenu(context, connection, details.globalPosition),
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

  void _showConnectionContextMenu(BuildContext context, ConnectionDB connection, Offset position) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect positionRect = RelativeRect.fromRect(
      Rect.fromPoints(position, position),
      Offset.zero & overlay.size,
    );

    showMenu(
      context: context,
      position: positionRect,
      items: [
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              const Icon(Icons.edit),
              const SizedBox(width: 8),
              const Text('Редактировать'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete),
              const SizedBox(width: 8),
              const Text('Удалить'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'edit') {
        _editConnection(connection);
      } else if (value == 'delete') {
        _deleteConnection(connection.id!);
      }
    });
  }

  void _deleteConnection(int id) {
    DatabaseHelper().deleteConnection(id).then((_) {
      _loadPinboardData();
      showCustomToastWithIcon(
        "Связь успешно удалена",
        accentColor: Colors.red,
        fontSize: 14.0,
        icon: const Icon(Icons.delete, size: 20, color: Colors.red),
      );
    });
  }

  void _editConnection(ConnectionDB connection) {
    final nameController = TextEditingController(text: connection.name);
    Color selectedColor = Color(connection.connectionColor);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Редактировать связь'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Название связи',
                  hintText: 'Введите название связи',
                ),
              ),
              const SizedBox(height: 16),
              const Text('Выберите цвет связи:'),
              ColorPicker(
                color: selectedColor,
                onChanged: (color) {
                  setState(() {
                    selectedColor = color;
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  connection.name = nameController.text;
                  connection.connectionColor = selectedColor.value;
                });
                DatabaseHelper().updateConnection(connection.toMap()).then((_) {
                  _loadPinboardData();
                  Navigator.pop(context);
                  showCustomToastWithIcon(
                    "Связь успешно обновлена",
                    accentColor: Colors.yellow,
                    fontSize: 14.0,
                    icon: const Icon(Icons.edit, size: 20, color: Colors.yellow),
                  );
                });
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  void _updateNote(PinboardNoteDB note) {
    DatabaseHelper().updatePinboardNote(note).then((_) {
      _loadPinboardData();
      showCustomToastWithIcon(
        "Заметка успешно обновлена",
        accentColor: Colors.yellow,
        fontSize: 14.0,
        icon: const Icon(Icons.edit, size: 20, color: Colors.yellow),
      );
    });
  }

  void _selectColor(PinboardNoteDB note) {
    // Implementation of _selectColor method
  }
} 