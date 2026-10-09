# Critérios de segurança e aceite

## Invariantes do MVP

- Zero exclusão, alteração, merge ou compressão dos dados do usuário.
- Nenhuma permissão Android de escrita ou acesso total ao sistema de arquivos.
- Somente leitura de fontes autorizadas; sem suposição de acesso completo.
- Duplicata confirmada exige tamanho, SHA-256, bytes e versão estável.
- Provedor sem versão confiável não recebe confirmação de duplicata.
- Item alterado, ilegível, incompleto ou revogado produz aviso, não confirmação.
- Cancelamento elimina grupos confirmados do relatório cancelado.
- Nenhuma escolha automática de arquivo a conservar.
- Correspondência de contatos é sugestão; nomes iguais não implicam duplicidade.
- Logs não incluem conteúdo ou dados pessoais.
- Código futuro de ações fica fora do grafo de compilação do MVP.

## Validação automatizada

Núcleo: nomes e tamanhos iguais com conteúdo diferente; colisão forçada de hash;
blocos diferentes; falha/revogação; mudança de versão; cancelamento; filtros;
3.000 cópias simuladas; sugestões conservadoras de contatos.

Aplicativo: Home, indicação de demonstração/somente leitura; MethodChannel com
permissão completa, limitada, negada, restrita e indisponível; leitura em blocos,
fechamento de handles inclusive em erro; fonte nativa não expõe ações destrutivas.

## Matriz de aparelhos — exigência anterior à distribuição

| Plataforma | Cenários obrigatórios |
|---|---|
| Android 7–12 | negar/permitir READ_EXTERNAL_STORAGE; revogar durante scanner |
| Android 13 | permitir só fotos, só vídeos, ambos e nenhum |
| Android 14+ | seleção parcial; alterar seleção; revogar no segundo plano |
| Android | documento escolhido/cancelado; provedor remoto/offline; contatos negados |
| iOS 15–17 | galeria completa/limitada/negada/restrita; mudar seleção |
| iOS 18+ | contatos limitados e completos; confirmar alcance da lista |
| iOS | original local/iCloud; Live Photo; recurso acima de 512 MiB; pouco espaço |
| Ambas | biblioteca vazia; item alterado/removido externamente; fechar app; cancelamento |

Confirmar separadamente que hashes de arquivos e base de contatos permanecem
iguais antes/depois do teste; só o sandbox do app pode ganhar/remover cache próprio.
Testar desempenho e memória com bibliotecas reais grandes e baixa memória.
Snapshots byte a byte externos devem ser feitos sobre biblioteca de teste, nunca
apenas sobre dados pessoais insubstituíveis.

## Limites e riscos residuais

Não há garantia absoluta de ausência de falhas. O mecanismo de prevenção é reduzir
o MVP à leitura e eliminar as capacidades de alteração dos dados do usuário.
Mudanças feitas por outro aplicativo ou pela sincronização não são controladas.
Versões nativas não equivalem a locks ou snapshots; qualquer ação futura precisa
conferir novamente conteúdo e identidade no momento da operação.

O inventário iOS ainda não oferece cancelamento por item à UI; cancelar o scanner
é observado depois do inventário ou entre blocos de leitura. Cache temporário iOS
pode ficar após encerramento abrupto; fica no sandbox temporário, sem afetar originais.
Esta versão é uma base de desenvolvimento; distribuição depende da matriz acima,
builds nativos, revisão de permissões e política das lojas.
