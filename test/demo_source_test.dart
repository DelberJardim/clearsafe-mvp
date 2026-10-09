import 'package:clearsafe/data/demo_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safe_scanner/safe_scanner.dart';

void main() {
  test('Demo confirms full content with multiple windows', () async {
    final report = await Scanner(DemoSource()).scan(Criteria());
    expect(report.warnings, isEmpty);
    expect(report.duplicates.length, 1);
  });
}
