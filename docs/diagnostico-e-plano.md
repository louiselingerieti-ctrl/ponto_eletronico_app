# Diagnóstico e plano: app pessoal de presença

**Data:** 10/11/2026. **Responsável pela frente:** APP_COLABORADOR.
Classificação usada: **CONFIRMADO** (visto no código ou na máquina),
**INFERIDO** e **NÃO CONFIRMADO**.

## 1. Pastas e fonte oficial

| Pasta | Situação | Papel |
|---|---|---|
| `Desktop\PROJETO_PONTO\APP_COLABORADOR` | CONFIRMADO: estava vazia, sem Git. Agora tem `git init` (sem commit), `core/` e `docs/`. | **Fonte oficial do app pessoal** (pasta autorizada) |
| `Downloads\ponto-eletronico-main\ponto-eletronico-main` | CONFIRMADO: é o PWA legado `ponto-corporativo-pwa` (React, Vite e Supabase), do repositório `louiselingerieti-ctrl/ponto-eletronico`. Tem admin, tablet coletivo e portal do funcionário com foto e GPS a cada batida. | **Não é** o app pessoal. Não foi alterado. |
| `Downloads\ponto-eletronico-main\Ponto_eletronico_backend` | Clone do repositório do backend, só com `.git` | Duplicata; não usar como fonte |
| `Desktop\PROJETO_PONTO\BACKEND` | CONFIRMADO: branch `fase-0/contratos-presenca`, árvore limpa | Somente leitura |
| `Desktop\PROJETO_PONTO\APP_TABLET` | CONFIRMADO: tem alterações não commitadas de outro agente | Somente leitura; não foi tocado |

Não encontrei `AGENTS.md` nem `CLAUDE.md` em nenhuma das pastas. Não li
nenhum `.env`.

## 2. Ambiente (revalidado em 10/11/2026)

| Item | Estado |
|---|---|
| Flutter | CONFIRMADO: 3.47.9 stable, Dart 3.13.7. `flutter --version` respondeu em cerca de 7 s. |
| `flutter doctor` | NÃO EXECUTADO nesta sessão |
| Android SDK | CONFIRMADO: `ANDROID_HOME` definido, platforms 35 e 36, build-tools 36.0.0, NDK, emulador e cmdline-tools. `adb` 37.0.1 está no PATH. |
| JDK | `JAVA_HOME` aponta para o JDK 17.0.21. O `java` do PATH é o 26.0.2. INFERIDO: o Gradle usa o `JAVA_HOME`; verificar no primeiro build. |
| Aparelho | CONFIRMADO: moto g86 5G, Android 16 (API 36), patch de 2026-09-01, conectado por adb sem fio. Não confirmei se é pessoal ou corporativo, nem se está autorizado para o piloto. |
| Ambiente iOS | Indisponível: esta máquina é Windows e não há Mac. Não dá para compilar nem testar iOS aqui. |
| Build Android | NÃO TESTADO |

## 3. Contratos: o que existe e o que é proposta

| Item | Estado |
|---|---|
| `BACKEND/docs/contratos/presenca-v1.openapi.yaml` + `presenca-v1.md` | CONFIRMADO: **rascunho** `1.0.0-draft.1`, atualizado em 10/11. Não é servido pela API e nenhuma rota está implementada. **Existe só na branch `fase-0/contratos-presenca` (commit `3b0b289`), sem merge.** Durante esta sessão, outro agente trocou o checkout do BACKEND para `ops/reforco-fundacao`, que tem edições sem commit e uma migration nova; nessa branch o arquivo não existe. A referência do app é o `3b0b289`. |
| Rotas `/v1/me/*` de presença em `BACKEND/src` | CONFIRMADO: **não existem** (a busca não encontrou nada) |
| Autenticação móvel | CONFIRMADO: o Better Auth só tem sessão por **cookie**, com checagem de Origin. O plugin `bearer` **não** está configurado. O rascunho propõe Bearer, e isso continua pendente (D-AUTH-1). |
| `APP_TABLET/docs/contrato-terminal-v1.md` | Proposta específica do coletor. **Não foi transportado** para o app pessoal. |

O `core/` implementa só a **forma de fio** do rascunho (`schemaVersion: 1`)
para `area_transition` e `detection_status`. `manual_punch` ficou fora porque
a política da contingência não foi definida. O núcleo **não chama nenhuma rota
real**: o adaptador `SimulatedPresenceServer` reproduz em memória as regras de
recebimento do rascunho e está identificado como simulado no código.

Pontos do rascunho que levei para alinhar com o backend (**não** são mudanças
feitas no backend):

1. **Lease no servidor e ACK por `eventId`.** O app casa os resultados por
   `eventId` e ignora os que não reconhece. Um item sem resultado volta para
   a fila. Convém o contrato dizer explicitamente que um resultado ausente
   equivale a "reenviar".
2. **`rejected` sem `eventId` utilizável.** O caso do JSON ilegível não está
   descrito no contrato.
3. **Qualidade do relógio.** O rascunho cita "o mesmo modelo do APP_TABLET",
   mas os limiares não estão no contrato. Por enquanto o app envia `uncertain`.
4. **Ordem da sequência quando um lote falha.** O app sempre envia em ordem
   de `installationSequence`, mas um ACK parcial pode fazer a sequência chegar
   fora de ordem ao servidor. É preciso confirmar que o `sequence_gap` é
   avaliado no fim e não no instante da chegada.

## 4. Arquitetura proposta para o Flutter

Ela segue o padrão por feature com camadas que já existe no APP_TABLET.
Aproveitei só a **escolha técnica** (SDK fixado, `sqlite3` com
SQLite3MultipleCiphers). Não copiei autenticação, interface, biometria nem
dependências de coletor.

```
APP_COLABORADOR/
├── core/                      ← Dart puro (existe): roda em `dart test` no Windows
│   └── lib/src/
│       ├── domain/            eventos, estados de entrega
│       ├── application/       portas, motor de envio, backoff
│       └── adapters/          fila SQLite, servidor SIMULADO
└── app/                       ← Flutter (ainda não criado; depende de D-PLAT)
    ├── lib/
    │   ├── features/session/        login e sessão (depende de D-AUTH-1)
    │   ├── features/presence_config/ vínculos e configuração (revisão, vigência, revogação)
    │   ├── features/geofence/       adaptador nativo → RecordDetection
    │   ├── features/delivery/       agendamento do SyncEngine
    │   └── features/status/         telas (depois do protótipo aprovado)
    └── android/ (ios/)              código nativo do geofence, se necessário
```

Por que `core/` separado: o domínio e a fila ficam testáveis sem Flutter e sem
aparelho, e a regra de entrega não depende de plugin. É um pacote só, usado
pelo `app/` por `path:`. Não há monorepo nem ferramenta extra.

### Garantias já implementadas e testadas (desktop)

| Requisito | Como |
|---|---|
| Persistir antes de dizer "salvo no aparelho" | `append` faz `BEGIN IMMEDIATE … COMMIT` e só retorna depois do commit, com WAL e `synchronous=FULL` |
| ID estável, sequência e versão | `eventId` UUIDv4, `installationSequence` e `schemaVersion` são atribuídos na mesma transação. O payload é congelado na gravação. |
| Idempotência e conflito | O reenvio manda os mesmos bytes. `duplicate` traz o recibo original; `conflict` e `rejected` nunca são reenviados. |
| Retry | Backoff exponencial com jitter, teto de 30 min (valor provisório), `Retry-After` como piso e redução do lote no 413 |
| Recebido só depois do ACK | O estado `received` só nasce de `accepted` ou `duplicate`. Timeout e 503 voltam para `savedLocally`. |
| Estados distintos | `savedLocally → sending → received / conflict / rejected`. "Avaliado" virá do `GET /v1/me/presence-events` e não é estado de entrega. |
| Três instantes | `observedAt` só quando o SO informa (`observedAtSource: none` quando não). `detectedAt` vem do app. `receivedAt` vem do servidor. Nenhum instante de cruzamento é inventado. |
| Reinício | Um lease vencido volta para a fila, e a sequência continua sem reutilização |
| Cifra | Com SQLite3MultipleCiphers, o arquivo não abre sem a chave nem com a chave errada, e o conteúdo não aparece em claro. **Só no desktop.** |

### Limitações conhecidas do núcleo (registradas, não corrigidas)

- **Sem token de lease.** Se dois isolates enviarem ao mesmo tempo depois de
  um lease vencer, o mesmo evento pode sair duas vezes. Isso não corrompe nada
  (o servidor responde `duplicate`), mas gasta rede. A correção é um
  `lease_token` por lote. Fica para o incremento do agendamento em segundo
  plano.
- O contador de falhas seguidas fica em memória e zera quando o app reinicia.
- A cifra é **opcional** no adaptador. No app ela deve ser obrigatória, com a
  chave gerada e guardada no Keystore ou Keychain via armazenamento seguro.
  Essa parte ainda não foi implementada.
- Eventos `received` nunca são apagados: a retenção local está pendente
  (D-PRIV).
- Qualidade do relógio: o avaliador não foi implementado.

## 5. Plataforma e execução em segundo plano: o que a documentação oficial diz

**Android:** documentação lida em 10/11/2026 em
`developer.android.com/develop/sensors-and-location/location/geofencing` e
`…/permissions/background`.

- O limite é de 100 geofences por app e por usuário do aparelho.
- A latência típica fica abaixo de 2 min. Com os limites de localização em
  segundo plano, a média é de 2 a 3 min, e chega a 6 min com o aparelho parado.
- O raio mínimo recomendado é de 100 a 150 m (o texto também diz "mínimo de
  100 m").
- `DWELL` existe, configurado com `setLoiteringDelay`. O valor padrão não é
  informado.
- É preciso **recadastrar** os geofences depois de reboot (`BOOT_COMPLETED`),
  reinstalação, limpeza dos dados do app ou do Play Services, e no alerta
  `GEOFENCE_NOT_AVAILABLE` (por exemplo, quando o provedor de localização é
  desligado).
- Para alvo API 29 ou superior é exigida `ACCESS_BACKGROUND_LOCATION`. A
  partir do Android 11, "Permitir o tempo todo" só é concedido **pela tela de
  Configurações**, depois de uma explicação dentro do app.
- A política do Google Play restringe a localização em segundo plano a apps
  que precisam dela para a função principal.
- **Não documentado** na página: a entrega com o processo morto e o efeito do
  "Forçar parada". Isso precisa ser testado (F-04 a F-06). INFERIDO, a
  confirmar no aparelho: depois de um "Forçar parada", o Android não entrega
  broadcasts até o usuário abrir o app de novo.
- O geofence depende do Google Play Services. Um aparelho sem ele não é
  suportado.

**iOS: NÃO CONFIRMADO.** As páginas da Apple vieram só com o título. Não
presumo limite de regiões, existência de dwell, relançamento depois de
encerrar o app ou a situação do `CLMonitor`. É preciso consultar a
documentação de novo, por outro meio, antes de qualquer decisão sobre iOS.

**Flutter:** `docs.flutter.dev/packages-and-plugins/background-processes`
descreve a execução de Dart em segundo plano por isolate com callback
dispatcher.

**Biblioteca de geofence:** ainda não escolhida. A recomendação a validar é
um **adaptador nativo próprio e fino**, que chame a Geofencing API do Play
Services e grave a transição em SQLite antes de qualquer coisa, sem depender
de o motor Dart subir. Plugins de terceiros (inclusive os pagos) ficam fora
sem autorização.

## 6. Decisões pendentes (recomendações não aprovadas)

| ID | Decisão | Recomendação (não aprovada) |
|---|---|---|
| D-PLAT | Android primeiro ou Android e iOS; aparelhos pessoais ou corporativos; distribuição do piloto | Android primeiro: só há ambiente para ele aqui. Piloto por distribuição interna (APK assinado ou teste interno da Play), sem publicação. |
| D-LOC-1/2 | Entrada e saída, permanência ou as duas; raio; dwell | Entrada e saída primeiro. Raio de 150 m ou mais. Dwell só depois de medir no aparelho. |
| D-JOR-1/2 | Conversão de presença em jornada; contingência manual | Continua pendente. O app não classifica jornada. |
| D-AUTH-1 | Transporte da sessão no app | Bearer do Better Auth, com o token no armazenamento seguro. Depende do backend. |
| D-OFF-1 / D-DEV-2 | Limite offline; sessão expirada, configuração vencida e vínculo revogado enquanto offline | Continuar capturando, nunca descartar e mostrar o estado. A recuperação fica com o backend. |
| D-PRIV-1..3 | Dados, retenção e acesso às coordenadas | Coordenada só na transição. Apagar o conteúdo local N dias depois do `received` (N a definir). Requer avaliação jurídica. |
| D-MAN | Contingência manual, aprovação e papel do tablet | O tablet continua sendo a contingência física. A política manual do app vem depois. |

## 7. Próximos incrementos

1. **(feito)** Domínio, fila persistente, servidor simulado e testes.
2. Avaliador de qualidade do relógio e configuração local (revisão, vigência,
   `validUntil`, revogação, `config_applied` e `config_expired`), com testes,
   no `core/`. Não depende de decisão.
3. Depois de D-PLAT: `flutter create` em `app/` (Android), `flutter doctor`,
   um build de debug e a **cifra validada no moto g86**.
4. Depois de D-LOC: adaptador nativo do geofence com **área sintética** e
   tela técnica de diagnóstico (só depois de o protótipo ser aprovado).
   Rodar a matriz física.
5. Cliente HTTP real, só quando o backend implementar as rotas e definir
   D-AUTH-1.
