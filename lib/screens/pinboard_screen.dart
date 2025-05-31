import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../db/database_helper.dart';
import '../models/pinboard_note.dart';
import '../models/connection.dart';
import '../utils/toast_utils.dart';
import '../utils/icon_utils.dart';
import '../widgets/color_picker.dart';
import '../widgets/connection_painter.dart';
import '../providers/database_provider.dart';
import 'package:provider/provider.dart';
import '../providers/enhanced_collaborative_provider.dart';

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
  // Ключ для создания скриншотов
  final GlobalKey _boardKey = GlobalKey();
  // Состояние экспорта
  bool _isExporting = false;
  // ИСПРАВЛЕНИЕ: Сохраняем ссылки на провайдеры для безопасного dispose
  DatabaseProvider? _databaseProvider;
  EnhancedCollaborativeProvider? _enhancedCollaborativeProvider;
  bool _isLoading = false;
  bool _isDataLoaded = false;
  String? _lastLoadedDatabaseId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Инициализация списка доступных иконок
    _availableIcons = [
      'person',
      'check',
      'tree',
      'home',
      'car',
      'close',
    ];
    
    // Добавляем слушатель изменений для обновления интерфейса при переключении базы данных
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        // Подписываемся на изменения в DatabaseProvider
        final dbProvider = Provider.of<DatabaseProvider>(context, listen: false);
        dbProvider.addListener(_handleDatabaseChanges);
        
        // Подписываемся на изменения в EnhancedCollaborativeProvider
        final enhancedCollabProvider = Provider.of<EnhancedCollaborativeProvider>(context, listen: false);
        enhancedCollabProvider.addListener(_handleCollaborativeDatabaseChanges);
      } catch (e) {
        print('Ошибка при добавлении слушателей: $e');
      }
      
      // Загружаем данные доски при запуске
      _loadPinboardNotes();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // ИСПРАВЛЕНИЕ: Сохраняем ссылки на провайдеры для безопасного dispose
    _databaseProvider = Provider.of<DatabaseProvider>(context, listen: false);
    _enhancedCollaborativeProvider = Provider.of<EnhancedCollaborativeProvider>(context, listen: false);
    
    // Загружаем данные только если есть флаг обновления
    if (_databaseProvider != null && _databaseProvider!.needsUpdate) {
      _forceReloadPinboardNotes();
      _databaseProvider!.resetUpdateFlag();
    }
    
    // ИСПРАВЛЕНИЕ: Загружаем данные только если база изменилась или данные не загружены
    final currentDatabaseId = _enhancedCollaborativeProvider!.isUsingSharedDatabase 
        ? _enhancedCollaborativeProvider!.currentDatabaseId 
        : null;
        
    if (!_isDataLoaded || _lastLoadedDatabaseId != currentDatabaseId) {
      _loadPinboardNotes();
    }
  }

  @override
  void dispose() {
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
    
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isActive) {
      setState(() {
        _isActive = true;
      });
      _loadPinboardNotes();
    } else if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      setState(() {
        _isActive = false;
      });
    }
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
      if (_lastLoadedDatabaseId != currentDatabaseId || databaseProvider.needsUpdate) {
        // ЗАЩИТА ОТ ЦИКЛОВ: Сбрасываем флаг ПОСЛЕ начала обработки
        final wasUpdateNeeded = databaseProvider.needsUpdate;
        if (wasUpdateNeeded) {
          databaseProvider.resetUpdateFlag();
          print('🔄 ОБНОВЛЕНИЕ: Флаг needsUpdate сброшен для экрана досок');
        }
        _forceReloadPinboardNotes();
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
      if (_lastLoadedDatabaseId != currentDatabaseId || databaseProvider.needsUpdate) {
        // ЗАЩИТА ОТ ЦИКЛОВ: Сбрасываем флаг ПОСЛЕ начала обработки
        final wasUpdateNeeded = databaseProvider.needsUpdate;
        if (wasUpdateNeeded) {
          databaseProvider.resetUpdateFlag();
          print('🤝 КОЛЛАБОРАЦИЯ: Флаг needsUpdate сброшен для экрана досок');
        }
        _forceReloadPinboardNotes();
      }
    }
  }

  // ИСПРАВЛЕНИЕ: Метод для принудительной перезагрузки
  void _forceReloadPinboardNotes() {
    _isDataLoaded = false;
    _lastLoadedDatabaseId = null;
    _loadPinboardNotes();
  }

  Future<void> _loadPinboardNotes() async {
    // ИСПРАВЛЕНИЕ: Защита от повторных загрузок
    if (_isLoading) {
      print('Загрузка доски уже выполняется, пропускаем');
      return;
    }
    
    // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Проверяем блокировку операций с базой данных
    final databaseProvider = Provider.of<DatabaseProvider>(context, listen: false);
    if (databaseProvider.isBlocked) {
      print('⚠️ Загрузка доски заблокирована во время переключения базы данных');
      return;
    }
    
    setState(() => _isLoading = true);
    try {
      // ИСПРАВЛЕНИЕ: Используем только EnhancedCollaborativeProvider
      final enhancedCollabProvider = Provider.of<EnhancedCollaborativeProvider>(context, listen: false);
      final currentDatabaseId = enhancedCollabProvider.isUsingSharedDatabase 
          ? enhancedCollabProvider.currentDatabaseId 
          : null;
      
      print('Загрузка доски для базы: ${currentDatabaseId ?? "локальной"}');
      
      // Загружаем и заметки, и соединения
      final results = await Future.wait([
        DatabaseHelper().getPinboardNotes(currentDatabaseId),
        DatabaseHelper().getConnectionsDB(currentDatabaseId),
      ]);
      
      if (mounted) {
        setState(() {
          _pinboardNotes = results[0] as List<PinboardNoteDB>;
          _connections = results[1] as List<ConnectionDB>;
          _isDataLoaded = true;
          _lastLoadedDatabaseId = currentDatabaseId;
        });
      }
    } catch (e) {
      print('Ошибка загрузки доски: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _addNote() {
    // Получаем идентификатор текущей базы данных для правильного сохранения
    String? databaseId;
    try {
      final enhancedCollabProvider = Provider.of<EnhancedCollaborativeProvider>(context, listen: false);
      if (enhancedCollabProvider.isUsingSharedDatabase) {
        databaseId = enhancedCollabProvider.currentDatabaseId;
      }
    } catch (e) {
      print('Ошибка при получении информации о совместной базе: $e');
    }
    
    final newNote = PinboardNoteDB(
      title: '',
      content: '',
      posX: 100,
      posY: 100,
      backgroundColor: 0xFF424242,
      icon: 'person',
      database_id: databaseId, // Добавляем ID базы данных
    );

    print('Создание заметки на доске в базе: ${databaseId ?? "локальная"}');
    DatabaseHelper().insertPinboardNote(newNote.toMap()).then((_) {
      if (!mounted) return;
      _loadPinboardNotes();
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
      if (!mounted) return;
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

  // Функция для экспорта экрана в виде изображения
  Future<void> _exportBoardAsImage() async {
    try {
      setState(() {
        _isExporting = true;
      });

      // Получаем границы виджета
      if (!mounted || _boardKey.currentContext == null) {
        showCustomToastWithIcon(
          "Не удалось получить доступ к доске",
          accentColor: Colors.red,
          fontSize: 14.0,
          icon: const Icon(Icons.error, size: 20, color: Colors.red),
        );
        setState(() {
          _isExporting = false;
        });
        return;
      }
      
      final RenderRepaintBoundary boundary = 
          _boardKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      
      // Создаем изображение
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData == null) {
        if (!mounted) return;
        showCustomToastWithIcon(
          "Не удалось создать изображение",
          accentColor: Colors.red,
          fontSize: 14.0,
          icon: const Icon(Icons.error, size: 20, color: Colors.red),
        );
        setState(() {
          _isExporting = false;
        });
        return;
      }
      
      final Uint8List imageBytes = byteData.buffer.asUint8List();
      
      // Обработка в зависимости от платформы
      if (Platform.isWindows) {
        try {
          // Для Windows используем FilePicker для выбора места сохранения
          String? outputPath = await FilePicker.platform.saveFile(
            dialogTitle: 'Сохранить изображение доски',
            fileName: 'pinboard_${DateTime.now().millisecondsSinceEpoch}.png',
            type: FileType.custom,
            allowedExtensions: ['png'],
          );

          if (outputPath != null) {
            // Добавляем расширение .png, если его нет
            if (!outputPath.toLowerCase().endsWith('.png')) {
              outputPath = '$outputPath.png';
            }
            
            // Сохраняем файл
            final File file = File(outputPath);
            await file.writeAsBytes(imageBytes);
            
            if (!mounted) return;
            showCustomToastWithIcon(
              "Изображение успешно сохранено: $outputPath",
              accentColor: Colors.green,
              fontSize: 14.0,
              icon: const Icon(Icons.check, size: 20, color: Colors.green),
            );
          } else {
            // Пользователь отменил сохранение
            if (!mounted) return;
            showCustomToastWithIcon(
              "Сохранение отменено",
              accentColor: Colors.orange,
              fontSize: 14.0,
              icon: const Icon(Icons.info, size: 20, color: Colors.orange),
            );
          }
        } catch (e) {
          if (!mounted) return;
          showCustomToastWithIcon(
            "Ошибка при сохранении: $e",
            accentColor: Colors.red,
            fontSize: 14.0,
            icon: const Icon(Icons.error, size: 20, color: Colors.red),
          );
        }
      } else {
        try {
          // Для других платформ используем стандартный механизм Share
          // Временный файл для сохранения
          final tempDir = await getTemporaryDirectory();
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final fileName = 'pinboard_$timestamp.png';
          final File file = File('${tempDir.path}/$fileName');
          await file.writeAsBytes(imageBytes);
          
          // Делимся файлом
          await Share.shareXFiles(
            [XFile(file.path)],
            subject: 'Доска заметок',
            text: 'Экспорт доски заметок',
          );
          
          if (!mounted) return;
          showCustomToastWithIcon(
            "Изображение готово к сохранению",
            accentColor: Colors.green,
            fontSize: 14.0,
            icon: const Icon(Icons.check, size: 20, color: Colors.green),
          );
        } catch (e) {
          if (!mounted) return;
          showCustomToastWithIcon(
            "Ошибка при экспорте: $e",
            accentColor: Colors.red,
            fontSize: 14.0,
            icon: const Icon(Icons.error, size: 20, color: Colors.red),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      showCustomToastWithIcon(
        "Произошла ошибка: $e",
        accentColor: Colors.red,
        fontSize: 14.0,
        icon: const Icon(Icons.error, size: 20, color: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
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
          // Получаем идентификатор текущей базы данных для правильного сохранения
          String? databaseId;
          try {
            final enhancedCollabProvider = Provider.of<EnhancedCollaborativeProvider>(context, listen: false);
            if (enhancedCollabProvider.isUsingSharedDatabase) {
              databaseId = enhancedCollabProvider.currentDatabaseId;
            }
          } catch (e) {
            print('Ошибка при получении информации о совместной базе: $e');
          }
          
          ConnectionDB newConn = ConnectionDB(
            fromId: _selectedForConnection!, 
            toId: id,
            database_id: databaseId, // Добавляем ID базы данных
          );
          
          print('Создание связи между заметками в базе: ${databaseId ?? "локальная"}');
          DatabaseHelper().insertConnection(newConn.toMap()).then((_) {
            _loadPinboardNotes();
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
                if (!mounted) return;
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
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _loadPinboardNotes();
            }
          });
          databaseProvider.resetUpdateFlag();
        }

        return Scaffold(
          backgroundColor: Colors.grey[850],
          appBar: AppBar(
            title: const Text("Доска заметок"),
            actions: [
              // Кнопка экспорта доски в виде изображения
              IconButton(
                onPressed: _isExporting ? null : _exportBoardAsImage,
                icon: _isExporting 
                  ? const SizedBox(
                      width: 20, 
                      height: 20, 
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      )
                    )
                  : const Icon(Icons.save_alt),
                tooltip: "Экспортировать как изображение",
              ),
            ],
          ),
          body: RepaintBoundary(
            key: _boardKey,
            child: Container(
              color: Colors.grey[850],
              child: Stack(
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
            ),
          ),
          floatingActionButton: FloatingActionButton(
            heroTag: 'add_pinboard_note_fab',
            onPressed: _addNote,
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
      if (!mounted) return;
      _loadPinboardNotes();
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
                if (!mounted) return;
                setState(() {
                  connection.name = nameController.text;
                  connection.connectionColor = selectedColor.value;
                });
                
                // Сохраняем существующий database_id или устанавливаем новый если нужно
                if (connection.database_id == null) {
                  try {
                    final enhancedCollabProvider = Provider.of<EnhancedCollaborativeProvider>(context, listen: false);
                    if (enhancedCollabProvider.isUsingSharedDatabase) {
                      connection.database_id = enhancedCollabProvider.currentDatabaseId;
                      print('Обновление связи с установкой базы: ${connection.database_id}');
                    }
                  } catch (e) {
                    print('Ошибка при получении информации о совместной базе: $e');
                  }
                } else {
                  print('Обновление связи в базе: ${connection.database_id}');
                }
                
                DatabaseHelper().updateConnection(connection.toMap()).then((_) {
                  if (!mounted) return;
                  _loadPinboardNotes();
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
    // Сохраняем существующий database_id или устанавливаем новый если нужно
    if (note.database_id == null) {
      try {
        final enhancedCollabProvider = Provider.of<EnhancedCollaborativeProvider>(context, listen: false);
        if (enhancedCollabProvider.isUsingSharedDatabase) {
          note.database_id = enhancedCollabProvider.currentDatabaseId;
          print('Обновление заметки на доске с установкой базы: ${note.database_id}');
        }
      } catch (e) {
        print('Ошибка при получении информации о совместной базе: $e');
      }
    } else {
      print('Обновление заметки на доске в базе: ${note.database_id}');
    }
    
    DatabaseHelper().updatePinboardNote(note).then((_) {
      if (!mounted) return;
      _loadPinboardNotes();
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