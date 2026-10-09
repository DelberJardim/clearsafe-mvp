# ClearSafe 0.1 — especificação técnica

## Objetivo e alcance

Aplicativo Flutter para Android e iOS, com interface em português, análise local
e prioridade para preservação dos dados. Home: Analisar armazenamento, Fotos,
Vídeos, Duplicados, Arquivos grandes, Contatos e Configurações. Nome provisório
próprio; não reutiliza marca, interface ou código do CleanX.

Alvos mínimos desta base: Android 7/API 24 e iOS 15. Assinatura de produção deve
ser configurada explicitamente; a variante release não usa chave debug por padrão.

A Home inicia em demonstração explícita. Desativar demonstração habilita a fonte
nativa, solicitando permissão apenas ao executar a função correspondente. Galeria
e contatos têm autorizações independentes. Documentos são escolhidos pelo seletor
do sistema. O MVP não consegue varrer o armazenamento inteiro do aparelho.
O total exibido representa os bytes dos itens inventariados, nunca espaço livre
do aparelho ou espaço já recuperado.

## Organização

- `packages/safe_scanner`: núcleo Dart independente do Flutter; interface
  ReadSource com apenas inventory, stat e read; critérios, relatórios e contatos.
- `lib/data`: implementação nativa por MethodChannel e biblioteca simulada.
- `lib/main.dart` e `lib/presentation/home.dart`: interface Material 3, fluxo, progresso, cancelamento, detalhes.
- Android MainActivity: MediaStore, Storage Access Framework e ContactsContract;
  leitura de conteúdo em blocos de 64 KiB em executor fora da thread da interface.
- iOS AppDelegate: PhotoKit, seletor de documentos e Contacts;
  leitura em fila própria, sem chamadas de alteração da biblioteca.
- `future_actions`: documento de desenho futuro, fora do código compilado.

O canal permite permission, requestPermission, inventory, stat, open, read,
close, contacts, diagnostics e selectDocuments. Não aceita caminho arbitrário para leitura:
identificadores precisam vir do inventário ou do seletor. Operações desconhecidas
falham. `close` fecha recursos de leitura; no iOS remove exclusivamente cópia
temporária própria, identificada por UUID e criada no sandbox do aplicativo.

## Scanner

1. Inventaria somente itens acessíveis; elimina IDs repetidos e metadados inválidos.
2. Aplica tipos e pastas ignoradas; ignorar pasta usa limite de segmento.
3. Agrupa tamanhos iguais; itens sem pares não precisam de hash.
4. Calcula SHA-256 por streaming, conferindo número de bytes e versão antes/depois.
5. Agrupa hashes iguais e compara byte a byte em janelas fixas, independentes da
   fragmentação de leitura do provedor. Colisão de hash não confirma duplicata.
6. Reconfere a versão dos membros antes de publicar o grupo.
7. Qualquer falha torna a confirmação inconclusiva. Avisos e logs acompanham o relatório.

Não escolhe automaticamente a cópia a conservar. Bytes redundantes são uma
estimativa matemática, sem ação de limpeza. Identidade e versão são garantias
observáveis do provedor, não snapshots atômicos: alterações externas podem ocorrer
depois do relatório. Futuras ações exigirão nova validação completa.

O filtro de idade usa data de modificação fornecida pela plataforma; datas ausentes
não passam quando há idade mínima. Arquivos grandes são ordenados por tamanho.
Pastas não fornecidas pelo iOS não podem ser excluídas por um caminho presumido.
Filtros e modo simples/avançado são mantidos apenas durante a sessão atual.

## Mídia e documentos

Android: galeria de imagens/vídeos autorizados no MediaStore; arquivos de outros
tipos via seleção explícita. Android 13+ pode autorizar somente imagens ou vídeos;
Android 14+ pode autorizar somente itens selecionados. Esses casos são parciais.
Não pede MANAGE_EXTERNAL_STORAGE, acesso de escrita ou localização de mídia.

iOS: acesso completo ou limitado da PhotoKit; recurso original único, local.
Não baixa iCloud automaticamente. Assets compostos, como Live Photos e RAW+JPEG,
são omitidos para evitar tratar um componente como duplicata do asset inteiro.
O tamanho é medido por leitura local do recurso; isso pode ser demorado. Cache
de tamanhos é indexado por ID e versão. Comparações exportam cópias locais temporárias
do recurso original, com teto de 512 MiB por recurso e verificação de espaço livre.
Recursos maiores ainda podem aparecer no inventário de grandes arquivos, mas sua
comparação exata falha com aviso. Duas cópias temporárias podem coexistir.

Documentos selecionados: o provedor pode não oferecer versão confiável ou data.
Neste MVP aparecem no inventário e na análise de tamanho; **não recebem confirmação
de duplicata exata** quando marcados como unversioned. Acesso vale para a sessão.

## Contatos

Analisa contatos acessíveis. Sugere grupos com telefone igual após remover apenas
espaços, parênteses, pontos e hífens; preserva DDI, sinal + e ramais inválidos.
E-mails são comparados literalmente após trim, preservando caixa. Nome igual
nunca basta. Mesmo telefone ou e-mail pode pertencer a pessoas distintas.
Não mescla, exporta backup nem altera contatos nesta versão.

## Logs e privacidade

O Runner inclui PrivacyInfo.xcprivacy: E174.1 para conferir espaço de cópia
temporária; C617.1 para arquivos próprios; 3B52.1 para metadados de documentos
selecionados. Sem rastreamento ou coleta fora do dispositivo. As razões foram
conferidas na documentação oficial da Apple:
https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons

Logs locais em memória: início/fim, contagens, falhas e estados de acesso. Não
contêm nomes, telefones, e-mails, caminhos ou bytes do conteúdo. Detalhes sensíveis
aparecem apenas quando solicitados na interface. Não existe telemetria, conta ou
serviço remoto. Logs e relatórios desaparecem ao encerrar o processo.

## Evolução prevista

1. Persistência privada dos critérios e histórico com política de retenção.
2. Permissões e ciclo de vida testados em aparelhos, com relatórios parciais mais granulares.
3. Seletores e leitura de documentos com versão/revalidação robustas.
4. Progresso/cancelamento nativo do inventário iOS e recursos compostos explícitos.
5. Módulo independente de planos de ação; lixeira/quarentena, journal, recibos e desfazer.
6. Compressão gera cópia e valida decodificação; original conservado até aprovação.
7. Fotos semelhantes em módulo separado, sem equivalência com duplicatas exatas.

## Fontes técnicas consultadas

- https://developer.android.com/about/versions/14/changes/partial-photo-video-access
- https://developer.apple.com/documentation/contacts/accessing-the-contact-store
- https://developer.apple.com/documentation/photos/phassetresourcerequestoptions/isnetworkaccessallowed

Não depende de plugins de galeria/contatos com APIs de exclusão. O bridge próprio
reduz as capacidades expostas e precisa de validação nativa, especialmente no iOS.
