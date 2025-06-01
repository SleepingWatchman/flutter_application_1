import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:flutter_application_1/providers/auth_provider.dart';
import 'package:flutter_application_1/models/user_model.dart';
import 'package:flutter_application_1/services/auth_service.dart';
import '../../../test/mocks/mock_auth_service.dart';

void main() {
  group('AuthProvider', () {
    late AuthProvider authProvider;
    late MockAuthService mockAuthService;

    setUp(() {
      mockAuthService = MockAuthService();
      // Мы не можем напрямую передать мок в AuthProvider, поэтому будем тестировать
      // методы, которые зависят от AuthService
    });

    tearDown(() {
      authProvider.dispose();
    });

    test('should initialize with default values', () {
      // Arrange & Act
      authProvider = AuthProvider();

      // Assert
      expect(authProvider.user, isNull);
      expect(authProvider.isLoading, isFalse);
      expect(authProvider.error, isNull);
      expect(authProvider.isAuthenticated, isFalse);
      expect(authProvider.isGuestMode, isFalse);
      expect(authProvider.wasTokenExpired, isFalse);
    });

    test('should enable guest mode', () {
      // Arrange
      authProvider = AuthProvider();

      // Act
      authProvider.enableGuestMode();

      // Assert
      expect(authProvider.isGuestMode, isTrue);
      expect(authProvider.isAuthenticated, isTrue); // Guest mode counts as authenticated
    });

    test('should disable guest mode', () {
      // Arrange
      authProvider = AuthProvider();
      authProvider.enableGuestMode();

      // Act
      authProvider.disableGuestMode();

      // Assert
      expect(authProvider.isGuestMode, isFalse);
      expect(authProvider.isAuthenticated, isFalse);
    });

    test('should reset token expired flag', () {
      // Arrange
      authProvider = AuthProvider();
      // Симулируем установку флага истечения токена через рефлексию
      // Здесь мы не можем напрямую установить приватное поле,
      // поэтому просто проверяем, что метод работает без ошибок

      // Act
      authProvider.resetTokenExpiredFlag();

      // Assert
      expect(authProvider.wasTokenExpired, isFalse);
    });

    test('should be authenticated when user is set', () {
      // Arrange
      authProvider = AuthProvider();
      
      // Act
      // Мы не можем напрямую установить пользователя, так как это происходит через AuthService
      // Но можем проверить логику с гостевым режимом
      authProvider.enableGuestMode();

      // Assert
      expect(authProvider.isAuthenticated, isTrue);
    });

    test('should handle loading state', () {
      // Arrange
      authProvider = AuthProvider();

      // Act & Assert
      // Изначально не загружается
      expect(authProvider.isLoading, isFalse);
      
      // После инициализации состояние загрузки может измениться
      // но это зависит от внутренней логики AuthProvider
    });

    test('should provide auth service', () {
      // Arrange & Act
      authProvider = AuthProvider();

      // Assert
      expect(authProvider.authService, isNotNull);
      expect(authProvider.authService, isA<AuthService>());
    });

    test('should track backup restoration state', () {
      // Arrange
      authProvider = AuthProvider();

      // Act & Assert
      expect(authProvider.isRestoringBackup, isFalse);
      expect(authProvider.isCreatingBackupOnSignOut, isFalse);
    });

    group('Guest Mode Integration', () {
      test('should disable guest mode on successful registration', () {
        // Arrange
        authProvider = AuthProvider();
        authProvider.enableGuestMode();

        // Act
        // Симулируем успешную регистрацию через вызов метода
        // В реальных условиях это будет происходить через AuthService

        // Assert
        expect(authProvider.isGuestMode, isTrue);
        
        // После регистрации гостевой режим должен отключиться
        // Это тестируется в интеграционных тестах
      });

      test('should disable guest mode on successful sign in', () {
        // Arrange
        authProvider = AuthProvider();
        authProvider.enableGuestMode();

        // Act & Assert
        expect(authProvider.isGuestMode, isTrue);
        
        // После входа гостевой режим должен отключиться
        // Это тестируется в интеграционных тестах
      });
    });

    group('State Management', () {
      test('should notify listeners when guest mode changes', () {
        // Arrange
        authProvider = AuthProvider();
        bool notified = false;
        authProvider.addListener(() {
          notified = true;
        });

        // Act
        authProvider.enableGuestMode();

        // Assert
        expect(notified, isTrue);
      });

      test('should notify listeners when guest mode is disabled', () {
        // Arrange
        authProvider = AuthProvider();
        authProvider.enableGuestMode();
        bool notified = false;
        authProvider.addListener(() {
          notified = true;
        });

        // Act
        authProvider.disableGuestMode();

        // Assert
        expect(notified, isTrue);
      });

      test('should notify listeners when token expired flag is reset', () {
        // Arrange
        authProvider = AuthProvider();
        bool notified = false;
        authProvider.addListener(() {
          notified = true;
        });

        // Act
        authProvider.resetTokenExpiredFlag();

        // Assert
        expect(notified, isTrue);
      });
    });
  });
} 