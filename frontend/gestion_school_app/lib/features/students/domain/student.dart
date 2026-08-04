class Student {
  final int id;
  final int userId;
  final String username;
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String matricule;
  final String gender;
  final String fullName;
  final bool isArchived;
  final int? classroomId;
  final String classroomName;
  final int? parentId;
  final String parentName;
  final String parentPhone;
  final String photo;
  final DateTime? birthDate;
  final DateTime? enrollmentDate;

  const Student({
    required this.id,
    required this.userId,
    this.username = '',
    this.firstName = '',
    this.lastName = '',
    this.email = '',
    this.phone = '',
    required this.matricule,
    this.gender = '',
    required this.fullName,
    required this.isArchived,
    this.classroomId,
    this.classroomName = '',
    this.parentId,
    this.parentName = '',
    this.parentPhone = '',
    this.photo = '',
    this.birthDate,
    this.enrollmentDate,
  });

  /// Une seule lecture du JSON d'un eleve, partagee par la liste et le dossier.
  factory Student.fromJson(Map<String, dynamic> map) {
    final fullName = map['user_full_name']?.toString().trim();
    return Student(
      id: _asInt(map['id']),
      userId: _asInt(map['user']),
      username: map['user_username']?.toString() ?? '',
      firstName: map['user_first_name']?.toString() ?? '',
      lastName: map['user_last_name']?.toString() ?? '',
      email: map['user_email']?.toString() ?? '',
      phone: map['user_phone']?.toString() ?? '',
      matricule: map['matricule']?.toString() ?? '',
      gender: map['gender']?.toString() ?? '',
      fullName: (fullName != null && fullName.isNotEmpty) ? fullName : 'Inconnu',
      isArchived: map['is_archived'] as bool? ?? false,
      classroomId: map['classroom'] == null ? null : _asInt(map['classroom']),
      classroomName: map['classroom_name']?.toString() ?? '',
      parentId: map['parent'] == null ? null : _asInt(map['parent']),
      parentName: map['parent_name']?.toString() ?? '',
      parentPhone: map['parent_phone']?.toString() ?? '',
      photo: map['photo']?.toString() ?? '',
      birthDate: _toDate(map['birth_date']),
      enrollmentDate: _toDate(map['enrollment_date']),
    );
  }

  /// Age revolu, ou null si la date de naissance manque.
  ///
  /// Calcule ici et non a l'affichage: deux ecrans qui le recalculent chacun
  /// finissent par diverger d'un an autour de la date anniversaire.
  int? ageAt(DateTime reference) {
    final birth = birthDate;
    if (birth == null) return null;
    var age = reference.year - birth.year;
    final aEuSonAnniversaire =
        reference.month > birth.month ||
        (reference.month == birth.month && reference.day >= birth.day);
    if (!aEuSonAnniversaire) age -= 1;
    return age < 0 ? null : age;
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime? _toDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}
