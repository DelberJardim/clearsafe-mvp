import 'package:safe_scanner/safe_scanner.dart';

class DemoSource implements ReadSource {
  final data = <String, List<int>>{
    'demo-1': List.generate(200000, (i) => i % 251),
    'demo-2': List.generate(200000, (i) => i % 251),
    'demo-3': List.generate(100000, (i) => i % 137),
  };
  Entry entry(String id) => Entry(
    id: id,
    name: '$id.${id == 'demo-3' ? 'mp4' : 'jpg'}',
    size: data[id]!.length,
    kind: id == 'demo-3' ? Kind.video : Kind.photo,
    folder: 'Biblioteca simulada',
    revision: 'demo-v1',
    modified: DateTime(2025, 1, 1),
  );
  @override
  Future<List<Entry>> inventory() async => data.keys.map(entry).toList();
  @override
  Future<Entry?> stat(String id) async =>
      data.containsKey(id) ? entry(id) : null;
  @override
  Stream<List<int>> read(String id) async* {
    final bytes = data[id]!;
    for (var i = 0; i < bytes.length; i += 65536) {
      yield bytes.sublist(i, (i + 65536).clamp(0, bytes.length));
    }
  }
}
