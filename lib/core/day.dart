// Calendar days as plain ints (days since 1970-01-01), so comparisons and
// arithmetic on 200k tasks are cheap and nothing allocates.

typedef Day = int;

const int _msPerDay = 86400000;

Day dayOf(int y, int m, int d) => DateTime.utc(y, m, d).millisecondsSinceEpoch ~/ _msPerDay;

/// Null when y-m-d is not a real date (2026-02-30, month 13 …).
Day? validDay(int y, int m, int d) {
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  final dt = DateTime.utc(y, m, d);
  if (dt.year != y || dt.month != m || dt.day != d) return null;
  return dt.millisecondsSinceEpoch ~/ _msPerDay;
}

DateTime dateOf(Day day) => DateTime.fromMillisecondsSinceEpoch(day * _msPerDay, isUtc: true);

Day dayFromDate(DateTime d) => dayOf(d.year, d.month, d.day);

/// Overridable so tests can pin "today".
Day Function() todayFn = () => dayFromDate(DateTime.now());
Day today() => todayFn();

String _two(int n) => n < 10 ? '0$n' : '$n';

String isoDay(Day day) {
  final d = dateOf(day);
  final y = d.year.toString().padLeft(4, '0');
  return '$y-${_two(d.month)}-${_two(d.day)}';
}

/// 1 = Monday … 7 = Sunday.
int weekdayOf(Day day) => dateOf(day).weekday;

const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

Day addMonths(Day day, int months) {
  final d = dateOf(day);
  final m0 = d.month - 1 + months;
  final y = d.year + (m0 >= 0 ? m0 ~/ 12 : (m0 - 11) ~/ 12);
  final m = m0 % 12 + 1;
  final last = DateTime.utc(y, m + 1, 0).day;
  return dayOf(y, m, d.day > last ? last : d.day);
}
