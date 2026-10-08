import 'package:flutter/material.dart' show DateUtils;
import 'package:intl/intl.dart';

final _rupees = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
final _wholeRupees = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// Money is sent by the API in paise.
String rupees(num paise) => paise % 100 == 0 ? _wholeRupees.format(paise / 100) : _rupees.format(paise / 100);

DateTime? parseTime(Object? value) => value == null ? null : DateTime.parse(value as String).toLocal();

String dateTime(DateTime? time) => time == null ? '' : DateFormat('dd MMM, hh:mm a').format(time);

/// "just now", "18 min ago", "3 h ago", "2 days ago".
String ago(DateTime time, DateTime now) {
  final diff = now.difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} ${diff.inDays == 1 ? 'day' : 'days'} ago';
}

String countdown(Duration left) {
  if (left.isNegative) return '0:00';
  final s = left.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// "Today, 10:42 AM", "Yesterday, 08:15 PM" or "07 Oct, 10:42 AM".
String friendlyDateTime(DateTime? time, [DateTime? now]) {
  if (time == null) return '';
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final day = DateUtils.dateOnly(time);
  final clock = DateFormat('hh:mm a').format(time);
  if (day == today) return 'Today, $clock';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday, $clock';
  return dateTime(time);
}

/// "1 item", "3 items".
String itemsLabel(num count) => '$count ${count == 1 ? 'item' : 'items'}';

/// "+91 98765 43210".
String mobileDisplay(String mobile) =>
    mobile.length == 10 ? '+91 ${mobile.substring(0, 5)} ${mobile.substring(5)}' : '+91 $mobile';

String km(num meters) => '${(meters / 1000).toStringAsFixed(1)} km';

String addressLine(Map<String, dynamic> a) => [
  a['house'],
  a['street'],
  a['landmark'],
  [a['city'], a['pincode']].whereType<String>().join(' '),
].whereType<String>().where((s) => s.trim().isNotEmpty).join(', ');
