# Matriz de testes físicos — geofence do app pessoal

**Estado em 10/11/2026: nenhum cenário foi testado em aparelho.** Ainda não
existe build com integração nativa.

Legenda: **TESTADO-OK** · **FALHOU** · **NÃO TESTADO** · **N/A**. Só marcar
TESTADO-OK com evidência (log da fila + horário + print), nunca por suposição.

## Aparelhos

| ID | Fabricante/modelo | SO / API | Patch | Pessoal/corp. | Observação |
|---|---|---|---|---|---|
| A1 | motorola moto g86 5G | Android 16 / API 36 | 2026-09-01 | **a confirmar** | Visto via `adb` (TLS sem fio) em 10/11/2026. Uso no piloto **não** aprovado. |
| I1 | — | iOS — | — | — | Nenhum aparelho iOS disponível. |

## Configuração de cada rodada (preencher)

Área sintética (centro e raio), `dwellSeconds`, responsividade, versão do app,
`configRevision`, economia de bateria (ligada/desligada; modo do fabricante),
permissão de localização (precisa / aproximada / "o tempo todo"), estado da
rede, data e hora de início e fim.

## Cenários

Para cada cenário: **entrada**, **saída** e, se aprovado, **permanência (dwell)**.
Registrar o atraso entre o cruzamento real (anotado à mão) e o `detectedAt`
e o `receivedAt`; se houve duplicação, ordem invertida ou perda; e se houve
`detection_status`.

| # | Cenário | A1 Android | I1 iOS |
|---|---|---|---|
| F-01 | App aberto em primeiro plano | NÃO TESTADO | NÃO TESTADO |
| F-02 | App em segundo plano (tela ligada) | NÃO TESTADO | NÃO TESTADO |
| F-03 | Segundo plano com tela desligada / parado (doze) | NÃO TESTADO | NÃO TESTADO |
| F-04 | Processo encerrado pelo sistema (pressão de memória) | NÃO TESTADO | NÃO TESTADO |
| F-05 | Encerrado pelo usuário: deslizar dos recentes | NÃO TESTADO | NÃO TESTADO |
| F-06 | Encerrado pelo usuário: "Forçar parada" nas configurações (Android) | NÃO TESTADO | N/A |
| F-07 | Reinício do aparelho; recadastro dos geofences no boot | NÃO TESTADO | NÃO TESTADO |
| F-08 | Economia de bateria do sistema ligada | NÃO TESTADO | NÃO TESTADO |
| F-09 | Restrição de bateria do app / otimização do fabricante | NÃO TESTADO | N/A |
| F-10 | Localização desligada e depois religada (gera `detection_status`?) | NÃO TESTADO | NÃO TESTADO |
| F-11 | Permissão negada na primeira solicitação | NÃO TESTADO | NÃO TESTADO |
| F-12 | Permissão "o tempo todo" revogada com o app instalado | NÃO TESTADO | NÃO TESTADO |
| F-13 | Só localização aproximada concedida | NÃO TESTADO | NÃO TESTADO |
| F-14 | Sem rede no cruzamento; envio ao voltar a rede | NÃO TESTADO | NÃO TESTADO |
| F-15 | Sem rede por mais de `maxEventAgeHours` | NÃO TESTADO | NÃO TESTADO |
| F-16 | Parar perto da borda (oscilação entrada/saída) | NÃO TESTADO | NÃO TESTADO |
| F-17 | Áreas sobrepostas (dois eventos de entrada) | NÃO TESTADO | NÃO TESTADO |
| F-18 | Passar rápido pela área (veículo) | NÃO TESTADO | NÃO TESTADO |
| F-19 | Troca de hora/fuso manual no aparelho | NÃO TESTADO | NÃO TESTADO |
| F-20 | Limpar dados do app / reinstalar (perda de fila e de geofences) | NÃO TESTADO | NÃO TESTADO |
| F-21 | Atualização do app com fila pendente | NÃO TESTADO | NÃO TESTADO |
| F-22 | Localização simulada (opção de desenvolvedor) e o sinal `mockReported` | NÃO TESTADO | N/A |

## Registro de execuções

| Data | Aparelho | Cenário | Configuração | Resultado | Evidência | Responsável |
|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — |

## Testes automatizados que **não** substituem esta matriz

`core/test` cobre, em desktop e com o servidor simulado: duplicação, ordem
invertida, rede ausente, retry com backoff, 503 antes do commit, timeout
depois do commit, ACK parcial, recusa, conflito, 401/403/413/429, reinício com
lote em voo e cifra do arquivo. Nada disso prova o comportamento do geofence
nem da cifra **no aparelho**.
