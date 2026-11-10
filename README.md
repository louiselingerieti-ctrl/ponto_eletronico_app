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

## Rodar os testes

```powershell
cd core
C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe pub get --offline
C:\src\flutter\bin\cache\dart-sdk\bin\dart.exe test
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
