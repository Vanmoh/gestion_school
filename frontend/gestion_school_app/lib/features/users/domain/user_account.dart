class UserAccount {
  final int id;
  final String username;
  final String firstName;
  final String lastName;
  final String email;
  final String role;
  final String phone;
  final int? etablissementId;
  final String etablissementName;

  const UserAccount({
    required this.id,
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.role,
    required this.phone,
    this.etablissementId,
    this.etablissementName = '',
  });

  String get fullName {
    final name = '$firstName $lastName'.trim();
    return name.isEmpty ? username : name;
  }
}
