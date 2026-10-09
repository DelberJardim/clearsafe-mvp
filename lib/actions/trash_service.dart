import 'package:flutter/services.dart';
import 'package:safe_scanner/safe_scanner.dart';

/// Separate capability from the scanner. No permanent deletion method exists.
class TrashService {
  static const channel = MethodChannel('clearsafe/recoverable_actions');
  Map<String, Object> snapshot(Entry e) => {
    'id': e.id,
    'name': e.name,
    'size': e.size,
    'revision': e.revision,
  };
  Future<bool> supported() async =>
      await channel.invokeMethod<bool>('supported') ?? false;
  Future<void> cancelValidation() =>
      channel.invokeMethod<void>('cancelValidation');
  Future<List<Map<String, dynamic>>> journal() async =>
      (await channel.invokeListMethod<dynamic>('journal') ?? [])
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
  Future<void> restore(String id) =>
      channel.invokeMethod<void>('restore', {'id': id});
  Future<void> trash(
    List<Entry> selected, {
    Entry? keep,
    String? digest,
  }) async {
    if (selected.isEmpty ||
        selected.length > 100 ||
        selected.map((e) => e.id).toSet().length != selected.length ||
        selected.any((e) => e.id == keep?.id) ||
        (digest != null &&
            (keep == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)))) {
      throw ArgumentError('Invalid selection');
    }
    await channel.invokeMethod<void>('trash', {
      'items': selected.map(snapshot).toList(),
      if (keep != null) 'keep': snapshot(keep),
      'digest': ?digest,
      'exact': digest != null,
    });
  }
}
