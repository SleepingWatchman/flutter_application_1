import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TagInputWidget extends StatefulWidget {
  final List<String> initialTags;
  final ValueChanged<List<String>> onTagsChanged;
  final String? hintText;
  final int? maxTags;

  const TagInputWidget({
    Key? key,
    required this.initialTags,
    required this.onTagsChanged,
    this.hintText,
    this.maxTags,
  }) : super(key: key);

  @override
  _TagInputWidgetState createState() => _TagInputWidgetState();
}

class _TagInputWidgetState extends State<TagInputWidget> {
  List<String> _tags = [];
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _tags = List<String>.from(widget.initialTags);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _addTag(String tag) {
    final cleanTag = tag.trim();
    if (cleanTag.isEmpty) return;
    
    if (widget.maxTags != null && _tags.length >= widget.maxTags!) {
      return;
    }
    
    if (!_tags.contains(cleanTag)) {
      setState(() {
        _tags.add(cleanTag);
      });
      _controller.clear();
      widget.onTagsChanged(_tags);
    }
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
    widget.onTagsChanged(_tags);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Отображение существующих тегов
        if (_tags.isNotEmpty)
          Wrap(
            spacing: 8.0,
            runSpacing: 4.0,
            children: _tags.map((tag) => _buildTagChip(tag)).toList(),
          ),
        
        const SizedBox(height: 8),
        
        // Поле ввода нового тега
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          decoration: InputDecoration(
            hintText: widget.hintText ?? 'Добавить тег...',
            suffixIcon: IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _addTag(_controller.text),
            ),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: _addTag,
          inputFormatters: [
            FilteringTextInputFormatter.deny(RegExp(r'[,;]')), // Запрещаем запятые и точки с запятой
          ],
        ),
      ],
    );
  }

  Widget _buildTagChip(String tag) {
    return Chip(
      label: Text(tag),
      onDeleted: () => _removeTag(tag),
      deleteIcon: const Icon(Icons.close, size: 18),
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      labelStyle: TextStyle(
        color: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
    );
  }
} 