import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/models/user_model.dart';

void main() {
  group('UserModel', () {
    test('should create user model with all fields', () {
      // Arrange
      const id = 'test-id';
      const email = 'test@example.com';
      const displayName = 'Test User';
      const photoURL = 'https://example.com/photo.jpg';

      // Act
      final user = UserModel(
        id: id,
        email: email,
        displayName: displayName,
        photoURL: photoURL,
      );

      // Assert
      expect(user.id, equals(id));
      expect(user.email, equals(email));
      expect(user.displayName, equals(displayName));
      expect(user.photoURL, equals(photoURL));
    });

    test('should create user model with minimal fields', () {
      // Arrange
      const id = 'test-id';
      const email = 'test@example.com';

      // Act
      final user = UserModel(
        id: id,
        email: email,
      );

      // Assert
      expect(user.id, equals(id));
      expect(user.email, equals(email));
      expect(user.displayName, isNull);
      expect(user.photoURL, isNull);
    });

    test('should convert to JSON correctly', () {
      // Arrange
      final user = UserModel(
        id: 'test-id',
        email: 'test@example.com',
        displayName: 'Test User',
        photoURL: 'https://example.com/photo.jpg',
      );

      // Act
      final json = user.toJson();

      // Assert
      expect(json['id'], equals('test-id'));
      expect(json['email'], equals('test@example.com'));
      expect(json['displayName'], equals('Test User'));
      expect(json['photoURL'], equals('https://example.com/photo.jpg'));
    });

    test('should create from JSON correctly', () {
      // Arrange
      final json = {
        'id': 'test-id',
        'email': 'test@example.com',
        'displayName': 'Test User',
        'photoURL': 'https://example.com/photo.jpg',
      };

      // Act
      final user = UserModel.fromJson(json);

      // Assert
      expect(user.id, equals('test-id'));
      expect(user.email, equals('test@example.com'));
      expect(user.displayName, equals('Test User'));
      expect(user.photoURL, equals('https://example.com/photo.jpg'));
    });

    test('should handle null values in JSON gracefully', () {
      // Arrange
      final json = {
        'id': 'test-id',
        'email': 'test@example.com',
        'displayName': null,
        'photoURL': null,
      };

      // Act
      final user = UserModel.fromJson(json);

      // Assert
      expect(user.id, equals('test-id'));
      expect(user.email, equals('test@example.com'));
      expect(user.displayName, isNull);
      expect(user.photoURL, isNull);
    });

    test('should be equal when all fields match', () {
      // Arrange
      final user1 = UserModel(
        id: 'test-id',
        email: 'test@example.com',
        displayName: 'Test User',
        photoURL: 'https://example.com/photo.jpg',
      );

      final user2 = UserModel(
        id: 'test-id',
        email: 'test@example.com',
        displayName: 'Test User',
        photoURL: 'https://example.com/photo.jpg',
      );

      // Act & Assert
      expect(user1, equals(user2));
      expect(user1.hashCode, equals(user2.hashCode));
    });

    test('should not be equal when fields differ', () {
      // Arrange
      final user1 = UserModel(
        id: 'test-id-1',
        email: 'test1@example.com',
      );

      final user2 = UserModel(
        id: 'test-id-2',
        email: 'test2@example.com',
      );

      // Act & Assert
      expect(user1, isNot(equals(user2)));
    });

    test('should have proper toString representation', () {
      // Arrange
      final user = UserModel(
        id: 'test-id',
        email: 'test@example.com',
        displayName: 'Test User',
      );

      // Act
      final stringRep = user.toString();

      // Assert
      expect(stringRep, contains('test-id'));
      expect(stringRep, contains('test@example.com'));
      expect(stringRep, contains('Test User'));
    });
  });
} 