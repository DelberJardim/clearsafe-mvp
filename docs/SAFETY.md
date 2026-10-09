# Segurança e critérios de aceite — 0.2

## Invariantes

- Scanner puro separado das ações. iOS e contatos permanecem somente leitura.
- Única ação Android: MediaStore.createTrashRequest(true/false). Sem delete,
  createDeleteRequest, update, escrita de originais ou esvaziamento.
- Nada começa selecionado; keeper escolhido pelo usuário fica fora dos alvos.
- Duplicata: tamanho, SHA256, bytes e versão estáveis. Repetir validação nativa
  antes de solicitar lixeira, inclusive na cópia preservada.
- Seleção manual de semelhantes/vídeos valida metadados e lê conteúdo completo
  para registrar hash; não é tratada como prova de duplicidade.
- Até100 alvos. ID repetido, provedor estranho, keeper nos alvos, falha de leitura
  ou revogação bloqueiam todo o lote. SAF somente leitura.
- Revisão, consentimento explícito e confirmação Android; validação cancelável.

## Registro e recuperação

SharedPreferences privado: URI, nome, tamanho, SHA256, momento/intenção.
commit() síncrono precisa concluir ANTES de abrir diálogo Android. Registro é
intenção, não prova do resultado. Histórico consulta IS_TRASHED/DATE_EXPIRES:
ativo, na lixeira, invisível/ausente ou desconhecido, inclusive após reinício.

Restaurar exige registro, estado na lixeira, leitura acessível e hash igual,
bloqueando ID reutilizado com conteúdo diferente. Sistema solicita confirmação.
Se o Android negar acesso aos bytes na lixeira, bloqueia e orienta recuperar
pela galeria. Fabricantes podem apresentar lixeira de forma diferente.

Desinstalar/limpar dados remove registro. Android controla prazo e pode apagar
após expiração. Não há retenção indefinida, backup dos bytes ou garantia de
liberar espaço imediatamente.

## Semelhança e documentos

Modelo OCR Latin embutido e local. Falha OCR/miniatura impede sugestão.
Texto detectado, nomes/pastas de documentos/capturas e padrões quase uniformes
excluem grupos. Letras pequenas, manuscritas, assinaturas e desfoque podem
passar despercebidos: revisão visual continua obrigatória.

dHash64 distância<=6, RGB L1<=0,12, proporção relativa<=5%.
Todos os pares devem satisfazer limites; sem encadear A~B~C se A e C diferem.
Até10 por grupo. Não entende significado, pessoas, importância ou qualidade.
Nomes WA não classificam importância. Sugestão nunca autoriza remoção automática.

## Privacidade e riscos residuais

Manifesto remove INTERNET herdada das dependências; modelo não precisa de download.
ACCESS_NETWORK_STATE permanece para o agendador da biblioteca, sem acesso à Internet.
Backup Android do app desativado. Logs gerais
não contêm bytes/OCR/contatos; registro privado contém metadados de recuperação.
Sem all-files, MANAGE_MEDIA ou permissões de escrita.

Metadados não são locks. Outro app/sincronização pode remover/alterar keeper
DURANTE o diálogo após validação. Não há transação atômica protegendo todas as
cópias. Não se promete risco zero; backup de material insubstituível é necessário.
iOS mantém scratch<=512MiB, possível cache após interrupção e cancelamento
atrasado do inventário. Recursos compostos/iCloud indisponível são omitidos.

## Matriz de aceite antes de produção

| Ambiente | Cenários |
|---|---|
| Android7–9 | somente análise, sem lixeira |
| Android10 | visual/semelhança, sem lixeira |
| Android11–12 | permissões, cancelamento, restauração, expiração |
| Android13 | só fotos/só vídeos/ambos/nenhum; revogação |
| Android14–16 | acesso parcial, mídia estrangeira, reinício no diálogo |
| Fabricantes/SD | lixeira e identidade em volumes removíveis |
| Documentos | número/assinatura diferente, OCR falho, padrão uniforme |
| Vídeos | arquivos WA grandes/longos, duração, visualizador ausente |
| Recuperação | hashes externos, registro durável, ID reutilizado |
| iOS15+ | permissões, contatos limitados, iCloud/LivePhoto/scratch |

Usar biblioteca artificial, hashes antes/depois e testar baixo espaço/memória.
Testes em emulador não substituem matriz de aparelhos. Guardas estáticas são
barreiras de regressão, não prova formal.

Fontes: [MediaStore](https://developer.android.com/reference/android/provider/MediaStore),
[prazo](https://developer.android.com/reference/android/provider/MediaStore.MediaColumns#DATE_EXPIRES),
[OCR local e qualidade](https://developers.google.com/ml-kit/vision/text-recognition/v2/android).
