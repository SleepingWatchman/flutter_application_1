import 'package:mockito/mockito.dart';
import 'package:flutter_application_1/services/auth_service.dart';
import 'package:flutter_application_1/models/user_model.dart';

class MockAuthService extends Mock implements AuthService {
  @override
  UserModel? get currentUser => super.noSuchMethod(
    Invocation.getter(#currentUser),
    returnValue: null,
  );

  @override
  String? get token => super.noSuchMethod(
    Invocation.getter(#token),
    returnValue: null,
  );

  @override
  Stream<UserModel?> get userStream => super.noSuchMethod(
    Invocation.getter(#userStream),
    returnValue: Stream<UserModel?>.empty(),
  );

  @override
  Future<UserModel> register(String email, String password, String displayName) =>
      super.noSuchMethod(
        Invocation.method(#register, [email, password, displayName]),
        returnValue: Future<UserModel>.value(UserModel(id: 'test', email: email)),
      );

  @override
  Future<UserModel> login(String email, String password) => super.noSuchMethod(
        Invocation.method(#login, [email, password]),
        returnValue: Future<UserModel>.value(UserModel(id: 'test', email: email)),
      );

  @override
  Future<void> signOut() => super.noSuchMethod(
        Invocation.method(#signOut, []),
        returnValue: Future<void>.value(),
      );

  @override
  Future<UserModel> updateProfile({String? displayName, String? photoURL}) =>
      super.noSuchMethod(
        Invocation.method(#updateProfile, [], {#displayName: displayName, #photoURL: photoURL}),
        returnValue: Future<UserModel>.value(UserModel(id: 'test', email: 'test@example.com')),
      );

  @override
  Future<void> loadSavedData() => super.noSuchMethod(
        Invocation.method(#loadSavedData, []),
        returnValue: Future<void>.value(),
      );

  @override
  bool isTokenExpired() => super.noSuchMethod(
        Invocation.method(#isTokenExpired, []),
        returnValue: false,
      );

  @override
  Future<String?> getToken() => super.noSuchMethod(
        Invocation.method(#getToken, []),
        returnValue: Future<String?>.value(null),
      );
} 