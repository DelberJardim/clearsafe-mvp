# Validação — versão 0.2 em 09/10/2026

## Resultados da 0.2

- 19 testes Flutter e 12 testes do núcleo Dart aprovados; análise estática sem problemas.
- 5 testes nativos da política de seleção aprovados.
- APK otimizado e APK debug compilados. O APK distribuído tem 82.035.743 bytes.
- Assinatura do APK conferida e idêntica à da versão 0.1; permite atualizar sem
  desinstalar. É uma assinatura de teste, não uma chave de produção.
- Manifesto final conferido: sem INTERNET, permissões de escrita, acesso amplo ao
  armazenamento ou permissão para alterar mídia sem confirmação. ACCESS_NETWORK_STATE
  permite à biblioteca local consultar conectividade, sem dar acesso à internet.
- Verificação de segurança aprovada: scanner separado das ações; nenhuma chamada
  nativa de exclusão definitiva, gravação ou atualização de mídia no código do app.
- Build iOS sem assinatura aprovado no macOS do pipeline; iOS permanece somente leitura.

Os testes instrumentados usam somente imagens e um pequeno vídeo MP4 artificiais,
criados pelo usuário shell do emulador. Eles verificam conteúdo estrangeiro ao app:
cópia preservada, lixeira e restauração byte a byte, histórico após recriação da
tela, cancelamento sem alteração, bloqueio de conteúdo diferente/revisão obsoleta,
miniatura real e OCR local de documento.

[Execução aprovada da matriz Android 13/15/16](https://github.com/DelberJardim/clearsafe-mvp/actions/runs/37995578353):
os 5 testes instrumentados passaram em cada uma das 3 versões, totalizando 15
execuções aprovadas. A preparação espera até 20 segundos pela visibilidade da
mídia artificial em provedores recém-iniciados, sem repetir inserção nem ampliar
permissões. O mesmo pipeline aprovou testes Dart/Flutter, política nativa,
verificação estática, build Android e build iOS sem assinatura.

Não há Android físico conectado. A virtualização local está desativada; os testes
instrumentados executam no CI com KVM. S23 Ultra, Note 10 Lite e S25 FE ainda
precisam de verificação no aparelho: galeria Samsung, permissões limitadas,
expiração real da lixeira, pouco espaço e biblioteca grande não estão certificados.
O Android pode continuar contabilizando arquivos na lixeira até a expiração;
o app não promete liberação imediata nem recuperação após esse prazo.

## Histórico — versão 0.1 (não descreve as capacidades da 0.2)

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
