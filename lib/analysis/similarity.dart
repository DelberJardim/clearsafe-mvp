import 'package:safe_scanner/safe_scanner.dart';

class VisualSignature {
  final Entry entry;
  final String bits;
  final List<double> colors;
  final double aspect;
  final bool protected;
  VisualSignature(this.entry, Map<dynamic, dynamic> m)
    : bits = m['bits'] as String? ?? '',
      colors = (m['colors'] as List? ?? [])
          .map((v) => (v as num).toDouble())
          .toList(),
      aspect = (m['aspect'] as num?)?.toDouble() ?? 0,
      protected = m['protected'] != false;
  bool get usable =>
      !protected &&
      entry.kind == Kind.photo &&
      !RegExp(
        r'screenshot|screen.?shot|captura|document|scan',
        caseSensitive: false,
      ).hasMatch('${entry.folder}/${entry.name}') &&
      RegExp(r'^[01]{64}$').hasMatch(bits) &&
      bits.split('').where((v) => v == '1').length >= 4 &&
      bits.split('').where((v) => v == '1').length <= 60 &&
      colors.length == 12 &&
      colors.every((v) => v.isFinite && v >= 0 && v <= 1) &&
      (colors.fold<double>(0, (a, b) => a + b) - 1).abs() < .01 &&
      aspect > 0 &&
      aspect.isFinite;
}

bool resembles(VisualSignature a, VisualSignature b) {
  if (!a.usable || !b.usable || a.entry.id == b.entry.id) return false;
  if ((a.aspect - b.aspect).abs() / a.aspect > .05) return false;
  var distance = 0;
  for (var i = 0; i < 64; i++) {
    if (a.bits[i] != b.bits[i]) distance++;
  }
  var color = 0.0;
  for (var i = 0; i < 12; i++) {
    color += (a.colors[i] - b.colors[i]).abs();
  }
  return distance <= 6 && color <= .12;
}

/// Complete-link groups: no chain A~B~C unless every pair resembles each other.
List<List<Entry>> similarGroups(List<VisualSignature> signatures) {
  final groups = <List<VisualSignature>>[];
  for (final value in signatures.where((s) => s.usable)) {
    if (groups.any((g) => g.any((s) => s.entry.id == value.entry.id))) continue;
    final index = groups.indexWhere(
      (g) => g.length < 10 && g.every((s) => resembles(s, value)),
    );
    if (index < 0) {
      groups.add([value]);
    } else {
      groups[index].add(value);
    }
  }
  return groups
      .where((g) => g.length > 1)
      .map((g) => g.map((s) => s.entry).toList())
      .toList();
}
