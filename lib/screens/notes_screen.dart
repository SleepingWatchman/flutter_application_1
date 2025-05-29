import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/note.dart';
import '../models/folder.dart';
import '../widgets/color_picker.dart';
import '../utils/toast_utils.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:oktoast/oktoast.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import '../providers/database_provider.dart';
import 'package:provider/provider.dart';
import '../providers/enhanced_collaborative_provider.dart';


/// Экран заметок и папок с использованием БД для заметок
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  _NotesScreenState createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Folder> _folders = [];
  List<Note> _notes = [];
  Folder? _selectedFolder;
  Note? _selectedNote;
  bool _isFolderExpanded = true;
  double _previewWidth = 0.3; // Default width ratio for preview window
  String _newFolderName = '';
  Color _selectedColor = Colors.blue;
  final TextEditingController _noteTitleController = TextEditingController();
  final TextEditingController _noteContentController = TextEditingController();
  final FocusNode _noteContentFocusNode = FocusNode();
  final FocusNode _noteTitleFocusNode = FocusNode();
  bool _isLoading = false;
  bool _isActive = true;
  bool _isDataLoaded = false; // ИСПРАВЛЕНИЕ: Флаг для предотвращения повторных загрузок
  String? _lastLoadedDatabaseId; // ИСПРАВЛЕНИЕ: Отслеживание последней загруженной базы
  DateTime? _lastSave; // ИСПРАВЛЕНИЕ: Переменная для отслеживания времени сохранения
  
  // ИСПРАВЛЕНИЕ: Сохраняем ссылки на провайдеры для безопасного dispose
  DatabaseProvider? _databaseProvider;
  EnhancedCollaborativeProvider? _enhancedCollaborativeProvider;
  
  // Кэш для отфильтрованных заметок
  Map<int?, List<Note>> _notesCache = {};
  
  // Виртуальная папка для заметок без папки
  final Folder _noFolderCategory = Folder(
    id: 0,
    name: 'Без папки',
    color: Colors.grey[600]!,
  );

  bool _isEditing = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // ИСПРАВЛЕНИЕ: Загружаем данные только один раз в initState
    _loadDataIfNeeded();
    
    // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Подписываемся на изменения базы данных
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      
      final dbProvider = Provider.of<DatabaseProvider>(context, listen: false);
      dbProvider.addListener(_handleDatabaseChanges);
      
      final enhancedCollabProvider = Provider.of<EnhancedCollaborativeProvider>(context, listen: false);
      enhancedCollabProvider.addListener(_handleCollaborativeDatabaseChanges);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // ИСПРАВЛЕНИЕ: Сохраняем ссылки на провайдеры для безопасного dispose
    _databaseProvider = Provider.of<DatabaseProvider>(context, listen: false);
    _enhancedCollaborativeProvider = Provider.of<EnhancedCollaborativeProvider>(context, listen: false);
    
    // ИСПРАВЛЕНИЕ: Загружаем данные только если есть флаг обновления
    if (_databaseProvider!.needsUpdate) {
      _forceReloadData();
      _databaseProvider!.resetUpdateFlag();
    } else {
      // Загружаем данные только если они нужны
      _loadDataIfNeeded();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _noteTitleController.dispose();
    _noteContentController.dispose();
    _noteContentFocusNode.dispose();
    _noteTitleFocusNode.dispose();
    
    // ИСПРАВЛЕНИЕ: Безопасное отписывание от изменений
    try {
      if (_databaseProvider != null) {
        _databaseProvider!.removeListener(_handleDatabaseChanges);
      }
      
      if (_enhancedCollaborativeProvider != null) {
        _enhancedCollaborativeProvider!.removeListener(_handleCollaborativeDatabaseChanges);
      }
    } catch (e) {
      print('Ошибка при отписке от изменений: $e');
    }
    
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isActive) {
      setState(() {
        _isActive = true;
      });
      _loadData();
    } else if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      setState(() {
        _isActive = false;
      });
    }
  }

  Future<void> _loadData() async {
    // ИСПРАВЛЕНИЕ: Защита от повторных загрузок
    if (_isLoading) {
      print('Загрузка данных уже выполняется, пропускаем');
      return;
    }
    
    setState(() => _isLoading = true);
    try {
      // Получаем провайдеры для доступа к текущему database_id
      final databaseProvider = Provider.of<DatabaseProvider>(context, listen: false);
      final enhancedCollabProvider = Provider.of<EnhancedCollaborativeProvider>(context, listen: false);
      
      // ИСПРАВЛЕНИЕ: Используем ТОЛЬКО EnhancedCollaborativeProvider для определения текущей базы
      final currentDatabaseId = enhancedCollabProvider.isUsingSharedDatabase 
          ? enhancedCollabProvider.currentDatabaseId 
          : null;
      
      print('Загрузка данных для базы: ${currentDatabaseId != null ? currentDatabaseId : "локальной"}');
      
      // Загружаем данные параллельно с учетом текущей базы
      final results = await Future.wait([
        _dbHelper.getFolders(currentDatabaseId),
        _dbHelper.getAllNotes(currentDatabaseId),
      ]);
      
      if (!mounted) return;
      
      setState(() {
        _folders = results[0] as List<Folder>;
        _notes = results[1] as List<Note>;
        _updateNotesCache();
        
        // Устанавливаем папку "Без папки" по умолчанию, если папка не выбрана
        if (_selectedFolder == null) {
          _selectedFolder = _noFolderCategory;
          _isFolderExpanded = true;
        }
        
        _isLoading = false;
        // ИСПРАВЛЕНИЕ: Устанавливаем флаги успешной загрузки
        _isDataLoaded = true;
        _lastLoadedDatabaseId = currentDatabaseId;
      });
    } catch (e) {
      print('Ошибка загрузки данных: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        showToast('Ошибка загрузки данных');
      }
    }
  }

  void _updateNotesCache() {
    _notesCache.clear();
    for (var note in _notes) {
      final key = note.folderId ?? 0; // Используем 0 для заметок без папки
      if (!_notesCache.containsKey(key)) {
        _notesCache[key] = [];
      }
      _notesCache[key]!.add(note);
    }
  }

  List<Note> _getNotesForFolder(Folder folder) {
    if (folder.id == _noFolderCategory.id) {
      return _notesCache[0] ?? []; // Используем ключ 0 для заметок без папки
    }
    return _notesCache[folder.id] ?? [];
  }

  void showToast(String message) {
    showToastWidget(
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
      ),
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> _createNote() async {
    try {
      // Получаем провайдер для доступа к текущему database_id
      final enhancedCollabProvider = Provider.of<EnhancedCollaborativeProvider>(context, listen: false);
      final currentDatabaseId = enhancedCollabProvider.isUsingSharedDatabase 
          ? enhancedCollabProvider.currentDatabaseId 
          : null;
      
      final now = DateTime.now();
      Map<String, dynamic> noteMap = {
        'title': '',
        'content': '',
        'folder_id': _selectedFolder?.id,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };
      
      // Добавляем database_id только если мы в совместной базе
      if (currentDatabaseId != null) {
        noteMap['database_id'] = currentDatabaseId;
      }
      
      final id = await _dbHelper.insertNote(noteMap);
      if (!mounted) return;

      setState(() {
        _selectedNote = Note(
          id: id,
          title: '',
          content: '',
          folderId: _selectedFolder?.id,
          createdAt: now,
          updatedAt: now,
          database_id: currentDatabaseId,
        );
        _notes.add(_selectedNote!);
        _noteTitleController.text = '';  // Пустой заголовок в контроллере
        _noteContentController.text = '';
        _updateNotesCache();
      });

      // Фокусируемся на заголовке
      _noteTitleFocusNode.requestFocus();

      showCustomToastWithIcon(
        "Заметка успешно создана",
        accentColor: Colors.green,
        fontSize: 14.0,
        icon: const Icon(Icons.check, size: 20, color: Colors.green),
      );
    } catch (e) {
      print('Ошибка создания заметки: $e');
      showCustomToastWithIcon(
        "Ошибка создания заметки",
        accentColor: Colors.yellow,
        fontSize: 14.0,
        icon: const Icon(Icons.warning, size: 20, color: Colors.yellow),
      );
    }
  }

  Future<void> _deleteNote(Note note) async {
    if (note.id == null) return;
    
    try {
      // Удаляем изображения из базы данных
      await _dbHelper.deleteImagesForNote(note.id!);
      
      // Удаляем заметку
      await _dbHelper.deleteNote(note.id!);
      if (!mounted) return;
      
      setState(() {
        // Удаляем заметку из списка
        _notes.removeWhere((n) => n.id == note.id);
        
        // Обновляем кэш заметок
        _updateNotesCache();
        
        // Если удалена выбранная заметка, очищаем поля редактирования
        if (_selectedNote?.id == note.id) {
          _selectedNote = null;
          _noteTitleController.clear();
          _noteContentController.clear();
        }
      });
      
      showCustomToastWithIcon(
        "Заметка успешно удалена",
        accentColor: Colors.red,
        fontSize: 14.0,
        icon: const Icon(Icons.close, size: 20, color: Colors.red),
      );
    } catch (e) {
      print('Ошибка удаления заметки: $e');
      showCustomToastWithIcon(
        "Ошибка удаления заметки",
        accentColor: Colors.yellow,
        fontSize: 14.0,
        icon: const Icon(Icons.warning, size: 20, color: Colors.yellow),
      );
    }
  }

  Future<void> _updateNote(Note note) async {
    await _dbHelper.updateNote(note);
  }

  Future<void> _addFolder() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Новая папка'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Название папки',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {
                    _newFolderName = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              ColorPicker(
                color: _selectedColor,
                onChanged: (color) {
                  setState(() {
                    _selectedColor = color;
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
                if (_newFolderName.isNotEmpty) {
                  Navigator.pop(context, {
                    'name': _newFolderName,
                    'color': _selectedColor,
                  });
                }
              },
              child: const Text('Создать'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      try {
        // Получаем провайдер для доступа к текущему database_id
        final enhancedCollabProvider = Provider.of<EnhancedCollaborativeProvider>(context, listen: false);
        final currentDatabaseId = enhancedCollabProvider.isUsingSharedDatabase 
            ? enhancedCollabProvider.currentDatabaseId 
            : null;
            
        final folder = Folder(
          name: result['name'],
          color: result['color'],
          database_id: currentDatabaseId,
        );
        
        await _dbHelper.insertFolder(folder.toMap());
        _loadData();
        showCustomToastWithIcon(
          "Папка успешно создана",
          accentColor: Colors.green,
          fontSize: 14.0,
          icon: const Icon(Icons.check, size: 20, color: Colors.green),
        );
      } catch (e) {
        print('Ошибка создания папки: $e');
        showCustomToastWithIcon(
          "Ошибка создания папки",
          accentColor: Colors.yellow,
          fontSize: 14.0,
          icon: const Icon(Icons.warning, size: 20, color: Colors.yellow),
        );
      }
    }
  }

  void _deleteFolder(int index) async {
    Folder folderToDelete = _folders[index];
    if (folderToDelete.id != null) {
      try {
        await _dbHelper.deleteFolder(folderToDelete.id!);
        setState(() {
          _folders.removeAt(index);
          // Обновляем заметки и их кэш
          for (var note in _notes) {
            if (note.folderId == folderToDelete.id) {
              final updatedNote = note.copyWith(
                folderId: null,
                updatedAt: DateTime.now(),
              );
              _dbHelper.updateNote(updatedNote);
              final noteIndex = _notes.indexWhere((n) => n.id == note.id);
              if (noteIndex != -1) {
                _notes[noteIndex] = updatedNote;
              }
            }
          }
          _updateNotesCache(); // Обновляем кэш после изменения заметок
          
          // После удаления папки выбираем папку "Без папки"
          _selectedFolder = _noFolderCategory;
          _isFolderExpanded = true;
          _selectedNote = null;
          _noteTitleController.clear();
          _noteContentController.clear();
        });
        showCustomToastWithIcon(
          "Папка успешно удалена",
          accentColor: Colors.red,
          fontSize: 14.0,
          icon: const Icon(Icons.close, size: 20, color: Colors.red),
        );
      } catch (e) {
        print('Ошибка удаления папки: $e');
        showCustomToastWithIcon(
          "Ошибка удаления папки",
          accentColor: Colors.yellow,
          fontSize: 14.0,
          icon: const Icon(Icons.warning, size: 20, color: Colors.yellow),
        );
      }
    }
  }

  Future<void> _editFolder(Folder folder) async {
    // Инициализируем начальные значения
    _newFolderName = folder.name;
    _selectedColor = folder.color;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Редактировать папку'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Название папки',
                  border: OutlineInputBorder(),
                ),
                controller: TextEditingController(text: _newFolderName),
                onChanged: (value) {
                  setState(() {
                    _newFolderName = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              ColorPicker(
                color: _selectedColor,
                onChanged: (color) {
                  setState(() {
                    _selectedColor = color;
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
                if (_newFolderName.isNotEmpty) {
                  Navigator.pop(context, {
                    'name': _newFolderName,
                    'color': _selectedColor,
                  });
                }
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      try {
        final updatedFolder = Folder(
          id: folder.id,
          name: result['name'],
          color: result['color'],
          database_id: folder.database_id, // Сохраняем database_id исходной папки
        );
        await _dbHelper.updateFolder(updatedFolder.toMap());
        _loadData();
        showCustomToastWithIcon(
          "Папка успешно обновлена",
          accentColor: Colors.yellow,
          fontSize: 14.0,
          icon: const Icon(Icons.edit, size: 20, color: Colors.yellow),
        );
      } catch (e) {
        print('Ошибка обновления папки: $e');
        showCustomToastWithIcon(
          "Ошибка обновления папки",
          accentColor: Colors.yellow,
          fontSize: 14.0,
          icon: const Icon(Icons.warning, size: 20, color: Colors.yellow),
        );
      }
    }
  }

  Future<void> _moveNoteToFolder(Note note, Folder? folder) async {
    if (note.id == null) return;
    
    try {
      // Проверяем, что папка принадлежит той же базе данных
      if (folder != null && folder.id != 0) {
        // Получаем database_id заметки и папки
        final noteDbId = note.database_id;
        final folderDbId = folder.database_id;
        
        print('Перемещение заметки из базы "${noteDbId ?? 'локальная'}" в папку из базы "${folderDbId ?? 'локальная'}"');
        
        // Проверяем, что они из одной базы данных
        if (noteDbId != folderDbId) {
          print('Ошибка: нельзя переместить заметку в папку из другой базы данных');
          showToast('Нельзя переместить заметку в папку из другой базы данных');
          return;
        }
      }
      
      // Обновляем локальный объект заметки
      final updatedNote = note.copyWith(
        folderId: folder?.id,
        updatedAt: DateTime.now(),
        // Сохраняем database_id заметки
        database_id: note.database_id,
      );
      
      // Обновляем заметку в базе данных
      await _dbHelper.updateNote(updatedNote);
      
      setState(() {
        // Обновляем заметку в списке
        final index = _notes.indexWhere((n) => n.id == note.id);
        if (index != -1) {
          _notes[index] = updatedNote;
        }
        
        // Если это текущая выбранная заметка, обновляем её
        if (_selectedNote?.id == note.id) {
          _selectedNote = updatedNote;
        }
        
        // Обновляем кэш заметок
        _updateNotesCache();
      });
      
      // Показываем уведомление об успешном перемещении
      showToast('Заметка успешно перемещена');
    } catch (e) {
      print('Ошибка перемещения заметки: $e');
      showToast('Ошибка перемещения заметки');
    }
  }

  void _toggleFolderExpansion(Folder folder) {
    setState(() {
      if (_selectedFolder?.id == folder.id) {
        _isFolderExpanded = !_isFolderExpanded;
      } else {
        _selectedFolder = folder;
        _isFolderExpanded = true;
        _loadData(); // Загружаем все заметки вместо только тех, которые в папке
      }
    });
  }

  Widget _buildCombinedList() {
    return ListView(
      children: [
        // Папка "Без папки"
        _buildFolderItem(_noFolderCategory),
        
        // Остальные папки
        ..._folders.map((folder) => _buildFolderItem(folder)),
      ],
    );
  }

  Widget _buildFolderItem(Folder folder) {
    final isSelected = _selectedFolder?.id == folder.id;
    final notes = _getNotesForFolder(folder);
    
    return DragTarget<Note>(
      onWillAccept: (data) => data != null && data.folderId != folder.id,
      onAccept: (data) {
        // Перемещаем заметку в новую папку
        _moveNoteToFolder(data, folder);
      },
      builder: (context, candidateData, rejectedData) => Column(
        children: [
          ListTile(
            leading: Icon(
              _isFolderExpanded && isSelected
                  ? Icons.folder_open
                  : Icons.folder,
              color: folder.color,
            ),
            title: Text(folder.name),
            selected: isSelected,
            selectedTileColor: isSelected ? Colors.cyan.withOpacity(0.15) : Colors.transparent, // Полупрозрачный cyan для выбранной папки
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: isSelected ? const BorderSide(color: Colors.cyan, width: 2) : BorderSide.none,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (notes.isNotEmpty)
                  Icon(
                    _isFolderExpanded && isSelected ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
                if (folder.id != 0) // Не показываем кнопки для папки "Без папки"
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _editFolder(folder),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () => _deleteFolder(_folders.indexOf(folder)),
                      ),
                    ],
                  ),
              ],
            ),
            onTap: () => _toggleFolderExpansion(folder),
          ),
          if (_isFolderExpanded && isSelected)
            ...notes.map((note) => Draggable<Note>(
                  data: note,
                  feedback: Material(
                    elevation: 4,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.blue.withOpacity(0.1),
                      child: Text(
                        note.title.isEmpty ? 'Новая заметка' : note.title,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                  child: DragTarget<Note>(
                    onWillAccept: (data) => data != null && data.id != note.id,
                    onAccept: (data) {
                      // Меняем позиции заметок в списке
                      final sourceIndex = notes.indexOf(data);
                      final targetIndex = notes.indexOf(note);
                      if (sourceIndex != -1 && targetIndex != -1) {
                        setState(() {
                          final item = notes.removeAt(sourceIndex);
                          notes.insert(targetIndex, item);
                        });
                      }
                    },
                    builder: (context, candidateData, rejectedData) => Container(
                      decoration: BoxDecoration(
                        border: Border(
                          top: candidateData.isNotEmpty
                              ? const BorderSide(color: Colors.blue, width: 2)
                              : BorderSide.none,
                        ),
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.note),
                        title: Text(note.title.isEmpty ? 'Новая заметка' : note.title),
                        selected: _selectedNote?.id == note.id,
                        selectedTileColor: _selectedNote?.id == note.id ? Colors.cyan.withOpacity(0.15) : Colors.transparent, // Полупрозрачный cyan для выбранной заметки
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: _selectedNote?.id == note.id ? const BorderSide(color: Colors.cyan, width: 2) : BorderSide.none,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () => _deleteNote(note),
                            ),
                          ],
                        ),
                        onTap: () => _selectNote(note),
                      ),
                    ),
                  ),
                )),
        ],
      ),
    );
  }

  void _selectVirtualFolder() {
    setState(() {
      if (_selectedFolder?.id == _noFolderCategory.id) {
        _isFolderExpanded = !_isFolderExpanded;
      } else {
        _selectedFolder = _noFolderCategory;
        _isFolderExpanded = true;
        _selectedNote = null;
        _noteTitleController.clear();
        _noteContentController.clear();
      }
    });
  }

  void _editNote(Note note) {
    final titleController = TextEditingController(text: note.title);
    final contentController = TextEditingController(text: note.content);
    int? selectedFolderId = note.folderId;

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
                  DropdownButtonFormField<int?>(
                    value: selectedFolderId,
                    decoration: const InputDecoration(
                      labelText: 'Папка',
                      hintText: 'Выберите папку',
                    ),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(_noFolderCategory.name),
                      ),
                      ..._folders.map((folder) => DropdownMenuItem(
                            value: folder.id,
                            child: Text(folder.name),
                          )),
                    ],
                    onChanged: (value) {
                      setState(() {
                        selectedFolderId = value;
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
              onPressed: () async {
                final now = DateTime.now();
                Note updatedNote = Note(
                  id: note.id,
                  title: titleController.text,
                  content: contentController.text,
                  folderId: selectedFolderId,
                  createdAt: note.createdAt,
                  updatedAt: now,
                );
                await _updateNote(updatedNote);
                this.setState(() {
                  final index = _notes.indexWhere((n) => n.id == note.id);
                  if (index != -1) {
                    _notes[index] = updatedNote;
                    _selectedNote = updatedNote;
                    _noteTitleController.text = updatedNote.title;
                    _noteContentController.text = updatedNote.content ?? '';
                  }
                });
                Navigator.pop(context);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  void _selectFolder(Folder folder) {
    setState(() {
      _selectedFolder = folder;
      _selectedNote = null;
      _notes = _notes.where((note) => note.folderId == folder.id).toList();
    });
  }

  void _selectNote(Note note) {
    if (!mounted) return;
    
    setState(() {
      _selectedNote = note;
      _noteTitleController.text = note.title;
      _noteContentController.text = note.content ?? '';
    });
    
    // Загружаем изображения для выбранной заметки
    _loadImagesForNote(note);
  }

  Future<void> _updateNoteContent(String content) async {
    if (_selectedNote == null) return;
    
    try {
      // Получаем список изображений из базы данных
      final images = await _dbHelper.getImagesForNote(_selectedNote!.id!);
      final imagePaths = images.map((img) => img['file_name'] as String).toList();
      
      // Создаем JSON с информацией об изображениях
      final contentJson = {
        'content': content,
        'images': imagePaths,
      };
      
      // Обновляем локальный объект заметки
      final updatedNote = _selectedNote!.copyWith(
        title: _noteTitleController.text,
        content: content,
        updatedAt: DateTime.now(),
        content_json: jsonEncode(contentJson),
      );
      
      // Обновляем заметку в базе данных
      await _dbHelper.updateNote(updatedNote);
      
      setState(() {
        _selectedNote = updatedNote;
        
        // Обновляем заметку в списке
        final index = _notes.indexWhere((n) => n.id == _selectedNote!.id);
        if (index != -1) {
          _notes[index] = _selectedNote!;
        }
        
        // Обновляем кэш заметок
        _updateNotesCache();
      });
    } catch (e) {
      print('Ошибка обновления заметки: $e');
      showToast('Ошибка обновления заметки');
    }
  }

  Future<void> _updateNoteTitle(String title) async {
    if (_selectedNote == null) return;
    
    try {
      // Обновляем локальный объект заметки
      final updatedNote = _selectedNote!.copyWith(
        title: title,
        updatedAt: DateTime.now(),
      );
      
      // Обновляем заметку в базе данных
      await _dbHelper.updateNote(updatedNote);
      
      setState(() {
        _selectedNote = updatedNote;
        
        // Обновляем заметку в списке
        final index = _notes.indexWhere((n) => n.id == _selectedNote!.id);
        if (index != -1) {
          _notes[index] = _selectedNote!;
        }
        
        // Обновляем кэш заметок
        _updateNotesCache();
      });
    } catch (e) {
      print('Ошибка обновления заголовка: $e');
      showToast('Ошибка обновления заголовка');
    }
  }

  void _debounceSave() {
    final now = DateTime.now();
    _lastSave = now;
    
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_lastSave == now && mounted && _selectedNote != null) {
        _dbHelper.updateNote(_selectedNote!);
      }
    });
  }

  Widget _buildNoteEditor() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          // Панель инструментов
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.image),
                  onPressed: _handleImageSelection,
                  tooltip: 'Вставить изображение',
                ),
              ],
            ),
          ),
          // Редактор
          Expanded(
            child: TextField(
              controller: _noteContentController,
              focusNode: _noteContentFocusNode,
              maxLines: null,
              expands: true,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Содержание заметки (поддерживается Markdown). Нажмите Enter для новой строки. Нажмите на кнопку изображения для вставки.',
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(8),
              ),
              onChanged: _updateNoteContent,
              onSubmitted: (value) {
                setState(() {
                  _isEditing = false;
                });
              },
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              style: const TextStyle(
                fontSize: 16,
                height: 1.5,
              ),
              cursorColor: Colors.cyan,
              enableInteractiveSelection: true,
              showCursor: true,
              readOnly: false,
              onTapOutside: (event) {
                setState(() {
                  _isEditing = false;
                });
              },
              onEditingComplete: () {
                _debounceSave();
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleImageSelection() async {
    try {
      final result = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );

      if (result == null) return;

      final file = File(result.path);
      if (!await file.exists()) {
        showCustomToastWithIcon(
          "Выбранный файл не существует",
          accentColor: Colors.yellow,
          fontSize: 14.0,
          icon: const Icon(Icons.warning, size: 20, color: Colors.yellow),
        );
        return;
      }

      // Читаем файл как байты
      final imageBytes = await file.readAsBytes();
      final fileName = 'image_${DateTime.now().millisecondsSinceEpoch}${path.extension(result.path)}';

      // Сохраняем информацию об изображении в базе данных
      if (_selectedNote?.id != null) {
        await _dbHelper.insertImage(
          _selectedNote!.id!,
          fileName,
          imageBytes,
        );
      }

      // Вставляем Markdown-ссылку с именем файла
      final text = _noteContentController.text;
      final selection = _noteContentController.selection;
      final beforeText = text.substring(0, selection.start);
      final afterText = text.substring(selection.end);
      
      final imageMarkdown = '\n![Изображение]($fileName)\n';
      
      setState(() {
        _noteContentController.text = beforeText + imageMarkdown + afterText;
        _noteContentController.selection = TextSelection.collapsed(
          offset: selection.start + imageMarkdown.length,
        );
      });

      _updateNoteContent(_noteContentController.text);
      showCustomToastWithIcon(
        "Изображение успешно добавлено",
        accentColor: Colors.green,
        fontSize: 14.0,
        icon: const Icon(Icons.check, size: 20, color: Colors.green),
      );
    } catch (e) {
      print('Ошибка при выборе изображения: $e');
      showCustomToastWithIcon(
        "Ошибка при выборе изображения",
        accentColor: Colors.yellow,
        fontSize: 14.0,
        icon: const Icon(Icons.warning, size: 20, color: Colors.yellow),
      );
    }
  }

  Future<void> _loadImagesForNote(Note note) async {
    if (note.id == null) return;
    
    try {
      final images = await _dbHelper.getImagesForNote(note.id!);
      final imageMap = <String, Uint8List>{};
      
      for (var image in images) {
        final imageData = await _dbHelper.getImageData(image['id'] as int);
        if (imageData != null) {
          imageMap[image['file_name'] as String] = imageData;
        }
      }
      
      print('Загружено изображений для заметки ${note.id}: ${imageMap.length}');
    } catch (e) {
      print('Ошибка при загрузке изображений: $e');
    }
  }

  Widget _buildMarkdownPreview(String content) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _selectedNote?.id != null ? _dbHelper.getImagesForNote(_selectedNote!.id!) : Future.value([]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          print('Ошибка при загрузке изображений: ${snapshot.error}');
          return const Center(child: Text('Ошибка при загрузке изображений'));
        }

        final images = snapshot.data ?? [];
        final imageMap = <String, Uint8List>{};

        return FutureBuilder<void>(
          future: Future.wait(
            images.map((image) async {
              final imageData = await _dbHelper.getImageData(image['id'] as int);
              if (imageData != null) {
                imageMap[image['file_name'] as String] = imageData;
              }
            }),
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            return Markdown(
              data: content,
              selectable: true,
              imageBuilder: (uri, title, alt) {
                try {
                  // Получаем имя файла из URI
                  final fileName = uri.pathSegments.last;
                  var imageData = imageMap[fileName];
                  
                  if (imageData == null) {
                    print('Изображение не найдено в базе данных: $fileName');
                    
                    // Дополнительная проверка: пытаемся найти изображение по пути
                    return FutureBuilder<Uint8List?>(
                      future: _dbHelper.findImageInAllDatabases(fileName),
                      builder: (context, imageSnapshot) {
                        if (imageSnapshot.connectionState == ConnectionState.waiting) {
                          return Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                SizedBox(width: 8),
                                Text('Поиск изображения...'),
                              ],
                            ),
                          );
                        }
                        
                        if (imageSnapshot.hasData && imageSnapshot.data != null) {
                          // Изображение найдено
                          return Image.memory(
                            imageSnapshot.data!,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              print('Ошибка при отображении найденного изображения: $error');
                              return Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.broken_image, color: Colors.grey[600]),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Ошибка отображения',
                                      style: TextStyle(color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        }
                        
                        // Изображение не найдено
                        return Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.broken_image, color: Colors.grey[600]),
                              const SizedBox(width: 8),
                              Text(
                                'Изображение не найдено',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  }

                  return Image.memory(
                    imageData,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      print('Ошибка при отображении изображения: $error');
                      return Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.broken_image, color: Colors.grey[600]),
                            const SizedBox(width: 8),
                            Text(
                              'Ошибка отображения',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                } catch (e) {
                  print('Ошибка при обработке изображения: $e');
                  return Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.broken_image, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Text(
                          'Ошибка обработки',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  );
                }
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Consumer<DatabaseProvider>(
      builder: (context, databaseProvider, child) {
        if (databaseProvider.needsUpdate) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _loadData();
              databaseProvider.resetUpdateFlag();
            }
          });
        }
        
        return Scaffold(
          body: Row(
            children: [
              // Левая панель
              SizedBox(
                width: MediaQuery.of(context).size.width * _previewWidth,
                child: Column(
                  children: [
                    // Панель инструментов
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: _createNote,
                          ),
                          IconButton(
                            icon: const Icon(Icons.create_new_folder),
                            onPressed: _addFolder,
                          ),
                        ],
                      ),
                    ),
                    // Список папок и заметок
                    Expanded(
                      child: Container(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height,
                        ),
                        child: _buildCombinedList(),
                      ),
                    ),
                  ],
                ),
              ),
              // Разделитель с возможностью перетаскивания
              MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _previewWidth += details.delta.dx / MediaQuery.of(context).size.width;
                      // Ограничиваем ширину от 20% до 60% экрана
                      _previewWidth = _previewWidth.clamp(0.2, 0.6);
                    });
                  },
                  child: Container(
                    width: 8,
                    color: Colors.black,
                    child: Center(
                      child: Container(
                        width: 2,
                        height: double.infinity,
                        color: Colors.cyan,
                      ),
                    ),
                  ),
                ),
              ),
              // Правая панель
              Expanded(
                child: _selectedNote == null
                    ? const Center(child: Text('Выберите заметку'))
                    : Column(
                        children: [
                          // Заголовок заметки
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: TextField(
                              controller: _noteTitleController,
                              decoration: const InputDecoration(
                                hintText: 'Новая заметка',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: _updateNoteTitle,
                            ),
                          ),
                          // Панель инструментов
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: Colors.grey),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.image),
                                  onPressed: () {
                                    if (!_isEditing) {
                                      setState(() {
                                        _isEditing = true;
                                      });
                                    }
                                    _handleImageSelection();
                                  },
                                  tooltip: 'Вставить изображение',
                                ),
                              ],
                            ),
                          ),
                          // Объединенный редактор/предпросмотр
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(8.0),
                              child: _isEditing
                                  ? Container(
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.grey),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: TextField(
                                        controller: _noteContentController,
                                        focusNode: _noteContentFocusNode,
                                        maxLines: null,
                                        expands: true,
                                        autofocus: true,
                                        decoration: const InputDecoration(
                                          hintText: 'Содержание заметки (поддерживается Markdown). Нажмите Enter для новой строки. Нажмите на кнопку изображения для вставки.',
                                          border: InputBorder.none,
                                          contentPadding: EdgeInsets.all(8),
                                        ),
                                        onChanged: _updateNoteContent,
                                        onSubmitted: (value) {
                                          setState(() {
                                            _isEditing = false;
                                          });
                                        },
                                        keyboardType: TextInputType.multiline,
                                        textInputAction: TextInputAction.newline,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          height: 1.5,
                                        ),
                                        cursorColor: Colors.cyan,
                                        enableInteractiveSelection: true,
                                        showCursor: true,
                                        readOnly: false,
                                        onTapOutside: (event) {
                                          setState(() {
                                            _isEditing = false;
                                          });
                                        },
                                        onEditingComplete: () {
                                          _debounceSave();
                                        },
                                      ),
                                    )
                                  : GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _isEditing = true;
                                        });
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          border: Border.all(color: Colors.grey),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: SingleChildScrollView(
                                          padding: const EdgeInsets.all(8),
                                          child: ConstrainedBox(
                                            constraints: BoxConstraints(
                                              minHeight: 0,
                                              maxHeight: MediaQuery.of(context).size.height,
                                            ),
                                            child: _selectedNote?.content?.isEmpty ?? true
                                                ? Column(
                                                    children: [
                                                      Text(
                                                        'Содержание заметки (поддерживается Markdown). Нажмите Enter для новой строки. Для вставки изображения перетащите его сюда.',
                                                        style: TextStyle(
                                                          color: Colors.grey,
                                                          fontSize: 16,
                                                        ),
                                                      ),
                                                    ],
                                                  )
                                                : _buildMarkdownPreview(_selectedNote?.content ?? ''),
                                          ),
                                        ),
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
      },
    );
  }

  Future<void> _handleNoteUpdate(Note note) async {
    await _dbHelper.updateNote(note);
  }

  Future<void> _handleNoteDelete(Note note) async {
    await _dbHelper.deleteNote(note.id!);
  }

  Future<void> _handleNoteMove(Note note, int newFolderId) async {
    final updatedNote = note.copyWith(
      folderId: newFolderId,
      updatedAt: DateTime.now(),
    );
    await _dbHelper.updateNote(updatedNote);
  }

  Future<void> _handleNoteCopy(Note note) async {
    final newNote = Note(
      title: '${note.title} (копия)',
      content: note.content,
      folderId: note.folderId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _dbHelper.insertNote(newNote.toMap());
  }

  Future<void> _saveNote() async {
    if (_selectedNote != null) {
      final updatedNote = _selectedNote!.copyWith(
        title: _noteTitleController.text,
        content: _noteContentController.text,
        updatedAt: DateTime.now(),
      );
      await _dbHelper.updateNote(updatedNote);
    }
  }

  // Обработчик изменений базы данных
  void _handleDatabaseChanges() {
    if (mounted) {
      // ОПТИМИЗИРОВАНО: Убираем избыточное логирование
      // print('Обновление экрана заметок из-за изменений в базе данных');
      
      // ИСПРАВЛЕНИЕ: Загружаем данные только если база изменилась
      final enhancedCollabProvider = Provider.of<EnhancedCollaborativeProvider>(context, listen: false);
      final currentDatabaseId = enhancedCollabProvider.isUsingSharedDatabase 
          ? enhancedCollabProvider.currentDatabaseId 
          : null;
      
      // Проверяем, изменилась ли база данных
      if (_lastLoadedDatabaseId != currentDatabaseId) {
        _forceReloadData();
      }
    }
  }
  
  // Обработчик изменений совместной базы данных
  void _handleCollaborativeDatabaseChanges() {
    if (mounted) {
      // ОПТИМИЗИРОВАНО: Убираем избыточное логирование
      // print('Обновление экрана заметок из-за изменений в совместной базе данных');
      
      // ИСПРАВЛЕНИЕ: Загружаем данные только при переключении базы
      final enhancedCollabProvider = Provider.of<EnhancedCollaborativeProvider>(context, listen: false);
      final currentDatabaseId = enhancedCollabProvider.isUsingSharedDatabase 
          ? enhancedCollabProvider.currentDatabaseId 
          : null;
      
      // Проверяем, изменилась ли база данных
      if (_lastLoadedDatabaseId != currentDatabaseId) {
        _forceReloadData();
      }
    }
  }

  // ИСПРАВЛЕНИЕ: Новый метод для условной загрузки данных
  void _loadDataIfNeeded() {
    final enhancedCollabProvider = Provider.of<EnhancedCollaborativeProvider>(context, listen: false);
    final currentDatabaseId = enhancedCollabProvider.isUsingSharedDatabase 
        ? enhancedCollabProvider.currentDatabaseId 
        : null;
    
    // Загружаем данные только если база изменилась или данные еще не загружены
    if (!_isDataLoaded || _lastLoadedDatabaseId != currentDatabaseId) {
      _loadData();
    }
  }

  // ИСПРАВЛЕНИЕ: Метод для принудительной перезагрузки
  void _forceReloadData() {
    _isDataLoaded = false;
    _lastLoadedDatabaseId = null;
    _notesCache.clear();
    _loadData();
  }
} 