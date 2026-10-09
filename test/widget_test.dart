import 'package:clearsafe/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Home exposes seven functions and read-only demonstration', (
    tester,
  ) async {
    await tester.pumpWidget(const ClearSafeApp());
    expect(find.text('ClearSafe'), findsOneWidget);
    expect(find.textContaining('Somente leitura'), findsOneWidget);
    expect(find.text('Biblioteca de demonstração'), findsOneWidget);
    for (final label in [
      'Analisar armazenamento',
      'Fotos',
      'Vídeos',
      'Duplicados',
      'Arquivos grandes',
      'Contatos',
      'Configurações',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile).first).value,
      isTrue,
    );
    expect(find.text('Excluir'), findsNothing);
  });
  testWidgets('Demo scan reports confirmed duplicates and opens explanation', (
    tester,
  ) async {
    await tester.pumpWidget(const ClearSafeApp());
    await tester.ensureVisible(find.text('Analisar armazenamento'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Analisar armazenamento'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, 700));
    await tester.pumpAndSettle();
    expect(find.text('1 grupos de duplicatas confirmados'), findsOneWidget);
    await tester.ensureVisible(find.text('Duplicados'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicados'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 cópias'), findsOneWidget);
    await tester.tap(find.textContaining('2 cópias'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('comparação byte a byte confirmada'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
