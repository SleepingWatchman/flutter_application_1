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