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
| Retry | Backoff exponencial com jitter, teto de 30 min (valor provisório), `Retry-After` como piso e redução do lote no 413. Só para falha transitória (ver o incremento 2). |
| Recebido só depois do ACK | O estado `received` só nasce de `accepted` ou `duplicate`. Timeout e 503 voltam para `savedLocally`. |
| Estados distintos | `savedLocally → sending → received / conflict / rejected`. "Avaliado" virá do `GET /v1/me/presence-events` e não é estado de entrega. |
| Três instantes | `observedAt` só quando o SO informa (`observedAtSource: none` quando não). `detectedAt` vem do app. `receivedAt` vem do servidor. Nenhum instante de cruzamento é inventado. |
| Reinício | Um lease vencido volta para a fila, e a sequência continua sem reutilização |
| Cifra | Com SQLite3MultipleCiphers, o arquivo não abre sem a chave nem com a chave errada, e o conteúdo não aparece em claro. **Só no desktop.** |

### Incremento 2 (10/11/2026; ainda não commitado)

| Requisito | Como |
|---|---|
| Cifra obrigatória | `LocalStore.open` é a única entrada. Ela exige `obtainKey` e confere `sqlite3mc_version()` e `PRAGMA cipher`. Recusa chave errada, arquivo existente em claro, base em memória ou URI, e confere depois que o cabeçalho gravado não está em claro. Não existe parâmetro para desligar a cifra. Os testes usam a mesma base cifrada, com chave sintética (`test/support.dart`). |
| Classes de falha | `transient` (exceção `TransportException`, 503, 429, 413 redutível) gera nova tentativa. `authOrPermission` (401/403), `contractRejection` (400, 413 com um só evento) e `internalDefect` (qualquer outra exceção) **param o envio**. A parada é gravada e só sai com `resume()` explícito. Uma resposta 200 fora do contrato vira anomalia relatada e o evento não é dado como recebido. |
| Backoff e concorrência | O contador de falhas fica gravado. Cada reserva de lote tem um `lease_token`: só quem tem o token conclui ou devolve aquele lote. Foi testado com duas conexões na mesma base. |
| Relógio | `assessClock` só devolve `trusted` quando há referência do servidor, o boot é o mesmo, o monotônico é consistente, a referência é recente e o desvio mais a ida e volta cabem na tolerância. Nos outros casos devolve `uncertain` ou `drift_suspected`. `detectedAt`, o monotônico e o `bootId` são preservados como lidos, e ficam `null` quando ausentes. |
| Configuração | O ciclo é **recebida** (só em memória) → **persistida** (commit cifrado) → **aplicada** (a plataforma confirma todas as áreas vigentes; o evento `config_applied` sai no mesmo commit). Também há falha de aplicação, substituição (resposta mais antiga é ignorada; a mesma revisão com outro conteúdo é recusada), vencimento (evento `config_expired`, uma vez) e revogação. |
| Imutabilidade | Triggers do SQLite impedem alterar `event_id`, `seq` ou `payload` e impedem apagar eventos. |
| Atribuição | O vínculo, a revisão e a área vêm do registro do geofence. Uma área ou revisão desconhecida é recusada, e nada é associado a todos os vínculos. |

### Incremento 3, parte 1: separação web e nativo (sem commit)

O núcleo passou a ter três pontos de entrada, e os casos de uso dependem só
de portas (`LocalPersistence` e `ConfigRepository`):

| Biblioteca | Conteúdo | Compila para a web |
|---|---|---|
| `presenca_core.dart` | Domínio e casos de uso, sem nenhum armazenamento | Sim |
| `presenca_core_native.dart` | `LocalStore`: SQLite **sempre cifrado**, sem mudança | Não (`dart:io`, FFI) |
| `presenca_lab.dart` | `InMemoryLabPersistence` (em memória, **sem cifra**, `isEncryptedAtRest = false`) e `SimulatedPresenceServer` | Sim |

Verificações:

- `test/persistence_contract_test.dart` roda os mesmos cenários nas duas
  persistências.
- `test/architecture_test.dart` impede que domínio, aplicação ou laboratório
  importem código nativo, e impede que o barril principal exporte
  armazenamento ou simulação.
- `dart test -p chrome test/web` roda o fluxo do laboratório **dentro do
  Chrome**.

Nada disso valida SQLite cifrado, Keystore, geofence ou segundo plano no
navegador.

### Incremento 3, parte 2: laboratório Flutter Web (sem commit)

O protótipo e a identidade visual do laboratório foram aprovados em
10/11/2026. A identidade vale **só para o laboratório**, não para o produto.

- `app/` foi criado só para web, com a dependência
  `presenca_core: path: ../core`. Ele importa apenas `presenca_lab`.
- `SimulatedGeofencePlatform` registra áreas só na memória e monta os
  callbacks sintéticos, sem leitura de localização.
- O controlador do laboratório injeta as falhas de rede ausente, 503 e ACK
  parcial no servidor simulado.
- A avaliação é escolhida à mão e é fictícia. Nenhuma marcação de jornada é
  criada.
- As fontes (licença OFL) são empacotadas no app.
- Testes: 15 (controlador, widget em 1400, 800 e 390 px, guarda de
  arquitetura). `flutter build web` compila.
- Esta versão não simula vencimento, revogação nem sessão expirada. As
  escolhas de D-CFG-1, D-LINK-1 e D-AUTH-2 aparecem, mas ainda não têm efeito
  visível.

### Incremento 3, parte 3: laboratório no emulador Android (11/11/2026)

A usuária autorizou acrescentar o Android ao laboratório, **só para o
emulador** (`ponto_dev_480x800`, Android 16, x86_64). Isso **não** aprova a
plataforma Android (D-PLAT continua pendente) e não autoriza instalar no
moto g86.

- `applicationId` provisório e só de laboratório:
  `dev.laboratorio.ponto_colaborador_lab`. O nome visível é "Lab simulado".
- O manifesto principal não declara **nenhuma** permissão; `INTERNET` aparece
  só em debug e profile, para as ferramentas do Flutter. A guarda de
  arquitetura confere isso.
- A persistência continua em memória, sem cifra: fechar o app apaga tudo. A
  tela mostra o texto certo para cada plataforma.
- Aceleração: `HypervisorPlatform` estava ativado, mas o hipervisor só subiu
  depois de um boot completo. O PC usava só hibernação desde 30/10. Agora
  `emulator -accel-check` mostra WHPX utilizável.
- Instalar o APK sempre com o serial explícito do emulador (`adb -s
  emulator-NNNN`), nunca no aparelho físico.

### App do colaborador: Etapa 1 do relatório v1.0 (11/11/2026)

Projeto separado em `mobile/`: o relatório pede não confundir o laboratório
com o app. A interface segue o álbum de 16 capturas, com a identidade da
Casa do Futuro (tokens claros e escuros, logo original), fontes e ícones
empacotados (Public Sans OFL e Lucide 0.460.0 ISC) e nenhuma dependência de
pub nova além do `uuid`, que o `core` já usava.

- **Arquitetura:** organizada por feature (`home`, `history`, `requests`,
  `areas`, `profile`, `permissions`, `delivery`, `session`).
  - Os adaptadores simulados ficam só em `lib/demo`, e uma guarda de
    arquitetura confere isso.
  - Cada uma das cinco áreas tem o próprio `Navigator` dentro de um
    `IndexedStack`: o estado é preservado e o "voltar" fecha o detalhe antes
    de sair da área.
- **Dados:** os eventos e a entrega vêm do núcleo real. "Recebido" só aparece
  com o ACK do servidor simulado, e as áreas mostram a etapa real do ciclo de
  configuração.
- **Testes:** 40 no total.
  - Menu em sequência e a partir do detalhe, círculo central tocável, voltar
    do sistema, formulário (validação, toque repetido, rascunho sem conexão,
    confirmação ao sair, rascunho mantido ao trocar de área), entrega,
    permissão, saída sem herança de dados, 320 px e fonte ×1,3 e ×1,6, alvos
    de 48.
  - 16 capturas geradas pelo próprio `flutter test`.
- **Diferenças em relação ao álbum, para decisão:**
  - Sincronização e Permissões abrem dentro da área atual, que continua
    marcada no menu. No protótipo, nenhum item fica marcado.
  - O login não mostra o avatar "AS": não há usuária antes de entrar.
  - O rodapé diz "Demonstração • dados fictícios".
  - A Sincronização mostra a última confirmação do servidor, que o relatório
    pede e o álbum não tem.
  - Ações de texto têm área de toque de 48 (no protótipo, 40).
  - A Public Sans substitui a Segoe UI, com o peso 650 aproximado para 700.

#### Layout adaptativo (`lib/shared/layout/cdf_layout.dart`)

Uma única fonte de regra para o que varia com o dispositivo. A classe é
escolhida pela largura e pela altura úteis, já sem as barras do sistema.

- **Largura:** compacta (< 380), padrão (380–599), média (600–839) ou
  expandida (≥ 840).
- **Altura:** baixa (< 600) ou normal.

O que varia: margem lateral (16, 22 ou 32), escala dos títulos (28, 26 ou
24; login 34 ou 28), espaços verticais, cabeçalho e o bloco "Última
detecção". Em tela larga, o conteúdo, o cabeçalho e os itens do menu ficam
numa coluna central de até 560. Cores, raios, ícones e o círculo de 52 não
mudam.

- **Nos contextos do álbum, os valores são idênticos aos aprovados.** Um
  teste trava isso.
- O conteúdo rola por baixo da faixa transparente do círculo central e
  ganha um respiro final igual à altura do menu.
- **Matriz testada:** emulador 320 × 533, 360 × 640, 400 × 860, 412 × 915,
  paisagem 800 × 360, tablet 768 × 1024 e navegador 1280 × 800, cada um com
  fonte × 1 e × 1,3, além do teclado aberto.
- **Adaptação nova, para revisão da dona:** tela baixa, paisagem e tela
  larga. Capturas em `mobile/build/screenshots/ctx-*.png`.

### Login real no backend (11/11/2026, provisório por cookie)

Pedido da usuária. O backend está em produção em `api-ponto.margemshop.com.br`
(`/health/ready` ok). O contrato foi conferido só lendo o código do backend,
branch `feat/acesso-do-funcionario`.

- **Modo:** é escolhido no build com `--dart-define=API_BASE_URL=https://…`.
  Sem isso, o app abre em demonstração. Na web, fica sempre em demonstração.
  O endereço não fica fixo no código, e um teste confere isso.
- **Rotas usadas:**
  - `POST /v1/auth/sign-in/email`, enviado sem cookie antigo;
  - `GET /v1/me`;
  - `GET /v1/me/memberships`.
- **Sessão:** o cookie `__Secure-ponto.session_token` fica no
  armazenamento seguro do Android, só como `nome=valor`. A senha nunca é
  guardada e o backup automático do app está desligado.
- **Isolamento:** rede e armazenamento seguro ficam só em `lib/integration/`.
  O manifesto declara apenas `INTERNET`, sem localização.
- **Tratado:** senha errada, conta desativada, senha temporária (orienta
  usar o portal), sem acesso ativo, mais de uma empresa (escolha
  explícita), 429, falta de rede (não apaga a sessão), resposta fora do
  contrato e sessão retomada ou expirada.
- **Continua simulado, com aviso na tela:** detecções, áreas, solicitações
  e o vínculo. O backend não tem essas rotas nem "meu vínculo" para o
  funcionário.
- **Testes:** feitos contra um servidor falso que imita o backend. Nenhum
  login foi feito em produção: a usuária ainda não tem conta.

- **Só colaborador:** o app aceita apenas acessos com o papel `employee`.
  Contas só de gestão (`tenant_admin`, `hr`, `manager`) recebem "use o
  portal". A fronteira de segurança continua sendo o backend.
- **Senha temporária:** a troca é feita no próprio app, na tela "Crie sua
  senha".
  - O app chama `POST /v1/auth/change-password` com `revokeOtherSessions` e
    guarda a sessão nova que o servidor emite.
  - Sair chama `POST /v1/auth/sign-out` e encerra a sessão no servidor.
  - Nos dois casos o app envia `Origin` igual à origem da API, porque o
    Better Auth confia na origem do próprio `baseURL`
    (`better-auth/dist/context/helpers.mjs:73-74`).
  - **Depende de `BETTER_AUTH_URL` de produção ser o endereço da API.** Não
    deu para verificar daqui. Se não for, a troca mostra "tente pelo
    portal" e a saída apaga a sessão só do aparelho.

### Login com Google no app (11/11/2026)

Pedido da usuária: o mesmo login com Google do portal, também no app.

- **Como funciona:** o app abre o seletor de contas do Google no aparelho
  (plugin `google_sign_in` 7.2.0, Credential Manager no Android), recebe um
  ID token e envia em `POST /v1/auth/sign-in/social`
  `{provider: "google", idToken: {token}}`. A API confere assinatura,
  emissor, público e validade e devolve o mesmo cookie de sessão do login
  por senha. Não há navegador nem redirecionamento.
- **Mesmas regras do portal:** só entra quem já tem conta criada pelo RH,
  pelo e-mail que o Google atesta como verificado. Nenhuma conta é criada.
  O papel `employee`, a escolha de empresa e a troca de senha temporária
  valem igual.
- **Backend:** não precisou de mudança de código. O contrato está coberto
  por `test/integration/google-id-token.int-spec.ts` (token forjado, de
  outro app, vencido, e-mail sem conta, conta desativada).
- **Build:** o botão só aparece com
  `--dart-define=GOOGLE_SERVER_CLIENT_ID=….apps.googleusercontent.com`,
  que é o client ID "Aplicativo da Web" já usado pela API
  (`GOOGLE_CLIENT_ID`). Não é segredo; o client secret **nunca** entra no
  app. O valor não fica fixo no código, e um teste confere isso.
- **Google Cloud (pendente, é da dona da conta):** no mesmo projeto do
  client da API, criar um client OAuth do tipo **Android** com o nome do
  pacote do app e o SHA-1 da chave que assina o APK. Um client por chave
  (debug e release). Sem isso o Google recusa no aparelho.
- **Isolamento:** o plugin fica só em `lib/integration/google/`; as telas
  falam com a porta `GoogleIdTokenSource`. O app pede só a identidade, sem
  escopos extras. O token não é guardado nem registrado em log.
- **Tratado:** desistir no seletor (sem erro), conta do Google sem
  cadastro, vínculo recusado, Google indisponível no aparelho ou desligado
  no servidor, conta desativada, 429 e falta de rede. Conta recusada é
  esquecida, para a pessoa escolher outra; sair também a esquece.
- **Testes:** contra servidor falso e Google falso. **Nenhum login com
  Google foi feito em aparelho real nem em produção**: depende do client
  Android acima.

### Build automático do APK (11/11/2026)

- **Workflow:** `.github/workflows/build-android.yml`. Em pull request, push
  na `main` e execução manual: `flutter analyze`, `flutter test` e o APK de
  release assinado, que fica como artefato da execução por 30 dias.
- **Ambiente `production` do repositório** (Settings → Environments):
  - secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
    `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`;
  - variables: `API_BASE_URL` e `GOOGLE_SERVER_CLIENT_ID`.
- **Chave de release:** fica fora do repositório. Nesta máquina, o Gradle
  a lê de `mobile/android/key.properties` (ignorado pelo git); sem chave, o
  release local sai assinado com a de debug. O workflow falha se o APK
  sair assinado com a chave de debug.
- **Perder a chave de release impede atualizar o app já instalado.** Ela
  precisa de cópia de reserva fora desta máquina.
- **Google Cloud:** cada chave tem o próprio SHA-1 e precisa da própria
  credencial OAuth do tipo Android. O resumo de cada execução do workflow
  mostra o SHA-1 do APK gerado.
- O workflow não publica em loja nem distribui o APK: só gera o arquivo.

### Permissão da câmera pedida pelo app (12/11/2026)

A foto estava sendo recusada no celular com o aviso genérico "Câmera
indisponível — Permita o uso da câmera…", que o app usava para três falhas
diferentes. No emulador o caminho todo funcionou (câmera do sistema, foto,
checagem de rosto), então a causa no celular ainda não está confirmada.

- O manifesto passa a declarar `CAMERA` (com `uses-feature` não
  obrigatório). Com isso o plugin **pede a permissão na hora da foto**
  (diálogo do Android), como o relatório v2 pede. Conferido no emulador:
  o diálogo aparece; "Não permitir" vira o aviso "Permita a câmera";
  "Permitir" abre a câmera.
- Cada falha tem aviso próprio e um código curto no fim (ex.:
  `picker:camera_access_denied`, `face:…`, `read:…`), sem imagem nem dado
  pessoal, para identificar o problema no aparelho.
- Câmera ou localização negadas oferecem "Abrir configurações do app".
- Tamanho mínimo do rosto na checagem: de 20% para 15% da imagem.

### Relatório v2.0: menu novo e + Registrar em quatro etapas (12/11/2026)

Pedido da usuária, com o relatório "App do colaborador — todas as páginas e
estados v2.0". **Substitui o fluxo da seção seguinte** (localização cria o
ponto provisório, selfie em até 5 minutos):

- **Menu:** Início · Histórico · + Registrar · Solicitações · Perfil. Áreas
  deixa de ser aba: abre pelo Início ("Minha área" → "Ver todas") e pelo
  Perfil, com Início selecionado.
- **+ Registrar:** 1. valida a localização ATUAL → 2. foto frontal nova,
  com prévia ("Usar esta foto" / "Tirar outra foto") → 3. Entrada ou Saída →
  resumo e confirmação. Sem localização validada não abre câmera; sem foto
  não escolhe tipo. Nada é enviado antes de confirmar.
- **Mudança de política (pelo relatório):** fora da área, localização
  negada/desligada/sem sinal, precisão pior que o raio da área ou empresa
  sem área cadastrada **bloqueiam** o registro (antes: aceito e
  sinalizado). "Relatar um problema" abre uma nova solicitação.
- **Validação no aparelho:** busca a configuração vigente
  (`GET /v1/me/attendance`, que já traz centro e raio das áreas do vínculo),
  lê o GPS uma vez e compara a distância com o raio. O servidor continua
  avaliando a localização por conta própria e pode sinalizar o ponto.
- **Gravação:** na confirmação, `POST /v1/me/punches` e logo em seguida
  `POST /v1/me/punches/{id}/face`. Sucesso só depois da resposta do servidor
  ("Recebido pelo servidor"). Queda de rede: "tentar de novo" reaproveita o
  mesmo ponto (mesmo `clientEventId`), sem duplicar.
- **Sessão de registro:** cada sessão tem número; respostas que chegam
  depois de cancelar, sair da aba ou recomeçar são ignoradas. Sair do
  + Registrar descarta a sessão; voltar recomeça pela localização. Toque
  duplo não grava duas vezes.
- **Validade das evidências:** a janela que o servidor informa para a foto
  (`faceWindowSeconds`, hoje 5 min). Vencida, volta à etapa 1.
- **Demonstração:** o mesmo fluxo, todo simulado (sem GPS nem câmera); o
  ponto fica "salvo no aparelho · aguardando envio" e aparece no Histórico
  como "Entrada manual".
- **Backend, APP_TABLET e portal não foram alterados.**

Pendências reais desta etapa:

- **Offline:** sem internet o ponto não é gravado (nem localmente). A fila
  cifrada de foto + ponto descrita no relatório (seção 8) não existe ainda.
- **Precisão e idade:** o limite de precisão usado é o raio da área e a
  validade é a janela da foto; os valores definitivos são decisão de
  política.
- Áreas sem área cadastrada bloqueiam o ponto: a empresa precisa cadastrar
  a área antes de usar o app.
- Nada disso foi testado em aparelho real (GPS, câmera, precisão).

### Ponto real pelo app: localização + selfie (11/11/2026)

Pedido da usuária, que **muda decisões anteriores deste documento**: o app
passa a ler a localização e a usar selfie. Respostas dela às perguntas:

- A **localização** registra um ponto provisório ("simulado"). Sozinho, ele
  não conta.
- A **selfie** é o que homologa o ponto. Sem comparação automática: é
  evidência para o RH (opção escolhida entre três).
- O **gatilho** é o horário da escala: o celular vibra e avisa.
- **Fora da área** o ponto é aceito e fica sinalizado.

O que foi feito:

- **Fluxo:** cartão "Seu ponto hoje" no início (modo real) → etapa 1 lê a
  localização e cria o ponto provisório no servidor → etapa 2 tira a selfie,
  em até 5 minutos, e confirma. Fechar antes da selfie deixa o registro só
  com a localização; ao voltar dentro da janela, o app retoma o mesmo ponto.
- **Localização:** uma leitura, só na hora do registro (`geolocator`,
  permissão "durante o uso"). **Sem localização em segundo plano e sem
  geofence**: o app não acompanha a pessoa. Negar a permissão não impede o
  ponto; ele segue sem coordenadas e sinalizado. O indicador de localização
  simulada do Android vai junto.
- **Selfie:** câmera frontal do sistema (`image_picker`), reduzida para até
  200 KB. O ML Kit confere **no aparelho** se há um rosto na foto
  (`google_mlkit_face_detection`); não identifica a pessoa e nada vai ao
  Google. A foto não é guardada no aparelho.
- **Avisos:** locais (`flutter_local_notifications`), agendados a partir da
  escala dos próximos 7 dias, em modo inexato (o Android pode atrasar alguns
  minutos). A permissão só é pedida quando a pessoa toca em "Ativar avisos".
  Sair da conta apaga os avisos.
- **Servidor:** `GET /v1/me/attendance`, `POST /v1/me/punches` e
  `POST /v1/me/punches/{id}/face` (backend, migração 0010). As escritas
  levam `Origin` igual à origem da API.
- **Isolamento:** os plugins do aparelho ficam só em
  `lib/integration/device/`. Manifesto: INTERNET, localização em primeiro
  plano, notificações, vibração e reinício. Um teste confere a lista.

Limites conhecidos:

- **Não é ponto oficial para fins legais** (sem NSR, comprovante e AFD).
- **Sem fila offline:** sem internet, o ponto não é registrado. O núcleo de
  fila (`core/`) ainda não foi ligado a este fluxo.
- **Selfie é dado pessoal sensível:** falta o termo de consentimento e a
  regra de retenção (D-PRIV), que dependem de avaliação jurídica.
- A checagem de rosto não detecta foto de foto.
- O histórico, as áreas e as solicitações do app continuam em demonstração.
- **Nada disto foi testado em aparelho real.** Os testes usam servidor,
  GPS, câmera e avisos falsos.

**Pendências do backend (fora desta frente):**

- **D-AUTH-1:** token para o app (plugin `bearer`). Elimina a dependência do
  `Origin` declarado pelo app descrita acima.
- Rota de "meu vínculo" e as rotas de presença e solicitações (contrato
  `presenca-v1`).
- Cookie entre domínios (`SESSION_COOKIE_CROSS_SITE` e `TRUSTED_ORIGINS`)
  para permitir login real também na web.

### Limitações conhecidas do núcleo (registradas, não corrigidas)

- A cifra só foi verificada no **Windows**. No Android, a chave no Keystore
  (`KeyProvider`) e o funcionamento do SQLite3MultipleCiphers não foram
  testados.
- O vencimento da configuração e as áreas vigentes usam o **relógio do
  aparelho**, que pode ter sido alterado. O núcleo grava a qualidade do
  relógio, e o servidor reavalia (`config_expired`).
- Uma resposta 200 com anomalia repetida é reenviada indefinidamente, com
  backoff limitado a 30 min. Não há limite de tentativas: isso é decisão.
- `maxQueuedEvents` ainda não é aplicado, e a fila não pode ser apagada
  (retenção D-PRIV). O que fazer com a fila cheia está pendente.
- `wallClockJump` existe, mas o evento `clock_change_detected` ainda não é
  emitido de forma automática: depende do sinal nativo de troca de hora.
- O contador de falhas é lido e gravado fora da transação do `settle`. Com
  dois isolates ao mesmo tempo, a contagem pode sair imprecisa, o que só
  afeta o intervalo do backoff.
- Uma base do esquema 1 (commit `fa53e9c`) é recusada sem migração. Ela só
  existiu em diretórios temporários de teste.

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
| D-CFG-1 | Detecção com a configuração vencida | O núcleo oferece `recordAndFlag` ou `refuse`, **sem valor padrão** |
| D-LINK-1 | Detecção para vínculo revogado no aparelho | Idem |
| D-AUTH-2 | Detecção depois de 401/403, antes de nova autenticação | Idem. Quando retirar a parada (`resume`) também está pendente. |
| D-CLK-1 | Tolerância e idade máxima da referência de horário | Parâmetros obrigatórios, sem valor padrão. Os testes usam 5 s e 12 h, só como exemplo. |
| D-RET-1 | Fila cheia (`maxQueuedEvents`) e limite de tentativas para resposta anômala | Pendente |

## 7. Próximos incrementos

1. **(feito)** Domínio, fila persistente, servidor simulado e testes.
2. **(feito, sem commit)** Cifra obrigatória, classes de falha, backoff
   gravado, token de reserva, relógio e ciclo de configuração: 79 testes.
3. Depois de D-PLAT: `flutter create` em `app/` (Android), `flutter doctor`,
   um build de debug e a **cifra validada no moto g86**.
4. Depois de D-LOC: adaptador nativo do geofence com **área sintética** e
   tela técnica de diagnóstico (só depois de o protótipo ser aprovado).
   Rodar a matriz física.
5. Cliente HTTP real, só quando o backend implementar as rotas e definir
   D-AUTH-1.
