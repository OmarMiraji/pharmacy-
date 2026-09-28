import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ExpiryPriority {
  static const urgentDays = 30;
  static const watchDays = 90;
  static const notifyDays = 5;

  static DateTime startOfToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static int daysLeft(DateTime expiry) {
    final day = DateTime(expiry.year, expiry.month, expiry.day);
    return day.difference(startOfToday()).inDays;
  }

  static bool isExpired(DateTime expiry) => daysLeft(expiry) < 0;

  static bool isUrgent(DateTime expiry) {
    final days = daysLeft(expiry);
    return days >= 0 && days <= urgentDays;
  }

  static bool isNotifySoon(DateTime expiry) {
    final days = daysLeft(expiry);
    return days >= 0 && days <= notifyDays;
  }

  static bool isWatch(DateTime expiry) {
    final days = daysLeft(expiry);
    return days > urgentDays && days <= watchDays;
  }

  static String format(DateTime expiry) {
    final day = expiry.day.toString().padLeft(2, '0');
    final month = expiry.month.toString().padLeft(2, '0');
    return '$day/$month/${expiry.year}';
  }

  static String label(DateTime expiry) {
    final days = daysLeft(expiry);
    if (days < 0) {
      final ago = -days;
      return ago == 1 ? 'Expired yesterday · ${format(expiry)}' : 'Expired $ago days ago · ${format(expiry)}';
    }
    if (days == 0) return 'Expires today — sell first';
    if (days == 1) return 'Expires tomorrow — sell first';
    if (days <= urgentDays) return 'Sell first · $days days · ${format(expiry)}';
    if (days <= watchDays) return 'Use soon · $days days · ${format(expiry)}';
    return 'Expires ${format(expiry)}';
  }

  static Color tint(DateTime expiry) {
    if (isExpired(expiry)) return const Color(0xffffeadf);
    if (isUrgent(expiry)) return const Color(0xfffff0d7);
    if (isWatch(expiry)) return const Color(0xfff2e7ff);
    return const Color(0xffdff7ee);
  }

  static Color ink(DateTime expiry) {
    if (isExpired(expiry) || isUrgent(expiry)) return const Color(0xffc2410c);
    if (isWatch(expiry)) return const Color(0xff6d28d9);
    return const Color(0xff0f766e);
  }

  static int compare(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    final aExpired = isExpired(a);
    final bExpired = isExpired(b);
    if (aExpired != bExpired) return aExpired ? -1 : 1;
    return a.compareTo(b);
  }

  static DateTime? parseAny(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return parse(value);
    if (value is num) {
      final n = value.toInt();
      if (n > 100000000000) return DateTime.fromMillisecondsSinceEpoch(n);
      if (n > 1000000000) return DateTime.fromMillisecondsSinceEpoch(n * 1000);
      if (n >= 19000101 && n <= 21001231) {
        final year = n ~/ 10000;
        final month = (n ~/ 100) % 100;
        final day = n % 100;
        if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
          return DateTime(year, month, day);
        }
      }
    }
    if (value is Map) {
      final seconds = value['_seconds'] ?? value['seconds'];
      if (seconds is num) return DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000);
    }
    return null;
  }

  static DateTime endOfMonth(int year, int month) => DateTime(year, month + 1, 0);

  static DateTime? parse(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    try {
      return DateTime.parse(trimmed);
    } catch (_) {}
    final monthYear = RegExp(r'^(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[/-]?(\d{2,4})$', caseSensitive: false);
    final monthYearMatch = monthYear.firstMatch(trimmed);
    if (monthYearMatch != null) {
      const months = {
        'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
        'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
      };
      final month = months[monthYearMatch.group(1)!.substring(0, 3).toLowerCase()];
      var year = int.tryParse(monthYearMatch.group(2)!);
      if (month != null && year != null) {
        if (year < 100) year += year >= 80 ? 1900 : 2000;
        return endOfMonth(year, month);
      }
    }
    final parts = trimmed.split(RegExp(r'[/-]'));
    if (parts.length == 2) {
      final first = int.tryParse(parts[0]);
      final second = int.tryParse(parts[1]);
      if (first == null || second == null) return null;
      final now = DateTime.now();
      if (second > 31 && first >= 1 && first <= 12) {
        final year = second < 100 ? 2000 + second : second;
        return endOfMonth(year, first);
      }
      if (first > 31 && second >= 1 && second <= 12) {
        final year = first < 100 ? 2000 + first : first;
        return endOfMonth(year, second);
      }
      if (first > 12 && second <= 12) return DateTime(now.year, second, first);
      if (second > 12 && first <= 12) return DateTime(now.year, first, second);
      return DateTime(now.year, second, first);
    }
    if (parts.length == 3) {
      final first = int.tryParse(parts[0]);
      final second = int.tryParse(parts[1]);
      var third = int.tryParse(parts[2]);
      if (first == null || second == null || third == null) return null;
      if (third < 100) third += third >= 80 ? 1900 : 2000;
      if (first > 31) return DateTime(first, second, third);
      if (first > 12) return DateTime(third, second, first);
      return DateTime(third, second, first);
    }
    return null;
  }
}
