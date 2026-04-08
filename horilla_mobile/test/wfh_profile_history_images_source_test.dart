import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('employee profile source removes WFH history image section from mobile profile', () {
    final source = File('lib/employee_views/employee_form.dart').readAsStringSync();

    expect(source, isNot(contains("const Text('Old Face Photo:'")));
    expect(source, isNot(contains("const Text('New Face Photo:'")));
    expect(source, isNot(contains("Unable to load old face photo")));
    expect(source, isNot(contains("Unable to load new face photo")));
    expect(source, isNot(contains("No WFH history")));
  });
}
