# ClearSafe 0.2 — análise, seleção e lixeira

Aplicativo Flutter para Android e iOS. Android11+ oferece lixeira/restauração;
Android10+ oferece miniaturas, duração, reprodução no visualizador local e fotos
semelhantes. Android7–9 e iOS mantêm análise somente leitura. Versão de teste.

## Usar no Android

1. Instale a [versão publicada](https://github.com/DelberJardim/clearsafe-mvp/releases).
2. Toque em Analisar armazenamento e autorize as mídias desejadas.
3. Em Duplicados, escolha qual manter e marque individualmente as outras cópias.
4. Toque em Revisar, confira a lista e confirme a solicitação no Android.
5. Use o botão de recuperação no topo da Home para consultar estado/prazo e restaurar.
6. Faça nova análise após alterações para atualizar o relatório.

Fotos → Encontrar fotos semelhantes compara lotes de250 imagens, com revisão
manual. Texto detectado, capturas e sinais de documentos excluem sugestões.
OCR pode falhar com letras pequenas/manuscritas/desfocadas. Vídeos e Arquivos
grandes mostram prévias; abrir permite consultar duração e reproduzir.
Nomes do WhatsApp não determinam importância nem duplicidade.

Nada começa selecionado. Sem exclusão definitiva, esvaziamento, compressão ou
mesclagem de contatos. A lixeira tem prazo e o Android pode apagar após expiração;
ela pode continuar ocupando espaço até lá. Documentos externos somente leitura.
Biblioteca real é padrão; demonstração opcional nunca chama ações nativas.

## Desenvolvimento

Flutter3.47.7/Dart3.13.5; Android SDK/JDK17+; iOS15+ requer macOS/Xcode.

```sh
flutter pub get
cd packages/safe_scanner
dart pub get
dart test
cd ../..
flutter analyze
flutter test
python tool/check_safety.py
flutter build apk --debug
cd android
./gradlew :app:testDebugUnitTest
```

CI inclui Android 13, 15 e 16 emulados com mídia artificial estrangeira,
confirmação/cancelamento, cópia preservada, vídeo, OCR de documento e recuperação
após recriação da tela. Resultados efetivamente aprovados em VALIDATION.md.
Build otimizado de teste exige CLEARSAFE_PREVIEW_SIGNING=1 explícito antes de
flutter build apk --release; usa a mesma chave de teste da0.1.
Assinatura de produção precisa de configuração própria. SDKs, keystores e
configurações locais não integram o repositório.

[Arquitetura](docs/MVP.md) · [Segurança](docs/SAFETY.md) ·
[Validação](docs/VALIDATION.md) · [Retomada](docs/RESUME.md)
