# Retomada — 0.2.0+2

Usuário autorizou seleção/lixeira/restauração/semelhantes/vídeos e publicar novo
APK no repositório público. Substitui restrição somente leitura da0.1;
exclusão definitiva permanece fora do app.

Implementado: ações/scanner separados, MediaStore API30+, journal antes do
diálogo, revalidação/keeper/revisão, visual/OCR Latin API29+, grupos conservadores,
fonte real padrão. Testes de seleção/UI/documentos/transitividade e5 testes
de política; integração Android 13/15/16 com mídia estrangeira, vídeo, OCR,
cancelamento e recriação.
Resultado fechado: 19 testes Flutter, 12 do núcleo Dart, 5 de política nativa e
5 instrumentados em cada Android 13/15/16 aprovados. Build iOS sem assinatura
aprovado. Evidência: https://github.com/DelberJardim/clearsafe-mvp/actions/runs/37995578353.
APK otimizado de teste: 82.035.743 bytes, assinatura idêntica à versão 0.1.
Publicação: https://github.com/DelberJardim/clearsafe-mvp/releases/tag/v0.2.0.
Fontes e checksums acompanham a versão. Detalhes/limites em VALIDATION.md.

Windows sem virtualização habilitada e sem Android físico. Integração via CI/KVM.
Flutter3.47.7/Dart3.13.5. Build teste otimizado exige CLEARSAFE_PREVIEW_SIGNING=1.
Pendências produção: matriz fabricantes/expiração/baixo espaço/desempenho e
documentos reais. iOS somente análise. Compressão/quarentena própria/contatos
alteráveis não implementados.
