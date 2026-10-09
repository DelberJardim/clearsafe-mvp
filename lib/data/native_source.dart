import 'package:flutter/services.dart';
import 'package:safe_scanner/safe_scanner.dart';

class NativeSource implements ReadSource, InventoryDiagnostics {
  static const channel = MethodChannel('clearsafe/read_only');
  @override
  Future<List<String>> inventoryWarnings() async =>
      await channel.invokeListMethod<String>('diagnostics') ?? [];
  Entry parse(Map<dynamic, dynamic> m) => Entry(
    id: m['id'] as String,
    name: m['name'] as String,
    size: (m['size'] as num).toInt(),
    kind: Kind.values.firstWhere(
      (k) => k.name == m['kind'],
      orElse: () => Kind.other,
    ),
    revision: m['revision'] as String,
    folder: m['folder'] as String? ?? '',
    modified: m['modified'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((m['modified'] as num).toInt()),
  );
  Future<Access> permission(String scope, {bool request = false}) async {
    final value = await channel.invokeMethod<String>(
      request ? 'requestPermission' : 'permission',
      {'scope': scope},
    );
    return Access.values.firstWhere(
      (a) => a.name == value,
      orElse: () => Access.unavailable,
    );
  }

  @override
  Future<List<Entry>> inventory() async {
    final all = <Entry>[];
    var offset = 0;
    while (true) {
      final page =
          await channel.invokeListMethod<dynamic>('inventory', {
            'offset': offset,
            'limit': 200,
          }) ??
          [];
      all.addAll(page.map((e) => parse(e as Map)));
      if (page.length < 200) break;
      offset += page.length;
    }
    return all;
  }

  @override
  Future<Entry?> stat(String id) async {
    final value = await channel.invokeMapMethod<dynamic, dynamic>('stat', {
      'id': id,
    });
    return value == null ? null : parse(value);
  }

  @override
  Stream<List<int>> read(String id) async* {
    final handle = await channel.invokeMethod<String>('open', {'id': id});
    if (handle == null) throw StateError('Unavailable');
    try {
      while (true) {
        final chunk = await channel.invokeMethod<Uint8List>('read', {
          'handle': handle,
        });
        if (chunk == null) throw StateError('Missing chunk');
        if (chunk.isEmpty) break;
        yield chunk;
      }
    } finally {
      await channel.invokeMethod<void>('close', {'handle': handle});
    }
  }

  Future<List<ContactRecord>> contacts() async {
    final records = await channel.invokeListMethod<dynamic>('contacts') ?? [];
    return records.map((v) {
      final m = v as Map;
      return ContactRecord(
        m['id'] as String,
        m['name'] as String,
        phones: List<String>.from(m['phones'] as List),
        emails: List<String>.from(m['emails'] as List),
      );
    }).toList();
  }
}
