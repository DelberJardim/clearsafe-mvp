# Validação — 08/10/2026

Ambiente: Windows; Flutter stable 3.47.7, Dart 3.13.5. SDK Flutter instalado em
área de trabalho para executar a verificação; não integra o ZIP do projeto.

## Resultados verificados

- 12 testes do núcleo Dart aprovados, incluindo 3.000 cópias simuladas,
  colisão de hash, leitura truncada e cancelamento na validação final.
- 11 testes Flutter aprovados: scanner da demonstração com arquivos de múltiplos
  blocos, Home e relatório de duplicatas; contratos de permissões, estado desconhecido
  e fechamento de leitura em sucesso/erro.
- Análise estática Flutter e Dart sem problemas na última execução.
- `python tool/check_safety.py` aprovado: permissões Android de leitura,
  ausência de chamadas de alteração nas fontes nativas, rede iCloud desativada
  e separação das ações futuras.
- Informações de uso Android/iOS e matriz de aceite documentadas.

## Compilação nativa

**Android: build APK debug concluído com sucesso.** O adaptador Kotlin foi
compilado e convertido para DEX. O manifesto final foi conferido: sem permissões
de escrita ou MANAGE_EXTERNAL_STORAGE. A variante debug inclui INTERNET para
infraestrutura Flutter de desenvolvimento; o aplicativo não implementa envio
de conteúdo nem serviço remoto.

O ambiente exigiu instalação do SDK Flutter e componentes Android. O problema
inicial de TLS foi resolvido com uma cópia isolada do truststore contendo o
certificado do antivírus já confiado pelo Windows, sem desativar TLS ou modificar
a confiança global. A primeira preparação longa foi interrompida para reiniciar
com limites menores de memória e concorrência; a nova compilação terminou em
914,8 segundos. O projeto limita Gradle a 2 GiB de heap e dois workers.

APK fornecido para desenvolvimento/teste, assinado com a chave debug do ambiente.
Assinatura de produção precisa ser configurada explicitamente. O ZIP de fontes
não inclui SDKs, caches, keystore, APK ou configurações locais do computador.

iOS: não compilado neste ambiente Windows. A integração Swift exige macOS/Xcode.
O projeto inclui pipeline para build iOS sem assinatura e build Android, que só
executará se o projeto for colocado em repositório com GitHub Actions.

## O que ainda precisa de validação

Os testes de permissões são simulações do contrato Dart/MethodChannel. Não provam
comportamento de diálogos reais ou de provedores de conteúdo no aparelho.
Não havia dispositivo ou emulador Android conectado nesta sessão. A matriz em
SAFETY.md e a compilação iOS são pendências antes da distribuição.

A verificação estática é uma barreira de regressão, não uma prova formal de
segurança. As operações de cache próprio no iOS permanecem permitidas; não há
alteração dos recursos originais na implementação.
