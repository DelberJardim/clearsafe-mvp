# ClearSafe — MVP Flutter 0.1

Scanner local somente leitura para Android e iOS. Home: Analisar armazenamento,
Fotos, Vídeos, Duplicados, Arquivos grandes, Contatos e Configurações.

## Executar

Use Flutter stable 3.47.7 ou compatível, Android SDK e JDK 17+ (Android 7/API 24+). Para iOS,
use macOS/Xcode, configure assinatura e dispositivo no Runner (iOS 15+).

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

Testes adicionais do núcleo:

```sh
cd packages/safe_scanner
dart pub get
dart test
```

Demonstração com dados simulados inicia ativada; desative para análise nativa.
Documentos são escolhidos no seletor do sistema. Não há exclusão, alteração de
contatos, compressão ou escolha automática de cópia. Relatórios são limitados
ao conteúdo acessível, e não representam o armazenamento inteiro do aparelho.

Veja [documentação técnica](docs/MVP.md), [segurança](docs/SAFETY.md) e
[validação realizada](docs/VALIDATION.md). As ações futuras estão reservadas
fora de lib/ e sem código executável. Distribuição depende da matriz de testes
em aparelhos descrita na documentação.
