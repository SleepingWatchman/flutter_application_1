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
      email: json['email'],
      displayName: json['displayName'],
      photoURL: json['photoURL'] ?? json['photoUrl'],
      token: json['token'],
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
} 