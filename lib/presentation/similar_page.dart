import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:safe_scanner/safe_scanner.dart';

import '../analysis/similarity.dart';
import '../data/visual_source.dart';
import 'review_page.dart';

class SimilarPage extends StatefulWidget {
  final List<Entry> photos;
  final bool demo;
  const SimilarPage({super.key, required this.photos, required this.demo});
  @override
  State<SimilarPage> createState() => _SimilarPageState();
}

class _SimilarPageState extends State<SimilarPage> {
  final signatures = <VisualSignature>[];
  List<List<Entry>> groups = [];
  bool busy = false, cancel = false, changed = false;
  int offset = 0, excluded = 0, failed = 0;
  String message =
      'Analise em lotes de até 250 fotos. A comparação pode demorar; permanece neste aparelho.';
  Future<void> analyze() async {
    if (widget.demo) {
      setState(
        () => message = 'Semelhança exige fotos reais; a biblioteca de demonstração contém apenas bytes sintéticos.',
      );
      return;
    }
    final available = await VisualSource().supported().catchError((_) => false);
    if (!mounted) return;
    if (!available) {
      setState(
        () =>
            message = 'Análise visual desta versão disponível no Android 10+.',
      );
      return;
    }
    setState(() {
      busy = true;
      cancel = false;
    });
    final end = (offset + 250).clamp(0, widget.photos.length);
    try {
      while (offset < end && !cancel && mounted) {
        final e = widget.photos[offset];
        try {
          final signature = VisualSignature(
            e,
            await VisualSource().signature(e.id),
          );
          if (signature.usable) {
            signatures.add(signature);
          } else {
            excluded++;
          }
        } catch (_) {
          failed++;
        }
        if (!mounted) return;
        setState(() {
          offset++;
          message =
              '$offset / ${widget.photos.length} fotos • $excluded protegidas • $failed indisponíveis';
        });
      }
      final result = await compute(similarGroups, signatures);
      if (mounted) setState(() => groups = result);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    cancel = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && busy) setState(() => cancel = true);
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('Fotos semelhantes')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Sugestões por padrões de imagem e cores. Não são duplicatas comprovadas. '
            'Imagens com texto detectado e sinais de documentos/capturas ficam fora dos grupos. '
            'Texto pequeno, desfocado ou manuscrito pode passar despercebido. Confira todas as fotos em tamanho completo.',
          ),
          const SizedBox(height: 16),
          Text(message),
          if (busy) ...[
            const LinearProgressIndicator(),
            TextButton(
              onPressed: () => setState(() => cancel = true),
              child: const Text('Cancelar após esta foto'),
            ),
          ],
          if (!busy && offset < widget.photos.length)
            FilledButton(
              onPressed: analyze,
              child: const Text('Analisar próximo lote de fotos'),
            ),
          Text('${groups.length} grupos sugeridos entre as fotos analisadas.'),
          ...groups.map(
            (g) => Card(
              child: ListTile(
                leading: SizedBox(
                  width: 64,
                  child: MediaPreview(g.first, demo: widget.demo),
                ),
                title: Text('${g.length} fotos parecidas'),
                subtitle: const Text('Comparar e escolher manualmente'),
                onTap: busy
                    ? null
                    : () async {
                        final applied = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ReviewPage(
                              title: 'Comparar fotos semelhantes',
                              entries: g,
                              demo: widget.demo,
                              requireKeeper: true,
                              explanation: 'Semelhança visual não garante o mesmo conteúdo. Escolha qual manter; confira detalhes, pessoas e documentos.',
                            ),
                          ),
                        );
                        if (applied == true && context.mounted) {
                          changed = true;
                          Navigator.pop(context, true);
                        }
                      },
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
