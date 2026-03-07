class PaymentItem {
  final int id;
  final int feeId;
  final double amount;
  final String method;
  final String reference;
  final String studentFullName;
  final String studentMatricule;
  final String feeType;
  final String createdAt;

  const PaymentItem({
    required this.id,
    required this.feeId,
    required this.amount,
    required this.method,
    required this.reference,
    required this.studentFullName,
    required this.studentMatricule,
    required this.feeType,
    required this.createdAt,
  });
}
