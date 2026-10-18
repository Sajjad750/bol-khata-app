import 'app_database.dart';
import 'phone_numbers.dart';

/// Customer row for the home list (includes last activity for "2 hours ago").
class CustomerListItem {
  const CustomerListItem({required this.customer, this.lastActivityAt});

  final Customer customer;
  final DateTime? lastActivityAt;

  int get id => customer.id;
  String get name => customer.name;
  String get phoneNumber => customer.phoneNumber;
  String? get photoPath => customer.photoPath;
  double get currentBalance => customer.currentBalance;
  bool get isPhonePending => PhoneNumbers.isPending(customer.phoneNumber);
}
