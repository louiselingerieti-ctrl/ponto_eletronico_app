# APP_COLABORADOR — app pessoal de presença (Flutter)

App pessoal do funcionário para o Sistema de Controle de Ponto. O canal
principal é a **detecção automática de entrada, saída e/ou permanência em
áreas autorizadas** (geofence nativo). A marcação manual é contingência, com
política ainda **não definida**.

> **Estado: prova de conceito, fase 1.** Ainda não existe app Flutter, tela,
> integração nativa nem conexão com o backend real. **Nenhuma marcação
> oficial é gerada.**

## O que existe

| Pasta | Conteúdo |
|---|---|
| [core/](core/) | Pacote Dart puro `presenca_core`: domínio dos eventos (contrato `presenca-v1`, rascunho), fila local SQLite transacional e cifrável, motor de envio com retry/backoff/idempotência e **servidor simulado** |
| [docs/diagnostico-e-plano.md](docs/diagnostico-e-plano.md) | Diagnóstico, arquitetura, decisões pendentes e próximos incrementos |
| [docs/matriz-testes-fisicos.md](docs/matriz-testes-fisicos.md) | Matriz de testes em aparelho (nada testado ainda) |

## App do colaborador Casa do Futuro — demonstração visual (Etapa 1)

[mobile/](mobile/) replica em Flutter, sem WebView, a interface aprovada no
relatório v2.0 (12/11/2026). Menu: Início · Histórico · **+ Registrar** ·
Solicitações · Perfil. Áreas abre pelo Início (e pelo Perfil). O + Registrar
segue a ordem obrigatória: validar a localização → tirar a foto → escolher
Entrada/Saída → confirmar o ponto.

- Usa **dados fictícios** (Ana Souza, Loja Centro, pedidos de exemplo).
- Fila e envio usam o núcleo real sobre memória **sem cifra** e servidor
  **simulado**.
- Não autentica, não pede localização, não fala com o backend e **não gera
  ponto oficial**.

```powershell
cd C:\Users\Micro\Desktop\PROJETO_PONTO\APP_COLABORADOR\mobile
flutter test                     # inclui as capturas em build\screenshots\
flutter run -d chrome            # ou instale o APK de debug só no emulador
```

`build\screenshots\comparacao.html` mostra cada captura do álbum ao lado da
versão Flutter.

## Laboratório web (SIMULADO)

[app/](app/) é um laboratório Flutter **só para web**. Ele usa o núcleo
(`presenca_core`) com adaptadores **simulados** (`presenca_lab`):

- memória do navegador, **sem cifra**; recarregar a página apaga tudo;
- servidor simulado (não é o backend);
- plataforma de geofence simulada.

Ele **não gera ponto oficial**, não pede localização, não registra geofence e
não fala com o backend. Também **não valida** SQLite cifrado, Keystore ou
execução em segundo plano.

```powershell
cd C:\Users\Micro\Desktop\PROJETO_PONTO\APP_COLABORADOR\app
flutter run -d chrome --no-web-resources-cdn
```

Com o comando rodando, `r` recarrega o código e `q` encerra.
`--no-web-resources-cdn` serve o motor do Flutter localmente, em vez de
buscá-lo no CDN do Google.

## Rodar os testes

```powershell
cd core
C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe pub get --offline
C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe test
C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe test -p chrome test/web   # núcleo dentro do Chrome

cd ..\app
flutter analyze
flutter test
```

## Limites que valem para todo o projeto

- O geofence do sistema operacional não garante entrega imediata, precisão de
  segundos nem funcionamento contínuo. Eventos podem atrasar, duplicar, chegar
  fora de ordem ou faltar.
- A ausência de evento não comprova a ausência da pessoa. GPS e o indicador de
  localização simulada não comprovam, sozinhos, presença ou trabalho.
- Entrar ou sair de uma área é **evidência de presença**, não marcação de
  jornada. Converter presença em jornada exige uma política versionada no
  backend (D-JOR-1), que ainda não existe.
- Sem rastreamento contínuo, sem selfie e sem biometria herdada do tablet.
