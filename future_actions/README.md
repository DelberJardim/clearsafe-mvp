# Área reservada — fora de lib/ e do grafo de dependências

Não contém código executável. A lixeira do Android da versão 0.2 está no módulo
separado lib/actions, com confirmação do sistema e registro persistente.
Exclusão definitiva, compressão e alterações de contatos não existem no app.

Futuro módulo independente: plano imutável de operação, confirmação explícita,
revalidação de identidade/conteúdo, backup verificado, transação com journal,
quarentena ou lixeira da plataforma, recibo e desfazer testado. Compressão deve
gerar novo arquivo, validar decodificação e integridade e manter o original.
Contatos exigem backup completo e restauração validada antes de qualquer merge.
Fotos semelhantes constituem sugestões separadas; nunca duplicatas exatas.
