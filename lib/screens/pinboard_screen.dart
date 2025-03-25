import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/pinboard_note.dart';
import '../models/connection.dart';
import '../utils/toast_utils.dart';
import '../utils/icon_utils.dart';
import '../widgets/color_picker.dart';
import '../widgets/connection_painter.dart';

/// Экран доски с использованием БД для заметок и соединений
class PinboardScreen extends StatefulWidget {
  const PinboardScreen({Key? key}) : super(key: key);

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