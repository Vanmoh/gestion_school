class StudentFeeItem {
  final int id;
  final String studentFullName;
  final String studentMatricule;
  final String classroomName;
  final String feeType;
  final double amountDue;
  final double balance;
  final String dueDate;

  const StudentFeeItem({
    required this.id,
    required this.studentFullName,
    required this.studentMatricule,
    required this.classroomName,
    required this.feeType,
    required this.amountDue,
    required this.balance,
    required this.dueDate,
  });
}
