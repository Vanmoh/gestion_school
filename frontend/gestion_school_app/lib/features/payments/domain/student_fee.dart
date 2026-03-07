class StudentFeeItem {
  final int id;
  final String studentFullName;
  final String studentMatricule;
  final String feeType;
  final double amountDue;
  final double balance;

  const StudentFeeItem({
    required this.id,
    required this.studentFullName,
    required this.studentMatricule,
    required this.feeType,
    required this.amountDue,
    required this.balance,
  });
}
