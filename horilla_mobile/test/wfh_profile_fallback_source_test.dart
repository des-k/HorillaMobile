import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String source() => File(
    'lib/employee_views/employee_form.dart',
  ).readAsStringSync();

  test('employee profile source keeps geo and face section with fallback state', () {
    final text = source();

    expect(text, contains('titleText = "Geo & Face Info";'));
    expect(text, contains("final Map<String, dynamic> wfhProfile = employeeDetails['wfh_profile'] is Map"));
    expect(text, contains("_absoluteMediaUrl((wfhProfile['face_image'] ?? '').toString())"));
    expect(text, contains("if (hasHomeCoordinates) ...["));
    expect(text, contains("Text('Radius: \$radius meter')"));
    expect(text, contains("Open in Google Maps"));
    expect(text, isNot(contains("Home Configured:")));
    expect(text, isNot(contains("Requires Home Reconfiguration:")));
    expect(text, isNot(contains("Requires Face Reenrollment:")));
    expect(text, isNot(contains("const Text('History'")));
    expect(text, isNot(contains("No WFH history")));
  });
}
