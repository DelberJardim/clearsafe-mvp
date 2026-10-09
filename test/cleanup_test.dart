import 'package:clearsafe/actions/trash_service.dart';
import 'package:clearsafe/analysis/similarity.dart';
import 'package:clearsafe/presentation/review_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safe_scanner/safe_scanner.dart';

Entry entry(String id, {String folder = 'Camera'}) => Entry(
  id: id,
  name: 'WA0001.jpg',
  size: 3,
  kind: Kind.photo,
  revision: '1',
  folder: folder,
);
VisualSignature signature(
  String id, {
  String? bits,
  bool? protected = false,
  String folder = 'Camera',
  double aspect = 1.5,
  List<double>? colors,
}) => VisualSignature(entry(id, folder: folder), {
  'bits': bits ?? '10' * 32,
  'protected': protected,
  'colors': colors ?? List.filled(12, 1 / 12),
  'aspect': aspect,
});
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'unknown OCR, detected text, screenshots, missing data are protected',
    () {
      expect(signature('a', protected: true).usable, isFalse);
      expect(signature('a', protected: null).usable, isFalse);
      expect(signature('a', folder: 'Pictures/Screenshots').usable, isFalse);
      expect(signature('a', bits: 'bad').usable, isFalse);
      expect(signature('a', colors: [1]).usable, isFalse);
    },
  );
  test('visual matching checks colors and aspect; never names', () {
    expect(resembles(signature('a'), signature('b')), isTrue);
    expect(resembles(signature('a'), signature('b', aspect: 2)), isFalse);
    expect(
      resembles(
        signature('a'),
        signature('b', colors: [1, ...List.filled(11, 0)]),
      ),
      isFalse,
    );
    expect(resembles(signature('a'), signature('a')), isFalse);
    expect(resembles(signature('a'), signature('b', protected: true)), isFalse);
  });
  test('visual groups do not bridge a chain of dissimilar endpoints', () {
    final a = '10' * 32;
    String flip(int start, int end) => [
      for (var i = 0; i < 64; i++)
        i >= start && i < end ? (a[i] == '1' ? '0' : '1') : a[i],
    ].join();
    final values = [
      signature('a', bits: a),
      signature('b', bits: flip(0, 6)),
      signature('c', bits: flip(0, 12)),
    ];
    expect(resembles(values[0], values[1]), isTrue);
    expect(resembles(values[1], values[2]), isTrue);
    expect(resembles(values[0], values[2]), isFalse);
    expect(similarGroups(values).single.map((e) => e.id), ['a', 'b']);
  });
  test('invalid trash selections cannot reach native actions', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(TrashService.channel, (c) async {
          calls.add(c);
          return null;
        });
    final service = TrashService();
    await expectLater(service.trash([]), throwsArgumentError);
    await expectLater(
      service.trash([entry('a')], keep: entry('a')),
      throwsArgumentError,
    );
    await expectLater(
      service.trash([entry('a'), entry('a')]),
      throwsArgumentError,
    );
    await expectLater(
      service.trash([entry('a')], digest: 'bad'),
      throwsArgumentError,
    );
    await expectLater(
      service.trash(List.generate(101, (i) => entry('$i'))),
      throwsArgumentError,
    );
    expect(calls, isEmpty);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(TrashService.channel, null);
  });
  test(
    'exact and manual requests keep their separate verification modes',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(TrashService.channel, (c) async {
            calls.add(c);
            return null;
          });
      await TrashService().trash(
        [entry('b')],
        keep: entry('a'),
        digest: 'a' * 64,
      );
      expect(calls.single.arguments['exact'], true);
      expect(calls.single.arguments['keep']['id'], 'a');
      await TrashService().trash([entry('b')], keep: entry('a'));
      expect(calls.last.arguments['exact'], false);
      expect(calls.last.arguments['keep']['id'], 'a');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(TrashService.channel, null);
    },
  );
  testWidgets(
    'keeper choice required; selecting keeper clears its trash selection',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewPage(
            title: 'Review',
            entries: [entry('a'), entry('b')],
            demo: true,
            requireKeeper: true,
            digest: 'a' * 64,
            explanation: 'test',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
            .onChanged,
        isNull,
      );
      await tester.tap(find.text('Manter esta cópia').first);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
            .onChanged,
        isNull,
      );
      await tester.ensureVisible(find.byType(CheckboxListTile).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile).last);
      await tester.pumpAndSettle();
      expect(find.text('Revisar 1 itens (até 100 por vez)'), findsOneWidget);
      await tester.tap(find.text('Manter esta cópia'));
      await tester.pumpAndSettle();
      expect(find.text('Revisar 0 itens (até 100 por vez)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('review requires explicit consent before system action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewPage(
          title: 'Review',
          entries: [entry('a')],
          demo: true,
          explanation: 'test',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revisar 1 itens (até 100 por vez)'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Simular'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Voltar'));
    await tester.pumpAndSettle();
    expect(find.text('Review'), findsOneWidget);
  });
}
