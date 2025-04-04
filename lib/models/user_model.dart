class UserModel {
  final int id;
  final String email;
  final String? displayName;
  final String? photoURL;

  UserModel({
    required this.id,
    required this.email,
    this.displayName,
    this.photoURL,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'],
      email: json['email'],
      displayName: json['displayName'],
      photoURL: json['photoURL'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'displayName': displayName,
      'photoURL': photoURL,
    };
  }
} 