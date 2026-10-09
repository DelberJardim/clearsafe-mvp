import 'dart:typed_data';
import 'package:safe_scanner/safe_scanner.dart';
import 'package:test/test.dart';

class FakeSource implements ReadSource {
  final Map<String, List<int>> bytes;
  final Set<String> fail = {};
  final Set<String> changed = {};
  final Map<String, int> reads = {};
  FakeSource(this.bytes);
  Entry entry(String id) => Entry(
      id: id,
      name: 'same-name',
      size: bytes[id]!.length,
      kind: Kind.photo,
      revision: changed.contains(id) ? '2' : '1',
      folder: 'Camera',
      modified: DateTime.utc(2020));
  @override
  Future<List<Entry>> inventory() async => bytes.keys.map(entry).toList();
  @override
  Future<Entry?> stat(String id) async =>
      bytes.containsKey(id) ? entry(id) : null;
  @override
  Stream<List<int>> read(String id) async* {
    reads[id] = (reads[id] ?? 0) + 1;
    if (fail.contains(id)) throw StateError('revoked');
    final data = bytes[id]!;
    final width = id.hashCode % 17 + 1;
    for (var n = 0; n < data.length; n += width) {
      yield data.sublist(n, (n + width).clamp(0, data.length));
    }
  }
}

class ShortSource extends FakeSource {
  ShortSource(super.bytes);
  @override
  Stream<List<int>> read(String id) async* {
    yield [1];
  }
}

class UnversionedSource extends FakeSource {
  UnversionedSource(super.bytes);
  @override
  Entry entry(String id) => Entry(
      id: id,
      name: id,
      size: bytes[id]!.length,
      kind: Kind.document,
      revision: 'unversioned');
}

class CancelAtFinalStat extends FakeSource {
  final CancelToken token;
  int stats = 0;
  CancelAtFinalStat(super.bytes, this.token);
  @override
  Future<Entry?> stat(String id) async {
    if (++stats == 9) token.cancelled = true;
    return super.stat(id);
  }
}

void main() {
  test('cancellation during final version validation discards group', () async {
    final token = CancelToken();
    final report = await Scanner(CancelAtFinalStat({
      'a': [1],
      'b': [1]
    }, token))
        .scan(Criteria(), token: token);
    expect(report.cancelled, isTrue);
    expect(report.duplicates, isEmpty);
  });
  test('truncated stream cannot confirm duplicates', () async {
    final r = await Scanner(ShortSource({
      'a': [1, 2],
      'b': [1, 2]
    })).scan(Criteria());
    expect(r.duplicates, isEmpty);
    expect(r.warnings.length, 2);
  });
  test('unversioned documents appear but are never confirmed duplicates',
      () async {
    final r = await Scanner(UnversionedSource({
      'a': [1],
      'b': [1]
    })).scan(Criteria(minimumBytes: 1));
    expect(r.entries.length, 2);
    expect(r.large.length, 2);
    expect(r.duplicates, isEmpty);
    expect(r.warnings, isNotEmpty);
  });
  test('empty library and empty files are handled', () async {
    expect((await Scanner(FakeSource({})).scan(Criteria())).entries, isEmpty);
    expect(
        (await Scanner(FakeSource({'a': [], 'b': []})).scan(Criteria()))
            .duplicates
            .single
            .entries
            .length,
        2);
  });
  test('same names/size do not imply duplicate; unequal chunk boundaries work',
      () async {
    final s = FakeSource({
      'a': [1, 2, 3],
      'b': [1, 2, 3],
      'c': [3, 2, 1],
      'd': [0]
    });
    final r = await Scanner(s).scan(Criteria());
    expect(r.duplicates.single.entries.map((e) => e.id), ['a', 'b']);
    expect(s.reads['d'], isNull);
  });
  test('forced hash collision cannot produce false duplicate', () async {
    final r = await Scanner(
        FakeSource({
          'a': [1, 2],
          'b': [2, 1]
        }),
        testHasher: (_, __) async => 'collision').scan(Criteria());
    expect(r.duplicates, isEmpty);
  });
  test('read failure is reported and excluded', () async {
    final s = FakeSource({
      'a': [1],
      'b': [1]
    })
      ..fail.add('b');
    final r = await Scanner(s).scan(Criteria());
    expect(r.duplicates, isEmpty);
    expect(r.warnings, isNotEmpty);
  });
  test('changed revision excluded', () async {
    final s = FakeSource({
      'a': [1],
      'b': [1]
    });
    final r = await Scanner(s, testHasher: (e, t) async {
      s.changed.add(e.id);
      return 'same';
    }).scan(Criteria());
    expect(r.duplicates, isEmpty);
    expect(r.warnings, isNotEmpty);
  });
  test('cancellation discards confirmed groups', () async {
    final token = CancelToken()..cancelled = true;
    final r = await Scanner(FakeSource({
      'a': [1]
    })).scan(Criteria(), token: token);
    expect(r.cancelled, isTrue);
    expect(r.duplicates, isEmpty);
  });
  test('filters honor kind, size, age and folder boundaries', () async {
    final s = FakeSource({
      'a': [1, 2],
      'b': [2, 1],
      'c': [3]
    });
    final r = await Scanner(s, clock: () => DateTime.utc(2026))
        .scan(Criteria(minimumBytes: 2, minimumAgeDays: 30));
    expect(r.large.length, 2);
    expect(
        (await Scanner(s).scan(Criteria(ignoredFolders: {'Cam'})))
            .entries
            .length,
        3);
    expect(
        (await Scanner(s).scan(Criteria(ignoredFolders: {'Camera'}))).entries,
        isEmpty);
    expect((await Scanner(s).scan(Criteria(kinds: {Kind.video}))).entries,
        isEmpty);
  });
  test('3000 simulated copies produce one stable group', () async {
    final s = FakeSource({
      for (var i = 0; i < 3000; i++) '$i': Uint8List.fromList([1, 2, 3, 4])
    });
    final r = await Scanner(s).scan(Criteria());
    expect(r.duplicates.single.entries.length, 3000);
    expect(r.duplicates.single.redundantBytes, 11996);
  });
  test('contacts are suggestions; no name-only or country-code guessing', () {
    final r = analyzeContacts([
      ContactRecord('a', 'Ana', phones: ['+55 (11) 99999-0000']),
      ContactRecord('b', 'Bia', phones: ['+5511999990000']),
      ContactRecord('c', 'Ana', phones: ['11999990000']),
      ContactRecord('d', 'Ana')
    ]);
    expect(r.single.contacts.map((c) => c.id), ['a', 'b']);
    expect(r.single.explanation, contains('não comprova'));
  });
}
