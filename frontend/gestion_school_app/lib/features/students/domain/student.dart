class Student {
  final int id;
  final int userId;
  final String username;
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String matricule;
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
}
