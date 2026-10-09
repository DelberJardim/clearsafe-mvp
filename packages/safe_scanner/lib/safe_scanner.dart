library;

import 'dart:async';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

enum Kind { photo, video, audio, document, other }

enum Access { full, limited, denied, restricted, unavailable }

class Entry {
  final String id, name, folder, revision;
  final int size;
  final Kind kind;
  final DateTime? modified;
  const Entry(
      {required this.id,
      required this.name,
      required this.size,
      required this.kind,
      required this.revision,
      this.folder = '',
      this.modified});
}

/// No write, delete, rename, merge or compression capability exists here.
abstract interface class ReadSource {
  Future<List<Entry>> inventory();
  Future<Entry?> stat(String id);
  Stream<List<int>> read(String id);
}

abstract interface class InventoryDiagnostics {
  Future<List<String>> inventoryWarnings();
}

class CancelToken {
  bool cancelled = false;
  void check() {
    if (cancelled) throw const ScanCancelled();
  }
}

class ScanCancelled implements Exception {
  const ScanCancelled();
}

class Criteria {
  final int minimumBytes, minimumAgeDays;
  final Set<Kind> kinds;
  final Set<String> ignoredFolders;
  Criteria(
      {this.minimumBytes = 100 * 1024 * 1024,
      this.minimumAgeDays = 0,
      Set<Kind>? kinds,
      Set<String> ignoredFolders = const {}})
      : ignoredFolders = Set.unmodifiable(ignoredFolders),
        kinds = Set.unmodifiable(kinds ?? Kind.values.toSet()) {
    if (minimumBytes < 0 || minimumAgeDays < 0) {
      throw ArgumentError('Negative criterion');
    }
  }
  bool includes(Entry e) =>
      kinds.contains(e.kind) &&
      !ignoredFolders.any(
          (f) => f.isNotEmpty && (e.folder == f || e.folder.startsWith('$f/')));
  bool large(Entry e, DateTime now) =>
      e.size >= minimumBytes &&
      (minimumAgeDays == 0 ||
          (e.modified != null &&
              !e.modified!
                  .isAfter(now.subtract(Duration(days: minimumAgeDays)))));
}

class DuplicateGroup {
  final List<Entry> entries;
  final String digest;
  DuplicateGroup(List<Entry> entries, this.digest)
      : entries = List.unmodifiable(entries);
  int get redundantBytes => entries.first.size * (entries.length - 1);
  String get explanation =>
      'Tamanho igual (${entries.first.size} bytes), SHA-256 igual '
      'e comparação byte a byte confirmada. Versões verificadas antes e depois da leitura. '
      'Resultado válido para o momento da análise; nenhuma cópia é escolhida para remoção.';
}

class ScanReport {
  final List<Entry> entries, large;
  final List<DuplicateGroup> duplicates;
  final List<String> warnings, logs;
  final DateTime started, finished;
  final bool cancelled;
  ScanReport(
      {required List<Entry> entries,
      required List<Entry> large,
      required List<DuplicateGroup> duplicates,
      required List<String> warnings,
      required List<String> logs,
      required this.started,
      required this.finished,
      this.cancelled = false})
      : entries = List.unmodifiable(entries),
        large = List.unmodifiable(large),
        duplicates = List.unmodifiable(duplicates),
        warnings = List.unmodifiable(warnings),
        logs = List.unmodifiable(logs);
  int get totalBytes => entries.fold(0, (n, e) => n + e.size);
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}

class Scanner {
  final ReadSource source;
  final DateTime Function() clock;
  // Injection enables a real hash-collision regression test.
  final Future<String> Function(Entry, CancelToken)? testHasher;
  Scanner(this.source, {DateTime Function()? clock, this.testHasher})
      : clock = clock ?? DateTime.now;
  bool _same(Entry a, Entry? b) =>
      b != null && a.id == b.id && a.size == b.size && a.revision == b.revision;
  Future<void> _stable(Entry e) async {
    if (!_same(e, await source.stat(e.id))) throw StateError('changed');
  }

  Future<String> _hash(Entry e, CancelToken token) async {
    await _stable(e);
    final out = _DigestSink();
    final sink = sha256.startChunkedConversion(out);
    var count = 0;
    try {
      await for (final chunk in source.read(e.id)) {
        token.check();
        count += chunk.length;
        if (count > e.size) throw StateError('changed');
        sink.add(chunk);
      }
    } finally {
      sink.close();
    }
    if (count != e.size) throw StateError('short read');
    await _stable(e);
    return out.value.toString();
  }

  // Chunk boundaries may differ between providers. Compare fixed windows.
  Stream<Uint8List> _windows(String id, CancelToken token) async* {
    var buffer = Uint8List(65536);
    var used = 0;
    await for (final chunk in source.read(id)) {
      token.check();
      var offset = 0;
      while (offset < chunk.length) {
        final n = (chunk.length - offset).clamp(0, buffer.length - used);
        buffer.setRange(used, used + n, chunk, offset);
        used += n;
        offset += n;
        if (used == buffer.length) {
          yield buffer;
          buffer = Uint8List(65536);
          used = 0;
        }
      }
    }
    if (used > 0) yield Uint8List.sublistView(buffer, 0, used);
  }

  Future<bool> _equal(Entry a, Entry b, CancelToken token) async {
    await _stable(a);
    await _stable(b);
    final left = StreamIterator(_windows(a.id, token));
    final right = StreamIterator(_windows(b.id, token));
    var count = 0;
    try {
      while (true) {
        token.check();
        final x = await left.moveNext();
        final y = await right.moveNext();
        if (x != y) return false;
        if (!x) break;
        if (left.current.length != right.current.length) return false;
        count += left.current.length;
        for (var i = 0; i < left.current.length; i++) {
          if (left.current[i] != right.current[i]) return false;
        }
      }
      if (count != a.size) throw StateError('short read');
      await _stable(a);
      await _stable(b);
      return true;
    } finally {
      await left.cancel();
      await right.cancel();
    }
  }

  Future<ScanReport> scan(Criteria criteria,
      {CancelToken? token,
      void Function(int done, int total)? progress}) async {
    final cancel = token ?? CancelToken();
    final start = clock();
    final warnings = <String>[];
    final logs = <String>['scan_started'];
    final entries = <Entry>[];
    final groups = <DuplicateGroup>[];
    var cancelled = false;
    try {
      cancel.check();
      final seen = <String>{};
      final inventory = await source.inventory();
      if (source is InventoryDiagnostics) {
        warnings
            .addAll(await (source as InventoryDiagnostics).inventoryWarnings());
      }
      for (final e in inventory) {
        cancel.check();
        if (!seen.add(e.id)) continue;
        if (e.size < 0) {
          warnings.add('Metadado inválido; item ignorado.');
          continue;
        }
        if (criteria.includes(e)) entries.add(e);
      }
      final sizes = <int, List<Entry>>{};
      for (final e in entries) {
        sizes.putIfAbsent(e.size, () => []).add(e);
      }
      var done = 0;
      final candidates =
          sizes.values.where((g) => g.length > 1).expand((g) => g).toList();
      final hashes = <String, List<Entry>>{};
      for (final e in candidates) {
        cancel.check();
        try {
          if (e.revision == 'unversioned') {
            throw StateError(
                'Provider does not expose a trustworthy content version');
          }
          final hash = testHasher == null
              ? await _hash(e, cancel)
              : await testHasher!(e, cancel);
          hashes.putIfAbsent('${e.size}:$hash', () => []).add(e);
        } on ScanCancelled {
          rethrow;
        } catch (_) {
          warnings.add(
              'Item indisponível ou alterado durante a leitura; ignorado.');
        }
        progress?.call(++done, candidates.length);
      }
      for (final bucket in hashes.values) {
        final partitions = <List<Entry>>[];
        for (final e in bucket) {
          cancel.check();
          var matched = false;
          try {
            for (final p in partitions) {
              if (await _equal(p.first, e, cancel)) {
                p.add(e);
                matched = true;
                break;
              }
            }
            if (!matched) partitions.add([e]);
          } on ScanCancelled {
            rethrow;
          } catch (_) {
            warnings.add('Comparação inconclusiva; item ignorado.');
          }
        }
        for (final p in partitions.where((p) => p.length > 1)) {
          cancel.check();
          var stable = true;
          for (final e in p) {
            try {
              await _stable(e);
            } catch (_) {
              stable = false;
            }
          }
          cancel.check();
          if (stable) {
            groups.add(DuplicateGroup(
                p,
                hashes.keys
                    .firstWhere((k) => identical(hashes[k], bucket))
                    .split(':')
                    .last));
          } else {
            warnings.add('Grupo alterado durante a análise; descartado.');
          }
        }
      }
    } on ScanCancelled {
      cancelled = true;
      groups.clear();
      logs.add('scan_cancelled');
    } catch (_) {
      warnings.add('Inventário incompleto ou acesso revogado.');
      logs.add('scan_incomplete');
    }
    final large = entries.where((e) => criteria.large(e, start)).toList()
      ..sort((a, b) => b.size.compareTo(a.size));
    logs.add(
        'scan_finished: items=${entries.length}, groups=${groups.length}, warnings=${warnings.length}');
    return ScanReport(
        entries: entries,
        large: large,
        duplicates: groups,
        warnings: warnings,
        logs: logs,
        started: start,
        finished: clock(),
        cancelled: cancelled);
  }
}

class ContactRecord {
  final String id, name;
  final List<String> phones, emails;
  ContactRecord(this.id, this.name,
      {this.phones = const [], this.emails = const []});
}

class ContactFinding {
  final List<ContactRecord> contacts;
  final String explanation;
  ContactFinding(this.contacts, this.explanation);
}

List<ContactFinding> analyzeContacts(List<ContactRecord> contacts) {
  final keys = <String, Map<String, ContactRecord>>{};
  for (final c in contacts) {
    // Conservative: formatting removal only. No country-code guessing.
    for (final phone in c.phones) {
      final normalized = phone.replaceAll(RegExp(r'[\s().-]'), '');
      if (RegExp(r'^\+?[0-9]{7,15}$').hasMatch(normalized)) {
        keys.putIfAbsent('telefone:$normalized', () => {})[c.id] = c;
      }
    }
    for (final email in c.emails) {
      final normalized =
          email.trim(); // Preserve case; avoid false equivalence.
      if (normalized.contains('@')) {
        keys.putIfAbsent('email:$normalized', () => {})[c.id] = c;
      }
    }
  }
  return keys.entries
      .where((e) => e.value.length > 1)
      .map((e) => ContactFinding(
          e.value.values.toList(),
          'Mesmo ${e.key.startsWith('telefone:') ? 'telefone após remover formatação' : 'email literal'}. '
          'Possível compartilhamento; isso não comprova que são a mesma pessoa. Revisão manual necessária.'))
      .toList();
}
