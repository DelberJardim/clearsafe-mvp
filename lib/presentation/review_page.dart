import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safe_scanner/safe_scanner.dart';

import '../actions/trash_service.dart';
import '../data/visual_source.dart';

String formatBytes(int n) => '${(n / 1024 / 1024).toStringAsFixed(1)} MB';

class MediaPreview extends StatefulWidget {
  final Entry entry;
  final bool demo;
  const MediaPreview(this.entry, {super.key, required this.demo});
  @override
  State<MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends State<MediaPreview> {
  late Future<Uint8List?> bytes;
  void load() {
    bytes = widget.demo
        ? Future.value(null)
        : VisualSource().preview(widget.entry.id).catchError((_) => null);
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant MediaPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.id != widget.entry.id ||
        oldWidget.entry.revision != widget.entry.revision ||
        oldWidget.demo != widget.demo) {
      load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: bytes,
    builder: (_, value) =>
        value.connectionState != ConnectionState.done || value.data == null
        ? SizedBox(
            height: 100,
            child: Icon(
              widget.entry.kind == Kind.video ? Icons.videocam : Icons.image,
              size: 48,
            ),
          )
        : Image.memory(
            value.data!,
            height: 150,
            width: double.infinity,
            fit: BoxFit.contain,
            cacheHeight: 300,
          ),
  );
}

Future<void> inspectMedia(BuildContext context, Entry e, bool demo) async {
  final details = demo
      ? <dynamic, dynamic>{}
      : await VisualSource()
            .details(e.id)
            .catchError((_) => <dynamic, dynamic>{});
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(e.name),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: MediaPreview(e, demo: demo),
            ),
            Text('${formatBytes(e.size)} • ${e.folder}'),
            Text('Data: ${e.modified?.toLocal().toString() ?? 'indisponível'}'),
            if (details['width'] != null)
              Text('${details['width']} × ${details['height']} pixels'),
            if ((details['duration'] as num? ?? 0) > 0)
              Text(
                'Duração: ${Duration(milliseconds: (details['duration'] as num).toInt()).toString().split('.').first}',
              ),
            const Text(
              'Abra a imagem completa ou reproduza o vídeo antes de escolher.',
            ),
          ],
        ),
      ),
      actions: [
        if (!demo)
          TextButton(
            onPressed: () async {
              try {
                await VisualSource().view(e.id);
              } catch (_) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Visualizador indisponível.')),
                  );
                }
              }
            },
            child: const Text('Abrir / reproduzir'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
}

class ReviewPage extends StatefulWidget {
  final String title, explanation;
  final List<Entry> entries;
  final bool demo, requireKeeper, advanced;
  final String? digest;
  const ReviewPage({
    super.key,
    required this.title,
    required this.entries,
    required this.demo,
    this.requireKeeper = false,
    this.advanced = false,
    this.digest,
    required this.explanation,
  });
  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  final selected = <String>{};
  String? keeper;
  bool busy = false;
  int page = 0;
  String message = '';
  late final Future<bool> supported = widget.demo
      ? Future.value(true)
      : TrashService().supported().catchError((_) => false);
  Future<void> submit() async {
    final targets = widget.entries
        .where((e) => selected.contains(e.id))
        .toList();
    if (targets.isEmpty || (widget.requireKeeper && keeper == null)) return;
    final preserved = keeper == null
        ? null
        : widget.entries.firstWhere((e) => e.id == keeper);
    var inspected = false;
    final consent = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Revisar envio à lixeira'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (preserved != null)
                    Text('MANTER: ${preserved.name}\n${preserved.folder}'),
                  Text(
                    '${targets.length} itens selecionados • ${formatBytes(targets.fold(0, (n, e) => n + e.size))}',
                  ),
                  ...targets.map(
                    (e) => ListTile(
                      dense: true,
                      title: Text(e.name),
                      subtitle: Text(e.folder),
                      onTap: () => inspectMedia(ctx, e, widget.demo),
                    ),
                  ),
                  const Text(
                    'A lixeira tem prazo definido pelo sistema; após expirar, os itens podem ser apagados pelo Android. '
                    'Ela pode continuar ocupando espaço até a expiração. Não esvazie a lixeira antes de conferir.',
                  ),
                  if (widget.digest == null)
                    const Text(
                      'Semelhança e tamanho não comprovam inutilidade. Documentos podem diferir por uma assinatura ou número.',
                    ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: inspected,
                    title: const Text(
                      'Conferi os itens selecionados e quero enviá-los à lixeira.',
                    ),
                    onChanged: (v) => update(() => inspected = v ?? false),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: inspected ? () => Navigator.pop(ctx, true) : null,
              child: Text(widget.demo ? 'Simular' : 'Continuar no Android'),
            ),
          ],
        ),
      ),
    );
    if (consent != true || !mounted) return;
    setState(() {
      busy = true;
      message = widget.digest != null
          ? 'Conferindo novamente o conteúdo das cópias…'
          : 'Validando conteúdo e registrando recuperação…';
    });
    try {
      if (!widget.demo) {
        await TrashService().trash(
          targets,
          keep: preserved,
          digest: widget.digest,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on PlatformException catch (e) {
      if (mounted) {
        setState(
          () => message = e.message ?? 'Ação bloqueada. Analise novamente.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'Ação bloqueada. Confira as permissões e analise novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final start = page * 40;
    final items = widget.entries.skip(start).take(40).toList();
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(widget.explanation),
            if (widget.advanced && widget.digest != null)
              SelectableText('SHA-256 confirmado: ${widget.digest}'),
            if (widget.demo)
              const Text('SIMULAÇÃO: nenhum arquivo real será alterado.'),
            if (widget.requireKeeper)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '1. Escolha uma cópia para manter.\n2. Marque individualmente as cópias que deseja enviar à lixeira.',
                ),
              ),
            ...items.map(
              (e) => Card(
                child: Column(
                  children: [
                    InkWell(
                      onTap: busy
                          ? null
                          : () => inspectMedia(context, e, widget.demo),
                      child: MediaPreview(e, demo: widget.demo),
                    ),
                    ListTile(
                      title: Text(e.name),
                      subtitle: Text(
                        '${formatBytes(e.size)} • ${e.folder}\n${e.modified?.toLocal().toString() ?? 'Sem data'}',
                      ),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: busy
                          ? null
                          : () => inspectMedia(context, e, widget.demo),
                    ),
                    if (widget.requireKeeper)
                      TextButton.icon(
                        icon: Icon(
                          keeper == e.id
                              ? Icons.verified_user
                              : Icons.shield_outlined,
                        ),
                        label: Text(
                          keeper == e.id
                              ? 'Esta cópia será mantida'
                              : 'Manter esta cópia',
                        ),
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                keeper = e.id;
                                selected.remove(e.id);
                              }),
                      ),
                    CheckboxListTile(
                      value: selected.contains(e.id),
                      title: const Text('Selecionar para lixeira'),
                      onChanged:
                          busy ||
                              (!widget.demo &&
                                  (!e.id.startsWith(
                                        'content://media/external/file/',
                                      ) ||
                                      (e.kind != Kind.photo &&
                                          e.kind != Kind.video))) ||
                              e.id == keeper ||
                              (widget.requireKeeper && keeper == null) ||
                              (!selected.contains(e.id) &&
                                  selected.length >= 100)
                          ? null
                          : (v) => setState(() {
                              v == true
                                  ? selected.add(e.id)
                                  : selected.remove(e.id);
                            }),
                    ),
                    if (widget.advanced)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          'ID: ${e.id}\nVersão analisada: ${e.revision}',
                        ),
                      ),
                    if (!widget.demo &&
                        !e.id.startsWith('content://media/external/file/'))
                      const Text(
                        'Este provedor permite apenas análise nesta versão.',
                      ),
                  ],
                ),
              ),
            ),
            if (widget.entries.length > 40)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: !busy && page > 0
                        ? () => setState(() => page--)
                        : null,
                    child: const Text('Anterior'),
                  ),
                  Text(
                    '${start + 1}–${start + items.length} / ${widget.entries.length}',
                  ),
                  TextButton(
                    onPressed: !busy && start + 40 < widget.entries.length
                        ? () => setState(() => page++)
                        : null,
                    child: const Text('Próxima'),
                  ),
                ],
              ),
            if (widget.entries.isEmpty) const Text('Nenhum item encontrado.'),
            if (busy) const LinearProgressIndicator(),
            if (busy && !widget.demo)
              TextButton(
                onPressed: () => TrashService().cancelValidation(),
                child: const Text('Cancelar verificação antes da confirmação'),
              ),
            if (message.isNotEmpty) Text(message),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: FutureBuilder<bool>(
              future: supported,
              builder: (_, value) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (value.data == false)
                    const Text(
                      'Lixeira disponível no Android 11+. Neste aparelho, use as prévias e a galeria.',
                    ),
                  FilledButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    onPressed:
                        value.data == true &&
                            !busy &&
                            selected.isNotEmpty &&
                            (!widget.requireKeeper || keeper != null)
                        ? submit
                        : null,
                    label: Text(
                      'Revisar ${selected.length} itens (até 100 por vez)',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
