# Arquitetura técnica — 0.2

## Camadas

packages/safe_scanner: modelos, ReadSource, scanner puro, cancelamento/filtros/
contatos conservadores. lib/data: fonte nativa/sintética e canal de prévias.
lib/analysis/similarity.dart: assinaturas e grupos completos.
lib/actions/trash_service.dart: capacidade explícita fora do scanner.
lib/presentation: Home, revisão, comparação e recuperação.
Android MediaActions: validação independente, streaming/journal/pedido ao sistema;
TrashPolicy: barreiras puras testáveis; MediaVisuals: miniaturas/duração/OCR/dHash.
iOS AppDelegate: PhotoKit/contatos/documentos somente leitura.
future_actions: compressão/quarentena própria ainda sem implementação.

## Scanner

Inventário autorizado → filtros → candidatos por tamanho → SHA256 por streaming
→ bytes em janelas64KiB → validação de versões. Provedor sem versão confiável
não recebe confirmação exata. Colisão forçada/truncamento/revogação/mudança
testados. Cancelamento descarta grupos. Arquivos grandes por tipo/tamanho/idade.

## Limpeza e recuperação

Lista/grupo → prévias → keeper explícito quando há comparação → seleção
individual → resumo/consentimento → validação nativa → commit privado →
confirmação Android → consulta de histórico → nova análise.
Páginas40 itens, até100 alvos. Keeper fora dos alvos. SAF bloqueado na UI/adaptador.
Solicitação aprovada invalida relatório. Journal é intenção, estado consultado
por IS_TRASHED/DATE_EXPIRES. Restaurar compara digest registrado e pede confirmação.
Registro não impede expiração nem é backup de bytes.

## Semelhança

Lotes250, cancelamento entre fotos, assinaturas acumuladas na tela; agrupamento
em isolate. Miniatura1280, OCR Latin embutido, dHash/RGB/proporção. Texto/capturas/
padrões uniformes excluídos. Grupos<=10 com todos os pares semelhantes.
Sugestões não provam identidade, significado ou qualidade.

## Plataformas/estado

Android7+ scanner; Android10+ visual; Android11+ lixeira. Android13–14+
leitura separada/parcial. iOS15+ scanner; novos canais Android indisponíveis.
Relatórios/configurações/logs/assinaturas em memória; recuperação persistente.
Fonte real padrão, demo opcional. Relatório não abrange todo o armazenamento.

Evolução: compressão em novo arquivo verificado+reversão; quarentena própria
com espaço/cópia íntegra/journal; similaridade semântica com fixtures;
ações iOS após desenho de recuperação e testes macOS/aparelho.
