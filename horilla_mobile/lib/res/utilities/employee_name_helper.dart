String cleanOptionalText(dynamic value) {
  if (value == null) return '';
  final text = value.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return '';
  return text;
}

String buildEmployeeName(Map source, {String firstKey = 'employee_first_name', String lastKey = 'employee_last_name'}) {
  final first = cleanOptionalText(source[firstKey]);
  final last = cleanOptionalText(source[lastKey]);
  return [first, last].where((e) => e.isNotEmpty).join(' ');
}
