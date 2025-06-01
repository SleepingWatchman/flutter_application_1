import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/models/note.dart';

void main() {
  group('Note', () {
    test('should create note with all fields', () {
      // Arrange
      const id = 1;
      const title = 'Test Note';
      const content = 'Test content';
      const folderId = 2;
      final createdAt = DateTime(2024, 1, 1);
      final updatedAt = DateTime(2024, 1, 2);

      // Act
      final note = Note(
        id: id,
        title: title,
        content: content,
        folderId: folderId,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      // Assert
      expect(note.id, equals(id));
      expect(note.title, equals(title));
      expect(note.content, equals(content));
      expect(note.folderId, equals(folderId));
      expect(note.createdAt, equals(createdAt));
      expect(note.updatedAt, equals(updatedAt));
    });

    test('should create note with minimal fields', () {
      // Arrange
      const title = 'Test Note';
      final now = DateTime.now();

      // Act
      final note = Note(
        title: title,
        createdAt: now,
        updatedAt: now,
      );

      // Assert
      expect(note.id, isNull);
      expect(note.title, equals(title));
      expect(note.content, isNull);
      expect(note.folderId, isNull);
      expect(note.createdAt, equals(now));
      expect(note.updatedAt, equals(now));
    });

    test('should convert to map correctly', () {
      // Arrange
      final createdAt = DateTime(2024, 1, 1);
      final updatedAt = DateTime(2024, 1, 2);
      final note = Note(
        id: 1,
        title: 'Test Note',
        content: 'Test content',
        folderId: 2,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      // Act
      final map = note.toMap();

      // Assert
      expect(map['id'], equals(1));
      expect(map['title'], equals('Test Note'));
      expect(map['content'], equals('Test content'));
      expect(map['folder_id'], equals(2));
      expect(map['created_at'], equals(createdAt.toIso8601String()));
      expect(map['updated_at'], equals(updatedAt.toIso8601String()));
    });

    test('should create from map correctly', () {
      // Arrange
      final map = {
        'id': 1,
        'title': 'Test Note',
        'content': 'Test content',
        'folder_id': 2,
        'created_at': '2024-01-01T00:00:00.000',
        'updated_at': '2024-01-02T00:00:00.000',
      };

      // Act
      final note = Note.fromMap(map);

      // Assert
      expect(note.id, equals(1));
      expect(note.title, equals('Test Note'));
      expect(note.content, equals('Test content'));
      expect(note.folderId, equals(2));
      expect(note.createdAt, equals(DateTime.parse('2024-01-01T00:00:00.000')));
      expect(note.updatedAt, equals(DateTime.parse('2024-01-02T00:00:00.000')));
    });

    test('should handle null values in map gracefully', () {
      // Arrange
      final map = {
        'title': 'Test Note',
        'created_at': '2024-01-01T00:00:00.000',
        'updated_at': '2024-01-02T00:00:00.000',
      };

      // Act
      final note = Note.fromMap(map);

      // Assert
      expect(note.title, equals('Test Note'));
      expect(note.id, isNull);
      expect(note.content, isNull);
      expect(note.folderId, isNull);
      expect(note.createdAt, isNotNull);
      expect(note.updatedAt, isNotNull);
    });

    test('should convert to JSON string correctly', () {
      // Arrange
      final createdAt = DateTime(2024, 1, 1);
      final updatedAt = DateTime(2024, 1, 2);
      final note = Note(
        id: 1,
        title: 'Test Note',
        content: 'Test content',
        folderId: 2,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

      // Act
      final json = note.toJson();

      // Assert
      expect(json, isA<String>());
      expect(json, contains('Test Note'));
      expect(json, contains('Test content'));
    });

    test('should create from JSON string correctly', () {
      // Arrange
      const jsonString = '''
      {
        "id": 1,
        "title": "Test Note",
        "content": "Test content",
        "folder_id": 2,
        "created_at": "2024-01-01T00:00:00.000",
        "updated_at": "2024-01-02T00:00:00.000"
      }
      ''';

      // Act
      final note = Note.fromJson(jsonString);

      // Assert
      expect(note.id, equals(1));
      expect(note.title, equals('Test Note'));
      expect(note.content, equals('Test content'));
      expect(note.folderId, equals(2));
    });

    test('should copy note with updated fields', () {
      // Arrange
      final originalNote = Note(
        id: 1,
        title: 'Original Title',
        content: 'Original Content',
        folderId: 1,
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
      );

      // Act
      final copiedNote = originalNote.copyWith(
        title: 'Updated Title',
        content: 'Updated Content',
      );

      // Assert
      expect(copiedNote.id, equals(originalNote.id));
      expect(copiedNote.title, equals('Updated Title'));
      expect(copiedNote.content, equals('Updated Content'));
      expect(copiedNote.folderId, equals(originalNote.folderId));
      expect(copiedNote.createdAt, equals(originalNote.createdAt));
    });

    test('should convert markdown to HTML', () {
      // Arrange
      final note = Note(
        title: 'Test Note',
        content: '# Heading\n\nThis is **bold** text.',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Act
      final html = note.toHtml();

      // Assert
      expect(html, contains('<h1>'));
      expect(html, contains('<strong>'));
      expect(html, contains('bold'));
    });

    test('should handle images list correctly', () {
      // Arrange
      final images = ['image1.jpg', 'image2.png'];
      final note = Note(
        title: 'Test Note',
        images: images,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Act
      final map = note.toMap();

      // Assert
      expect(note.images, equals(images));
      expect(map['images'], isNotNull);
    });

    test('should handle metadata correctly', () {
      // Arrange
      final metadata = {'key1': 'value1', 'key2': 42};
      final note = Note(
        title: 'Test Note',
        metadata: metadata,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Act
      final map = note.toMap();

      // Assert
      expect(note.metadata, equals(metadata));
      expect(map['metadata'], equals(metadata));
    });

    test('should handle database_id field correctly', () {
      // Arrange
      const databaseId = 'shared_db_123';
      final note = Note(
        title: 'Test Note',
        database_id: databaseId,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Act
      final map = note.toMap();

      // Assert
      expect(note.database_id, equals(databaseId));
      expect(map['database_id'], equals(databaseId));
    });
  });
} 