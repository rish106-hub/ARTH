import 'package:intl/intl.dart';

final NumberFormat _inr0 =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// Formats whole rupees as `₹1,23,456` (Indian grouping, no decimals).
String money0(int amount) => _inr0.format(amount);
