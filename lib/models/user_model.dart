class UserModel {
  final String id;
  final String email;
  final String? displayName;
  final String? photoURL;
  final String? token;

  UserModel({
    required this.id,
    required this.email,
    this.displayName,
    this.photoURL,
    this.token,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'].toString(),
      email: json['email'] as String? ?? '',
      displayName: json['displayName'] as String?,
      photoURL: json['photoURL'] as String?,
      token: json['token'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'displayName': displayName,
      'photoURL': photoURL,
      'token': token,
    };
  }

  UserModel copyWith({
    String? id,
    String? email,
    String? displayName,
    String? photoURL,
    String? token,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoURL: photoURL ?? this.photoURL,
      token: token ?? this.token,
    );
  }
} 