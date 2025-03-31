import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/note.dart';
import '../models/folder.dart';
import '../widgets/color_picker.dart';
import '../utils/toast_utils.dart';

/// Экран заметок и папок с использованием БД для заметок
class NotesScreen extends StatefulWidget {
  const NotesScreen({Key? key}) : super(key: key);

  @override
  _NotesScreenState createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<Folder> _folders = [];
  List<Note> _notes = [];
  Folder? _selectedFolder;
  Note? _selectedNote;
  bool _isFolderExpanded = true;
  double _previewWidth = 0.3; // Default width ratio for preview window
  final TextEditingController _noteTitleController = TextEditingController();
  final TextEditingController _noteContentController = TextEditingController();
  // Виртуальная папка для заметок без папки
  final Folder _noFolderCategory = Folder(
    id: -1, // Специальный ID для виртуальной папки
    name: "Без папки",
    backgroundColor: Colors.grey[600]!.value,
  );

  @override
  void initState() {
    super.initState();
    _loadFolders();
    _loadAllNotes();
  }

  @override
  void dispose() {
    _noteTitleController.dispose();
    _noteContentController.dispose();
    super.dispose();
  }

  Future<void> _loadFolders() async {
    List<Folder> foldersFromDb = await DatabaseHelper().getFolders();
    setState(() {
      _folders = foldersFromDb;
    });
  }

  Future<void> _loadAllNotes() async {
    List<Note> notesFromDb = await DatabaseHelper().getAllNotes();
    setState(() {
      _notes = notesFromDb;
      // Выбираем папку "Без папки" по умолчанию, если папка не выбрана
      if (_selectedFolder == null) {
        _selectedFolder = _noFolderCategory;
        _isFolderExpanded = true;
      }
    });
  }

  Future<void> _loadNotes(int folderId) async {
    List<Note> notesFromDb;
    if (folderId == _noFolderCategory.id) {
      // Загружаем все заметки и фильтруем без папки
      notesFromDb = await DatabaseHelper().getAllNotes();
    } else {
      // Загружаем заметки для выбранной папки
      notesFromDb = await DatabaseHelper().getNotesByFolder(folderId);
    }
    setState(() {
      _notes = notesFromDb;
    });
  }

  void _addNote() async {
    Note newNote = Note(
      title: '',
      content: '',
      folderId: _selectedFolder?.id == _noFolderCategory.id ? null : _selectedFolder?.id,
    );
    int id = await DatabaseHelper().insertNote(newNote);
    newNote.id = id;
    setState(() {
      _notes.add(newNote);
      _selectedNote = newNote;
      _noteTitleController.text = newNote.title;
      _noteContentController.text = newNote.content ?? '';
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
        _selectedNote = null;
      });
      showCustomToastWithIcon(
        "Заметка успешно удалена",
        accentColor: Colors.red,
        fontSize: 14.0,
        icon: const Icon(Icons.close, size: 20, color: Colors.red),
      );
    }
  }

  void _updateSelectedNote(String title, String content, [int? folderId]) async {
    if (_selectedNote != null) {
      Note updatedNote = Note(
        id: _selectedNote!.id,
        title: title,
        content: content,
        folderId: folderId,
      );
      await DatabaseHelper().updateNote(updatedNote);
      setState(() {
        final index = _notes.indexWhere((note) => note.id == updatedNote.id);
        if (index != -1) {
          _notes[index] = updatedNote;
          _selectedNote = updatedNote;
        }
      });
    }
  }

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
        for (var note in _notes) {
          if (note.folderId == folderToDelete.id) {
            note.folderId = null;
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

  void _moveNoteToFolder(Note note, Folder folder) async {
    if (folder.id == _noFolderCategory.id) {
      note.folderId = null;
    } else if (note.folderId != folder.id) {
      note.folderId = folder.id;
    }
    
    await DatabaseHelper().updateNote(note);
    setState(() {
      final index = _notes.indexWhere((n) => n.id == note.id);
      if (index != -1) {
        _notes[index] = note;
        if (_selectedNote?.id == note.id) {
          _selectedNote = note;
        }
      }
    });
  }

  void _toggleFolderExpansion(Folder folder) {
    setState(() {
      if (_selectedFolder?.id == folder.id) {
        _isFolderExpanded = !_isFolderExpanded;
      } else {
        _selectedFolder = folder;
        _isFolderExpanded = true;
        _loadAllNotes(); // Загружаем все заметки вместо только тех, которые в папке
      }
    });
  }

  Widget _buildCombinedList() {
    return ListView.builder(
      itemCount: _folders.length + 1, // +1 для виртуальной папки "Без папки"
      itemBuilder: (context, index) {
        if (index == 0) {
          // Всегда показываем виртуальную папку "Без папки"
          final isSelected = _selectedFolder?.id == _noFolderCategory.id;
          // Получаем заметки без папки
          final notesWithoutFolder = _notes.where((note) => note.folderId == null).toList();
          
          return Column(
            children: [
              DragTarget<Note>(
                onAccept: (note) {
                  _moveNoteToFolder(note, _noFolderCategory);
                },
                builder: (context, candidates, rejects) {
                  return Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.cyan.withOpacity(0.2)
                          : candidates.isNotEmpty
                              ? Colors.cyan.withOpacity(0.1)
                              : null,
                      border: Border(
                        left: BorderSide(
                          color: isSelected
                              ? Colors.cyan
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                    child: ListTile(
                      leading: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Color(_noFolderCategory.backgroundColor),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      title: Text(_noFolderCategory.name),
                      selected: isSelected,
                      onTap: () => _selectVirtualFolder(),
                      trailing: Icon(
                        isSelected && _isFolderExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                      ),
                    ),
                  );
                },
              ),
              if (isSelected && _isFolderExpanded)
                ...notesWithoutFolder.map((note) {
                  final isNoteSelected = _selectedNote?.id == note.id;
                  return Draggable<Note>(
                    data: note,
                    feedback: Material(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        color: Colors.cyan.withOpacity(0.2),
                        child: Text(note.title),
                      ),
                    ),
                    childWhenDragging: Container(
                      color: Colors.grey[800],
                      child: ListTile(
                        title: Text(note.title),
                      ),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isNoteSelected
                            ? Colors.cyan.withOpacity(0.2)
                            : Colors.grey[850],
                        border: Border(
                          left: BorderSide(
                            color: isNoteSelected
                                ? Colors.cyan
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                      child: ListTile(
                        title: Text(note.title),
                        selected: isNoteSelected,
                        onTap: () {
                          setState(() {
                            _selectedNote = note;
                            _noteTitleController.text = note.title;
                            _noteContentController.text = note.content ?? '';
                          });
                        },
                        trailing: IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => _deleteNote(_notes.indexOf(note)),
                        ),
                      ),
                    ),
                  );
                }).toList(),
            ],
          );
        }

        // Показываем обычные папки
        final folderIndex = index - 1;
        final folder = _folders[folderIndex];
        final isSelected = _selectedFolder?.id == folder.id;
        // Фильтруем заметки по выбранной папке
        final folderNotes = _notes.where((note) => note.folderId == folder.id).toList();
        
        return Column(
          children: [
            DragTarget<Note>(
              onAccept: (note) {
                _moveNoteToFolder(note, folder);
              },
              builder: (context, candidates, rejects) {
                return Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.cyan.withOpacity(0.2)
                        : candidates.isNotEmpty
                            ? Colors.cyan.withOpacity(0.1)
                            : null,
                    border: Border(
                      left: BorderSide(
                        color: isSelected
                            ? Colors.cyan
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                  child: ListTile(
                    leading: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Color(folder.backgroundColor),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    title: Text(folder.name),
                    selected: isSelected,
                    onTap: () => _toggleFolderExpansion(folder),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            isSelected && _isFolderExpanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                          ),
                          onPressed: () => _toggleFolderExpansion(folder),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _editFolder(folderIndex),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () => _deleteFolder(folderIndex),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            if (isSelected && _isFolderExpanded)
              ...folderNotes.map((note) {
                final isNoteSelected = _selectedNote?.id == note.id;
                return Draggable<Note>(
                  data: note,
                  feedback: Material(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.cyan.withOpacity(0.2),
                      child: Text(note.title),
                    ),
                  ),
                  childWhenDragging: Container(
                    color: Colors.grey[800],
                    child: ListTile(
                      title: Text(note.title),
                    ),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isNoteSelected
                          ? Colors.cyan.withOpacity(0.2)
                          : Colors.grey[850],
                      border: Border(
                        left: BorderSide(
                          color: isNoteSelected
                              ? Colors.cyan
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                    child: ListTile(
                      title: Text(note.title),
                      selected: isNoteSelected,
                      onTap: () {
                        setState(() {
                          _selectedNote = note;
                          _noteTitleController.text = note.title;
                          _noteContentController.text = note.content ?? '';
                        });
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () => _deleteNote(_notes.indexOf(note)),
                      ),
                    ),
                  ),
                );
              }).toList(),
          ],
        );
      },
    );
  }

  void _selectVirtualFolder() {
    setState(() {
      if (_selectedFolder?.id == _noFolderCategory.id) {
        _isFolderExpanded = !_isFolderExpanded;
      } else {
        _selectedFolder = _noFolderCategory;
        _isFolderExpanded = true;
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
                Note updatedNote = Note(
                  id: note.id,
                  title: titleController.text,
                  content: contentController.text,
                  folderId: selectedFolderId,
                );
                await DatabaseHelper().updateNote(updatedNote);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Combined folders and notes list with resizable width
          SizedBox(
            width: MediaQuery.of(context).size.width * _previewWidth,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Папки и заметки',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: _addNote,
                          ),
                          IconButton(
                            icon: const Icon(Icons.create_new_folder),
                            onPressed: _addFolder,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _buildCombinedList(),
                ),
              ],
            ),
          ),
          // Resize handle
          GestureDetector(
            onHorizontalDragUpdate: (details) {
              setState(() {
                _previewWidth = (_previewWidth + details.delta.dx / MediaQuery.of(context).size.width)
                    .clamp(0.2, 0.5);
              });
            },
            child: Container(
              width: 8,
              color: Colors.transparent,
              child: Center(
                child: Container(
                  width: 2,
                  height: 40,
                  color: Colors.cyan.withOpacity(0.3),
                ),
              ),
            ),
          ),
          // Note content section
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      TextField(
                        controller: _noteTitleController,
                        decoration: const InputDecoration(
                          labelText: 'Заголовок',
                          hintText: 'Новая заметка',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          if (_selectedNote != null) {
                            _updateSelectedNote(
                              value,
                              _noteContentController.text,
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int?>(
                        value: _selectedNote?.folderId,
                        decoration: const InputDecoration(
                          labelText: 'Папка',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(_noFolderCategory.name),
                          ),
                          ..._folders.map((folder) {
                            return DropdownMenuItem(
                              value: folder.id,
                              child: Text(folder.name),
                            );
                          }).toList(),
                        ],
                        onChanged: (value) {
                          if (_selectedNote != null) {
                            _updateSelectedNote(
                              _noteTitleController.text,
                              _noteContentController.text,
                              value,
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Содержимое',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TextField(
                      controller: _noteContentController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      onChanged: (value) {
                        if (_selectedNote != null) {
                          _updateSelectedNote(
                            _noteTitleController.text,
                            value,
                          );
                        }
                      },
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