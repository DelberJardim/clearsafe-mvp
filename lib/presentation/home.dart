import 'package:flutter/material.dart';
import 'package:safe_scanner/safe_scanner.dart';

import '../data/demo_source.dart';
import '../data/native_source.dart';

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
  bool demo = true, advanced = false, busy = false;
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
  Widget entry(Entry e, String why) => Card(
    child: ListTile(
      title: Text(e.name),
      subtitle: Text('${bytes(e.size)} • ${kindLabels[e.kind]}'),
      trailing: const Icon(Icons.info_outline),
      onTap: () => page('Por que este item foi marcado?', [
        Text(e.name, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        Text(why),
        const SizedBox(height: 16),
        Text('Pasta: ${e.folder.isEmpty ? 'Não informada' : e.folder}'),
        Text('Data: ${e.modified?.toIso8601String() ?? 'Não disponível'}'),
        if (advanced) ...[Text('ID: ${e.id}'), Text('Versão: ${e.revision}')],
        const SizedBox(height: 20),
        const Text('Nenhuma ação de alteração está disponível nesta versão.'),
      ]),
    ),
  );
  void showItems(String title, Kind? kind, {bool large = false}) {
    if (report == null) {
      setState(() => status = 'Execute Analisar armazenamento primeiro.');
      return;
    }
    final list = (large ? report!.large : report!.entries)
        .where((e) => kind == null || e.kind == kind)
        .toList();
    page(title, [
      Text(
        '${list.length} itens no relatório • ${demo ? 'dados simulados' : 'conteúdo autorizado'}',
      ),
      const SizedBox(height: 12),
      if (list.isEmpty)
        const Text('Nenhum item encontrado pelos critérios atuais.'),
      ...list.map(
        (e) => entry(
          e,
          large
              ? 'Tamanho igual ou superior a $minimumMb MB; idade mínima $age dias; tipo incluído nos filtros.'
              : 'Item de mídia acessível, classificado por tipo. Não foi avaliada semelhança visual.',
        ),
      ),
    ]);
  }

  void showDuplicates() {
    if (report == null) {
      setState(() => status = 'Execute Analisar armazenamento primeiro.');
      return;
    }
    page('Duplicados exatos', [
      const Text(
        'Confirmação por tamanho, SHA-256 e conteúdo. Estimativa de bytes redundantes; nenhum espaço foi liberado.',
      ),
      if (report!.duplicates.isEmpty)
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text('Nenhuma duplicata confirmada.'),
        ),
      ...report!.duplicates.map(
        (g) => Card(
          child: ExpansionTile(
            title: Text(
              '${g.entries.length} cópias • ${bytes(g.redundantBytes)} redundantes',
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(g.explanation),
              ),
              if (advanced)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText('SHA-256: ${g.digest}'),
                ),
              ...g.entries.map((e) => entry(e, g.explanation)),
            ],
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
            'MVP 0.1 • Somente leitura • Nenhum arquivo ou contato é alterado',
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
            'Processamento local. Sem envio de conteúdo. Fotos semelhantes, compressão e lixeira ficam para versões futuras.',
          ),
        ],
      ),
    );
  }
}
