import 'package:flutter/material.dart';

import '../actions/trash_service.dart';

class RecoveryPage extends StatefulWidget {
  const RecoveryPage({super.key});
  @override
  State<RecoveryPage> createState() => _RecoveryPageState();
}

class _RecoveryPageState extends State<RecoveryPage> {
  List<Map<String, dynamic>> rows = [];
  bool busy = true;
  String message = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final value = await TrashService().journal();
      if (mounted) setState(() => rows = value);
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Histórico indisponível. A lixeira exige Android 11+. A recuperação também pode ser feita pela galeria do aparelho.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> restore(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restaurar este item?'),
        content: Text(row['name'] as String),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restaurar no Android'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => busy = true);
    try {
      await TrashService().restore(row['id'] as String);
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'Restauração cancelada ou conteúdo inacessível. Confira a lixeira na galeria e as permissões.',
        );
      }
    }
    await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Lixeira e recuperação'),
      actions: [
        IconButton(
          onPressed: busy
              ? null
              : () {
                  setState(() => busy = true);
                  load();
                },
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'O histórico registra solicitações do ClearSafe. O estado abaixo é consultado no Android. '
          'O sistema pode apagar itens ao vencer o prazo. Não desinstale o app nem limpe seus dados antes de revisar a recuperação.',
        ),
        if (busy) const LinearProgressIndicator(),
        Text(message),
        if (rows.isEmpty && !busy)
          const Text('Nenhuma solicitação registrada.'),
        ...rows.map(
          (r) => Card(
            child: ListTile(
              title: Text(r['name'] as String),
              subtitle: Text(
                '${switch (r['state']) {
                  'trashed' => 'Na lixeira',
                  'active' => 'Na biblioteca (mantido ou restaurado)',
                  'missing' => 'Não encontrado ou não visível; consulte a galeria',
                  _ => 'Estado indisponível; consulte a galeria',
                }}\n${r['expires'] == null ? 'Prazo não disponível' : 'Prazo informado: ${DateTime.fromMillisecondsSinceEpoch((r['expires'] as num).toInt()).toLocal()}'}',
              ),
              trailing: r['state'] == 'trashed'
                  ? IconButton(
                      tooltip: 'Restaurar',
                      icon: const Icon(Icons.restore),
                      onPressed: busy ? null : () => restore(r),
                    )
                  : null,
            ),
          ),
        ),
      ],
    ),
  );
}
