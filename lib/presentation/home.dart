import 'package:flutter/material.dart';
import 'package:safe_scanner/safe_scanner.dart';

import '../data/demo_source.dart';
import '../data/native_source.dart';
import 'review_page.dart';
import 'recovery_page.dart';
import 'similar_page.dart';

const accessLabels = {
  Access.full: 'acesso completo',
  Access.limited: 'acesso parcial',
  Access.denied: 'acesso negado',
  Access.restricted: 'acesso restrito',
  Access.unavailable: 'indisponível',
};

const kindLabels = {
  Kind.photo: 'Foto',
  Kind.video: 'Vídeo',
  Kind.audio: 'Áudio',
  Kind.document: 'Documento',
  Kind.other: 'Outro',
};

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final native = NativeSource();
  ScanReport? report;
  List<ContactRecord> contacts = [];
  List<ContactFinding> contactFindings = [];
  bool demo = false, advanced = false, busy = false;
  int minimumMb = 100, age = 0, done = 0, total = 0;
  Set<Kind> kinds = Kind.values.toSet();
  Set<String> ignored = {};
  CancelToken? token;
  String status = 'Escolha uma função para começar.';
  Access mediaAccess = Access.unavailable, contactAccess = Access.unavailable;
  final audit = <String>[];
  Criteria get criteria => Criteria(
    minimumBytes: minimumMb * 1024 * 1024,
    minimumAgeDays: age,
    kinds: kinds,
    ignoredFolders: ignored,
  );
  @override
  void dispose() {
    if (token != null) token!.cancelled = true;
    super.dispose();
  }

  void log(String code) =>
      audit.add('${DateTime.now().toIso8601String()} $code');
  Future<void> scan({bool requestMedia = true}) async {
    if (busy) return;
    log('scan_requested demo=$demo');
    setState(() {
      busy = true;
      report = null;
      done = 0;
      total = 0;
      status = 'Analisando conteúdo acessível…';
    });
    token = CancelToken();
    try {
      if (!demo) {
        mediaAccess = await native.permission('media', request: requestMedia);
        log('media_access=${mediaAccess.name}');
        if (mediaAccess == Access.denied ||
            mediaAccess == Access.restricted ||
            mediaAccess == Access.unavailable) {
          if (mounted) {
            setState(
              () => status = 'Sem acesso à galeria. Você pode analisar documentos selecionados.',
            );
          }
        }
      }
      final result = await Scanner(demo ? DemoSource() : native).scan(
        criteria,
        token: token,
        progress: (d, t) {
          if (mounted) {
            setState(() {
              done = d;
              total = t;
            });
          }
        },
      );
      if (!mounted) return;
      setState(() {
        report = result;
        status = result.cancelled
            ? 'Análise cancelada.'
            : 'Análise concluída do conteúdo acessível. ${result.warnings.length} avisos.';
      });
      for (final line in result.logs) {
        log(line);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => status = 'Não foi possível analisar. Verifique as permissões.',
        );
      }
      log('scan_failed');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> scanContacts() async {
    if (busy) return;
    log('contacts_scan_requested demo=$demo');
    token = null;
    setState(() => busy = true);
    try {
      if (demo) {
        contacts = [
          ContactRecord('1', 'Ana', phones: ['+55 (11) 99999-0000']),
          ContactRecord('2', 'Ana trabalho', phones: ['+5511999990000']),
        ];
      } else {
        contactAccess = await native.permission('contacts', request: true);
        log('contacts_access=${contactAccess.name}');
        contacts =
            (contactAccess == Access.full || contactAccess == Access.limited)
            ? await native.contacts()
            : [];
      }
      contactFindings = analyzeContacts(contacts);
      log('contacts_analyzed=${contacts.length}');
      if (mounted) showContacts();
    } catch (_) {
      if (mounted) {
        setState(() => status = 'Contatos indisponíveis ou acesso revogado.');
      }
      log('contacts_failed');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> selectFiles() async {
    if (busy || demo) return;
    try {
      await NativeSource.channel.invokeMethod<void>('selectDocuments');
      log('documents_selected');
      await scan(requestMedia: false);
    } catch (_) {
      if (mounted) {
        setState(
          () => status = 'Seleção de documentos cancelada ou indisponível.',
        );
      }
    }
  }

  void page(String title, List<Widget> children) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: ListView(padding: const EdgeInsets.all(20), children: children),
      ),
    ),
  );
  String bytes(int n) => n >= 1024 * 1024
      ? '${(n / 1024 / 1024).toStringAsFixed(1)} MB'
      : '${(n / 1024).toStringAsFixed(1)} KB';
  Future<void> review(
    List<Entry> entries,
    String title,
    String explanation, {
    bool keeper = false,
    String? digest,
  }) async {
    final applied = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewPage(
          title: title,
          entries: entries,
          demo: demo,
          requireKeeper: keeper,
          digest: digest,
          explanation: explanation,
        ),
      ),
    );
    if (applied == true && mounted) {
      log('trash_request_completed demo=$demo');
      setState(() {
        report = null;
        status = demo
            ? 'Limpeza simulada. Execute nova análise para recomeçar.'
            : 'Solicitação concluída. Confira Lixeira e recuperação e faça nova análise para atualizar a biblioteca.';
      });
    }
  }

  void showItems(String title, Kind? kind, {bool large = false}) {
    if (report == null) {
      setState(() => status = 'Execute Analisar armazenamento primeiro.');
      return;
    }
    final list =
        (large ? report!.large : report!.entries)
            .where((e) => kind == null || e.kind == kind)
            .toList()
          ..sort((a, b) => b.size.compareTo(a.size));
    if (kind == Kind.photo) {
      page(title, [
        FilledButton.icon(
          icon: const Icon(Icons.compare),
          label: const Text('Encontrar fotos semelhantes'),
          onPressed: () async {
            final changed = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) => SimilarPage(photos: list, demo: demo),
              ),
            );
            if (changed == true && mounted) {
              Navigator.pop(context);
              setState(() {
                report = null;
                status = 'Biblioteca alterada. Confira a lixeira e faça nova análise.';
              });
            }
          },
        ),
        TextButton(
          onPressed: () => review(
            list,
            title,
            'Fotos ordenadas por tamanho. Abra as prévias e escolha manualmente os itens.',
          ),
          child: const Text('Ver todas as fotos e selecionar'),
        ),
      ]);
    } else {
      review(
        list,
        title,
        large
            ? 'Itens pelos filtros de tipo, tamanho e idade, do maior para o menor. Confira o conteúdo antes de selecionar.'
            : 'Vídeos do maior para o menor. Toque na prévia para consultar duração e reproduzir.',
      );
    }
  }

  void showDuplicates() {
    if (report == null) {
      setState(() => status = 'Execute Analisar armazenamento primeiro.');
      return;
    }
    final groups = report!.duplicates;
    page('Duplicados exatos', [
      const Text(
        'Tamanho, SHA-256 e comparação byte a byte confirmados. Escolha qual manter e marque as outras cópias.',
      ),
      if (groups.isEmpty) const Text('Nenhuma duplicata confirmada.'),
      ...groups.map(
        (g) => Card(
          child: ListTile(
            title: Text(
              '${g.entries.length} cópias • ${bytes(g.redundantBytes)} redundantes',
            ),
            subtitle: const Text(
              'Escolher cópia para manter e revisar lixeira',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await review(
                g.entries,
                'Escolher cópia preservada',
                g.explanation,
                keeper: true,
                digest: g.digest,
              );
              if (report == null && mounted) Navigator.pop(context);
            },
          ),
        ),
      ),
    ]);
  }

  void showContacts() => page('Contatos', [
    Text(
      '${contacts.length} contatos acessíveis • ${demo ? 'simulação' : accessLabels[contactAccess]}',
    ),
    const Text('Correspondências são sugestões para revisão, sem mesclagem.'),
    if (contactFindings.isEmpty)
      const Text('Nenhuma correspondência encontrada ou sem acesso.'),
    ...contactFindings.map(
      (f) => Card(
        child: ListTile(
          title: Text(f.contacts.map((c) => c.name).join(' / ')),
          subtitle: Text(f.explanation),
        ),
      ),
    ),
  ]);
  void settings() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, update) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            24 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Configurações',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              SwitchListTile(
                title: const Text('Modo avançado'),
                subtitle: const Text('IDs, versões e hashes no relatório'),
                value: advanced,
                onChanged: (v) {
                  setState(() => advanced = v);
                  update(() {});
                },
              ),
              DropdownButtonFormField<int>(
                initialValue: minimumMb,
                decoration: const InputDecoration(
                  labelText: 'Arquivo grande: tamanho mínimo',
                ),
                items: [1, 10, 50, 100, 500, 1024]
                    .map(
                      (n) => DropdownMenuItem(value: n, child: Text('$n MB')),
                    )
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    minimumMb = v!;
                    report = null;
                  });
                  update(() {});
                },
              ),
              DropdownButtonFormField<int>(
                initialValue: age,
                decoration: const InputDecoration(
                  labelText: 'Idade mínima (data de modificação)',
                ),
                items: [0, 30, 90, 180, 365]
                    .map(
                      (n) => DropdownMenuItem(value: n, child: Text('$n dias')),
                    )
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    age = v!;
                    report = null;
                  });
                  update(() {});
                },
              ),
              Wrap(
                children: Kind.values
                    .map(
                      (k) => FilterChip(
                        label: Text(kindLabels[k]!),
                        selected: kinds.contains(k),
                        onSelected: (v) {
                          setState(() {
                            v ? kinds.add(k) : kinds.remove(k);
                            report = null;
                          });
                          update(() {});
                        },
                      ),
                    )
                    .toList(),
              ),
              TextFormField(
                initialValue: ignored.join(';'),
                decoration: const InputDecoration(
                  labelText: 'Pastas ignoradas (separadas por ;)',
                ),
                onChanged: (v) => setState(() {
                  ignored = v
                      .split(';')
                      .map((s) => s.trim())
                      .where((s) => s.isNotEmpty)
                      .toSet();
                  report = null;
                }),
              ),
              const SizedBox(height: 16),
              const Text(
                'Critérios valem para a próxima análise. Ajustes são mantidos nesta sessão.',
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Concluir'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final tiles = <({String title, IconData icon, VoidCallback action})>[
      (
        title: 'Analisar armazenamento',
        icon: Icons.analytics_outlined,
        action: scan,
      ),
      (
        title: 'Fotos',
        icon: Icons.photo_outlined,
        action: () => showItems('Fotos', Kind.photo),
      ),
      (
        title: 'Vídeos',
        icon: Icons.videocam_outlined,
        action: () => showItems('Vídeos', Kind.video),
      ),
      (
        title: 'Duplicados',
        icon: Icons.copy_all_outlined,
        action: showDuplicates,
      ),
      (
        title: 'Arquivos grandes',
        icon: Icons.folder_outlined,
        action: () => showItems('Arquivos grandes', null, large: true),
      ),
      (title: 'Contatos', icon: Icons.contacts_outlined, action: scanContacts),
      (title: 'Configurações', icon: Icons.tune, action: settings),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('ClearSafe'),
        actions: [
          IconButton(
            tooltip: 'Lixeira e recuperação',
            icon: const Icon(Icons.restore),
            onPressed: busy || demo
                ? null
                : () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(builder: (_) => const RecoveryPage()),
                  ),
          ),
          IconButton(
            tooltip: 'Logs e avisos',
            icon: const Icon(Icons.receipt_long),
            onPressed: () => page('Logs e avisos', [
              ...audit.map((l) => SelectableText(l)),
              ...?(report?.warnings.map((w) => Text(w))),
            ]),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Conheça seu armazenamento',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Versão 0.2 • Limpeza com revisão e lixeira do Android • Contatos somente leitura',
          ),
          const SizedBox(height: 20),
          Card(
            child: SwitchListTile(
              title: const Text('Biblioteca de demonstração'),
              subtitle: Text(
                demo
                    ? 'Dados simulados. Nenhuma permissão necessária.'
                    : 'Biblioteca autorizada neste dispositivo.',
              ),
              value: demo,
              onChanged: busy
                  ? null
                  : (v) => setState(() {
                      demo = v;
                      report = null;
                      contacts = [];
                      contactFindings = [];
                      status = 'Fonte alterada. Execute uma nova análise.';
                    }),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(status),
                  if (busy) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: total > 0 ? done / total : null,
                    ),
                    Text('$done / $total candidatos'),
                    TextButton(
                      onPressed: () => token?.cancelled = true,
                      child: const Text('Cancelar análise'),
                    ),
                  ],
                  if (report != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      '${report!.entries.length} itens • ${bytes(report!.totalBytes)} acessíveis',
                    ),
                    Text(
                      '${report!.duplicates.length} grupos de duplicatas confirmados',
                    ),
                    Text(
                      demo
                          ? 'Relatório simulado'
                          : 'Galeria: ${accessLabels[mediaAccess]}. Documentos: somente os selecionados.',
                    ),
                    const Text(
                      'Este relatório não representa todo o armazenamento do aparelho.',
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (ctx, c) => Wrap(
              spacing: 12,
              runSpacing: 12,
              children: tiles
                  .map(
                    (t) => SizedBox(
                      width: c.maxWidth > 600
                          ? (c.maxWidth - 24) / 3
                          : (c.maxWidth - 12) / 2,
                      child: Card(
                        child: InkWell(
                          onTap: busy ? null : t.action,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(t.icon, size: 30),
                                const SizedBox(height: 14),
                                Text(
                                  t.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          if (!demo)
            TextButton.icon(
              onPressed: busy ? null : selectFiles,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Selecionar documentos para análise'),
            ),
          const SizedBox(height: 20),
          const Text(
            'Análise local. Escolha manual, lixeira com prazo e recuperação no Android 11+. Compressão e alterações de contatos ficam para versões futuras.',
          ),
        ],
      ),
    );
  }
}
