import 'dart:convert';
import 'dart:typed_data';

import 'package:casa_futuro_colaborador/app/app.dart';
import 'package:casa_futuro_colaborador/app/app_services.dart';
import 'package:casa_futuro_colaborador/features/punch/punch_controller.dart';
import 'package:casa_futuro_colaborador/features/punch/punch_models.dart';
import 'package:casa_futuro_colaborador/integration/backend/backend_auth_gateway.dart';
import 'package:casa_futuro_colaborador/integration/backend/backend_punch_gateway.dart';
import 'package:casa_futuro_colaborador/integration/backend/session_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'backend_auth_gateway_test.dart' show FakeBackend;
import 'support.dart';

const _tenant = '00000000-0000-4000-8000-0000000000a1';
const _link = '00000000-0000-4000-8000-0000000000b1';

/// Servidor FALSO do ponto, com as respostas do backend (módulo punches).
class FakePunchServer {
  final requests = <http.Request>[];
  final punches = <Map<String, Object?>>[];
  DateTime now = DateTime.utc(2026, 11, 11, 11, 0); // 08:00 em São Paulo
  bool hasArea = true;
  bool canPunch = true;
  List<Map<String, Object?>> links = [{}];
  String locationStatus = 'inside';
  int? distanceM = 40;
  String? registerError;
  String? faceError;
  int attendanceStatus = 200;

  /// Quantas vezes o envio da foto cai por falta de rede (antes de chegar).
  int faceDrops = 0;

  Map<String, Object?> _day(String date, String kind) => {
        'date': date,
        'kind': kind,
        'startsAt': kind == 'work' ? '08:00' : null,
        'endsAt': kind == 'work' ? '17:00' : null,
        'breakMinutes': kind == 'work' ? 60 : 0,
        'overnight': false,
        'scheduleName': kind == 'work' ? 'Comercial 40h' : null,
      };

  String get nextKind => punches.where((p) => p['status'] == 'confirmed').lastOrNull?['kind'] == 'entry' ? 'exit' : 'entry';

  Map<String, Object?> get attendance => {
        'serverTime': now.toIso8601String(),
        'today': '2026-11-11',
        'timeZone': 'America/Sao_Paulo',
        'faceWindowSeconds': 300,
        'links': [
          for (final _ in links)
            {
              'employmentLinkId': _link,
              'companyId': '00000000-0000-4000-8000-0000000000c9',
              'companyName': 'Casa do Futuro',
              'establishmentName': 'Loja Centro',
              'canPunch': canPunch,
              'nextKind': nextKind,
              'days': [_day('2026-11-11', 'work'), _day('2026-11-12', 'work'), _day('2026-11-13', 'work'), _day('2026-11-14', 'off'), _day('2026-11-15', 'off'), _day('2026-11-16', 'work'), _day('2026-11-17', 'work')],
              'areas': hasArea
                  ? [
                      {'id': 'a1', 'name': 'Loja Centro', 'latitude': -23.5, 'longitude': -46.6, 'radiusM': 150}
                    ]
                  : <Object>[],
              'punchesToday': punches,
            }
        ],
      };

  http.Response _error(int status, String code) => http.Response(jsonEncode({'error': {'code': code, 'message': 'x'}}), status);

  MockClient get client => MockClient((r) async {
        requests.add(r);
        if (r.headers['cookie'] != '__Secure-ponto.session_token=tok.sig') return _error(401, 'unauthenticated');
        if (r.headers['x-tenant-id'] != _tenant) return _error(400, 'tenant_required');
        if (r.method == 'POST' && r.headers['origin'] != 'https://api.exemplo.test') return _error(403, 'origin_not_allowed');
        final path = r.url.path;
        if (r.method == 'GET' && path == '/v1/me/attendance') {
          if (attendanceStatus != 200) return _error(attendanceStatus, 'internal_error');
          return http.Response(jsonEncode(attendance), 200, headers: {'content-type': 'application/json; charset=utf-8'});
        }
        if (r.method == 'POST' && path == '/v1/me/punches') {
          if (registerError != null) return _error(registerError == 'punch_too_soon' ? 409 : 422, registerError!);
          final b = jsonDecode(r.body) as Map;
          final located = b['location'] != null;
          final p = <String, Object?>{
            'id': 'p${punches.length + 1}',
            'kind': b['kind'],
            'recordedAt': now.toIso8601String(),
            'status': 'pending_face',
            'locationStatus': located ? (hasArea ? locationStatus : 'no_area') : 'unavailable',
            'areaName': located && hasArea ? 'Loja Centro' : null,
            'distanceM': located && hasArea ? distanceM : null,
            'mockLocation': located && (b['location'] as Map)['mock'] == true,
            'faceDeadline': now.add(const Duration(minutes: 5)).toIso8601String(),
          };
          punches.add(p);
          return http.Response(jsonEncode(p), 201, headers: {'content-type': 'application/json; charset=utf-8'});
        }
        final face = RegExp(r'^/v1/me/punches/(p\d+)/face$').firstMatch(path);
        if (r.method == 'POST' && face != null && faceDrops > 0) {
          faceDrops--;
          throw http.ClientException('sem rede');
        }
        if (r.method == 'POST' && face != null) {
          if (faceError != null) return _error(faceError == 'punch_already_confirmed' ? 409 : 422, faceError!);
          final p = punches.firstWhere((x) => x['id'] == face.group(1));
          p['status'] = 'confirmed';
          p['faceDeadline'] = null;
          return http.Response(jsonEncode(p), 200, headers: {'content-type': 'application/json; charset=utf-8'});
        }
        return http.Response('not found', 404);
      });
}

class FakeLocation implements LocationSource {
  LocationResult result = const LocationResult.ok(DeviceLocation(latitude: -23.4996, longitude: -46.6, accuracyM: 12));
  int reads = 0;
  @override
  Future<LocationResult> current() async {
    reads++;
    return result;
  }
}

/// PNG 1×1 válido: a prévia da foto consegue mostrar.
final tinyPng = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');

class FakeCamera implements SelfieCamera {
  SelfieResult result = SelfieResult.ok(tinyPng);
  int shots = 0;
  int settings = 0;
  @override
  Future<SelfieResult> capture() async {
    shots++;
    return result;
  }

  @override
  Future<void> openSettings() async => settings++;
}

class FakeReminders implements PunchReminders {
  bool on = false;
  bool grant = true;
  List<PunchReminder> scheduled = [];
  String? timeZone;
  int clears = 0;
  @override
  Future<bool> enabled() async => on;
  @override
  Future<bool> request() async => on = grant;
  @override
  Future<void> schedule(List<PunchReminder> reminders, {required String timeZone}) async {
    scheduled = reminders;
    this.timeZone = timeZone;
  }

  @override
  Future<void> clear() async {
    clears++;
    scheduled = [];
  }
}

void main() {
  setUpAll(loadAppFonts);
  final base = Uri.parse('https://api.exemplo.test');

  group('avisos no horário da escala', () {
    Attendance att({List<PunchRecord> punches = const [], bool canPunch = true}) => Attendance(
          serverTime: DateTime.utc(2026, 11, 11, 11),
          today: '2026-11-11',
          timeZone: 'America/Sao_Paulo',
          faceWindowSeconds: 300,
          links: [
            LinkAttendance(
              employmentLinkId: _link,
              companyName: 'Casa do Futuro',
              canPunch: canPunch,
              nextKind: PunchKind.entry,
              areas: const [WorkArea(id: 'a1', name: 'Loja Centro', latitude: -23.5, longitude: -46.6, radiusM: 150)],
              punchesToday: punches,
              days: const [
                DayPlan(date: '2026-11-11', kind: DayKind.work, startsAt: '08:00', endsAt: '17:00'),
                DayPlan(date: '2026-11-12', kind: DayKind.off),
                DayPlan(date: '2026-11-13', kind: DayKind.work, startsAt: '22:00', endsAt: '06:00', overnight: true),
                DayPlan(date: '2026-11-14', kind: DayKind.unassigned),
              ],
            ),
          ],
        );
    List<String> slots(List<PunchReminder> r) => [for (final x in r) '${x.kind.name} ${x.date} ${x.time}'];

    test('entrada e saída de cada dia trabalhado; folga e dia sem escala não avisam', () {
      final r = buildReminders(att(), nowDate: '2026-11-11', nowTime: '07:00');
      expect(slots(r), ['entry 2026-11-11 08:00', 'exit 2026-11-11 17:00', 'entry 2026-11-13 22:00', 'exit 2026-11-14 06:00']);
      expect(r.first.title, 'Hora de registrar a entrada');
      expect(r.first.body, contains('+ Registrar: localização e foto'));
      expect({for (final x in r) x.id}.length, r.length, reason: 'ids únicos');
    });

    test('horário que já passou hoje não é agendado; saída noturna cai no dia seguinte', () {
      expect(slots(buildReminders(att(), nowDate: '2026-11-11', nowTime: '08:00')).first, 'exit 2026-11-11 17:00');
      expect(slots(buildReminders(att(), nowDate: '2026-11-13', nowTime: '23:00')), ['exit 2026-11-14 06:00']);
    });

    test('ponto de hoje já confirmado não gera aviso; provisório ainda gera', () {
      PunchRecord p(PunchStatus s) => PunchRecord(id: 'x', kind: PunchKind.entry, recordedAt: DateTime.utc(2026, 11, 11, 10, 58), status: s, verdict: LocationVerdict.inside);
      expect(slots(buildReminders(att(punches: [p(PunchStatus.confirmed)]), nowDate: '2026-11-11', nowTime: '07:00')).first, 'exit 2026-11-11 17:00');
      expect(slots(buildReminders(att(punches: [p(PunchStatus.pendingFace)]), nowDate: '2026-11-11', nowTime: '07:00')).first, 'entry 2026-11-11 08:00');
    });

    test('empresa desativada não avisa', () {
      expect(buildReminders(att(canPunch: false), nowDate: '2026-11-11', nowTime: '07:00'), isEmpty);
    });
  });

  group('servidor (BackendPunchGateway)', () {
    late FakePunchServer server;
    late MemorySessionStore store;
    late BackendPunchGateway gw;
    setUp(() {
      server = FakePunchServer();
      store = MemorySessionStore()..value = '__Secure-ponto.session_token=tok.sig';
      gw = BackendPunchGateway(baseUrl: base, store: store, client: server.client);
    });
    Future<PunchFailure> failureOf(Future<Object?> f) async {
      try {
        await f;
      } on PunchException catch (e) {
        return e.failure;
      }
      fail('esperava PunchException');
    }

    test('lê a jornada: escala, área e próximo ponto', () async {
      final a = await gw.attendance(_tenant);
      expect(a.today, '2026-11-11');
      expect(a.faceWindowSeconds, 300);
      final l = a.links.single;
      expect([l.companyName, l.establishmentName, l.canPunch, l.nextKind, l.hasArea], ['Casa do Futuro', 'Loja Centro', true, PunchKind.entry, true]);
      expect([l.areas.single.name, l.areas.single.latitude, l.areas.single.radiusM], ['Loja Centro', -23.5, 150]);
      expect(l.today!.summary, '08:00 às 17:00');
      expect(l.days[3].summary, 'Folga');
      expect(server.requests.single.headers.containsKey('origin'), isFalse, reason: 'leitura não precisa de Origin');
    });

    test('etapa 1 envia a localização com Origin da API e tenant; etapa 2 envia a selfie em base64', () async {
      final p = await gw.register(_tenant,
          employmentLinkId: _link, clientEventId: 'evt-1', kind: PunchKind.entry, location: const DeviceLocation(latitude: -23.4996, longitude: -46.6, accuracyM: 12, mock: true));
      expect([p.status, p.verdict, p.distanceM, p.mockLocation], [PunchStatus.pendingFace, LocationVerdict.inside, 40, true]);
      expect(p.faceDeadline!.difference(p.recordedAt), const Duration(minutes: 5));
      final sent = server.requests.last;
      expect(sent.headers['origin'], 'https://api.exemplo.test');
      expect(sent.headers['x-tenant-id'], _tenant);
      final body = jsonDecode(sent.body) as Map;
      expect(body['clientEventId'], 'evt-1');
      expect(body['location'], {'latitude': -23.4996, 'longitude': -46.6, 'accuracyM': 12, 'mock': true});

      final done = await gw.confirm(_tenant, p.id, Uint8List.fromList([0xff, 0xd8, 0xff]));
      expect(done.confirmed, isTrue);
      expect((jsonDecode(server.requests.last.body) as Map)['dataBase64'], base64Encode([0xff, 0xd8, 0xff]));
    });

    test('sem localização o corpo leva null e o ponto volta sinalizado', () async {
      final p = await gw.register(_tenant, employmentLinkId: _link, clientEventId: 'evt-2', kind: PunchKind.entry, location: null);
      expect((jsonDecode(server.requests.last.body) as Map).containsKey('location'), isTrue);
      expect((jsonDecode(server.requests.last.body) as Map)['location'], isNull);
      expect([p.verdict, p.flagged], [LocationVerdict.unavailable, true]);
    });

    test('cada recusa do servidor vira a falha certa', () async {
      Future<PunchFailure> reg() => failureOf(gw.register(_tenant, employmentLinkId: _link, clientEventId: 'e', kind: PunchKind.entry, location: null));
      server.registerError = 'punch_too_soon';
      expect(await reg(), PunchFailure.tooSoon);
      server.registerError = 'employment_link_not_found';
      expect(await reg(), PunchFailure.noLink);
      server.registerError = 'company_inactive';
      expect(await reg(), PunchFailure.companyInactive);
      server.registerError = null;
      final p = await gw.register(_tenant, employmentLinkId: _link, clientEventId: 'e', kind: PunchKind.entry, location: null);
      for (final (code, failure) in [
        ('punch_face_window_expired', PunchFailure.windowExpired),
        ('punch_already_confirmed', PunchFailure.alreadyConfirmed),
        ('invalid_selfie', PunchFailure.invalidSelfie),
        ('selfie_too_large', PunchFailure.invalidSelfie),
      ]) {
        server.faceError = code;
        expect(await failureOf(gw.confirm(_tenant, p.id, Uint8List(3))), failure, reason: code);
      }
    });

    test('sem sessão guardada, sessão recusada e sem rede', () async {
      store.value = null;
      expect(await failureOf(gw.attendance(_tenant)), PunchFailure.sessionExpired);
      expect(server.requests, isEmpty);
      store.value = '__Secure-ponto.session_token=outra';
      expect(await failureOf(gw.attendance(_tenant)), PunchFailure.sessionExpired);
      final offline = BackendPunchGateway(baseUrl: base, store: MemorySessionStore()..value = 'c=1', client: MockClient((_) async => throw http.ClientException('sem rede')));
      expect(await failureOf(offline.attendance(_tenant)), PunchFailure.network);
    });
  });

  group('+ Registrar pela tela', () {
    Future<(AppServices, FakePunchServer, FakeLocation, FakeCamera, FakeReminders)> pumpReal(WidgetTester t, {void Function(FakePunchServer, FakeLocation, FakeCamera, FakeReminders)? setup, bool dark = false}) async {
      t.view.physicalSize = const Size(400, 1500);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final auth = FakeBackend();
      final server = FakePunchServer();
      final location = FakeLocation();
      final camera = FakeCamera();
      final reminders = FakeReminders();
      setup?.call(server, location, camera, reminders);
      final store = MemorySessionStore();
      var ids = 0;
      final s = AppServices(
        now: () => demoNow,
        auth: BackendAuthGateway(baseUrl: base, store: store, client: auth.client),
        punch: PunchDeps(
          gateway: BackendPunchGateway(baseUrl: base, store: store, client: server.client),
          location: location,
          camera: camera,
          reminders: reminders,
          now: () => server.now,
          newId: () => 'evt-${++ids}',
        ),
      );
      addTearDown(s.dispose);
      await t.pumpWidget(RepaintBoundary(key: rootKey, child: CasaFuturoApp(services: s, themeMode: dark ? ThemeMode.dark : ThemeMode.light)));
      await s.init();
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField).first, 'ana@casadofuturo.com.br');
      await t.enterText(find.byType(TextFormField).last, 'senha-correta-12');
      await tapText(t, 'Entrar');
      return (s, server, location, camera, reminders);
    }

    Iterable<http.Request> writes(FakePunchServer s) => s.requests.where((r) => r.method == 'POST');

    /// Botão cujo texto também é o título da tela: toca o último (o botão).
    Future<void> press(WidgetTester t, String label) async {
      final f = find.text(label).last;
      await t.ensureVisible(f);
      await t.pumpAndSettle();
      await t.tap(f);
      await settleSimulated(t);
    }

    Future<void> toConfirm(WidgetTester t, {String kind = 'Entrada'}) async {
      await tapNav(t, 'Registrar');
      await tapText(t, 'Tirar foto');
      await tapText(t, 'Usar esta foto');
      await chooseKind(t, kind);
    }

    testWidgets('início mostra a escala de hoje, a área real e o atalho para registrar', (t) async {
      await pumpReal(t);
      expect(find.text('Seu ponto hoje'), findsOneWidget);
      expect(find.text('Escala de hoje: 08:00 às 17:00'), findsOneWidget);
      expect(find.text('Nenhum ponto registrado hoje.'), findsOneWidget);
      expect(find.text('Minha área'), findsOneWidget);
      expect(find.text('Cadastrada pela empresa'), findsOneWidget);
      expect(find.text('Ativar avisos'), findsOneWidget);
      await tapText(t, 'Registrar ponto');
      expect(find.text('Agora, tire sua foto').hitTestable(), findsOneWidget);
    });

    testWidgets('ordem obrigatória: localização → foto → Entrada/Saída → confirmar; só a confirmação grava', (t) async {
      final (_, server, location, camera, _) = await pumpReal(t);
      await tapNav(t, 'Registrar');
      expect(find.text('Agora, tire sua foto'), findsOneWidget);
      expect(find.text('Loja Centro · consulta deste registro'), findsOneWidget);
      expect(location.reads, 1);
      expect(camera.shots, 0, reason: 'a câmera só abre com o toque');

      await tapText(t, 'Tirar foto');
      expect(find.text('Confira sua foto'), findsOneWidget);
      expect(find.textContaining('Nenhum ponto foi salvo ainda.'), findsOneWidget);
      await tapText(t, 'Usar esta foto');
      expect(find.text('Qual registro deseja fazer?'), findsOneWidget);
      expect(find.text('Pela sequência de hoje, o próximo previsto é a entrada.'), findsOneWidget);
      await chooseKind(t, 'Entrada');
      expect(find.text('Confirmar entrada'), findsWidgets);
      expect(writes(server), isEmpty, reason: 'nada é gravado antes de confirmar');

      await press(t, 'Confirmar entrada');
      expect(find.text('Entrada registrada'), findsOneWidget);
      expect(find.text('Recebido pelo servidor'), findsWidgets);
      expect(server.punches.single['status'], 'confirmed');
      expect(server.punches.single['kind'], 'entry');
      expect(writes(server).map((r) => r.url.path), ['/v1/me/punches', '/v1/me/punches/p1/face']);
      expect((jsonDecode(writes(server).first.body) as Map)['location'], {'latitude': -23.4996, 'longitude': -46.6, 'accuracyM': 12, 'mock': false});

      await tapText(t, 'Voltar ao início');
      expect(find.textContaining('Entrada às'), findsOneWidget);
      await tapNav(t, 'Histórico');
      expect(find.text('Entrada registrada').hitTestable(), findsOneWidget);
    });

    testWidgets('saída: a pessoa escolhe e o servidor recebe o tipo escolhido', (t) async {
      final (_, server, _, _, _) = await pumpReal(t);
      await toConfirm(t, kind: 'Saída');
      await press(t, 'Confirmar saída');
      expect(find.text('Saída registrada'), findsOneWidget);
      expect(server.punches.single['kind'], 'exit');
    });

    testWidgets('alterar tipo de registro volta para a escolha', (t) async {
      await pumpReal(t);
      await toConfirm(t);
      await tapText(t, 'Alterar tipo de registro');
      expect(find.text('Qual registro deseja fazer?'), findsOneWidget);
    });

    testWidgets('fora da área: bloqueia câmera e registro; tentar de novo valida outra vez', (t) async {
      final (_, server, location, camera, _) = await pumpReal(t, setup: (_, l, _, _) {
        l.result = const LocationResult.ok(DeviceLocation(latitude: -23.49, longitude: -46.6, accuracyM: 30));
      });
      await tapNav(t, 'Registrar');
      expect(find.text('Não foi possível continuar'), findsOneWidget);
      expect(find.text('Você está fora da área'), findsOneWidget);
      expect(find.textContaining('Você está a 1,1 km de Loja Centro.'), findsOneWidget);
      expect(find.text('Tirar foto'), findsNothing);
      expect(find.text('Relatar um problema'), findsOneWidget);
      expect(camera.shots, 0);
      expect(writes(server), isEmpty);

      location.result = const LocationResult.ok(DeviceLocation(latitude: -23.4996, longitude: -46.6, accuracyM: 12));
      await tapText(t, 'Tentar novamente');
      expect(find.text('Agora, tire sua foto'), findsOneWidget);
      expect(location.reads, 2);
    });

    for (final (name, result, title) in [
      ('negada', const LocationResult.failed(LocationProblem.denied), 'Permita a localização'),
      ('bloqueada', const LocationResult.failed(LocationProblem.deniedForever), 'Permita a localização'),
      ('desligada', const LocationResult.failed(LocationProblem.serviceOff), 'Ligue a localização'),
      ('sem sinal', const LocationResult.failed(LocationProblem.timeout), 'Localização indisponível'),
      ('imprecisa', const LocationResult.ok(DeviceLocation(latitude: -23.4996, longitude: -46.6, accuracyM: 400)), 'Localização imprecisa'),
      ('sem precisão informada', const LocationResult.ok(DeviceLocation(latitude: -23.4996, longitude: -46.6)), 'Localização imprecisa'),
    ]) {
      testWidgets('localização $name: não avança para a foto e nada é enviado', (t) async {
        final (_, server, _, camera, _) = await pumpReal(t, setup: (_, l, _, _) => l.result = result);
        await tapNav(t, 'Registrar');
        expect(find.text(title), findsOneWidget);
        expect(find.text('Tirar foto'), findsNothing);
        expect(camera.shots, 0);
        expect(writes(server), isEmpty);
      });
    }

    testWidgets('sem área cadastrada: bloqueia sem nem ler o GPS', (t) async {
      final (_, server, location, _, _) = await pumpReal(t, setup: (s, _, _, _) => s.hasArea = false);
      expect(find.textContaining('ainda não cadastrou a área de trabalho'), findsWidgets);
      await tapNav(t, 'Registrar');
      expect(find.text('Área de trabalho não cadastrada'), findsOneWidget);
      expect(location.reads, 0);
      expect(writes(server), isEmpty);
    });

    testWidgets('relatar um problema abre a nova solicitação', (t) async {
      await pumpReal(t, setup: (_, l, _, _) => l.result = const LocationResult.failed(LocationProblem.denied));
      await tapNav(t, 'Registrar');
      await tapText(t, 'Relatar um problema');
      expect(find.text('Conte o que aconteceu.').hitTestable(), findsOneWidget);
    });

    testWidgets('foto sem rosto avisa; desistir da câmera não é erro; câmera indisponível bloqueia', (t) async {
      final (_, server, _, camera, _) = await pumpReal(t, setup: (_, _, c, _) => c.result = const SelfieResult.failed(SelfieProblem.noFace));
      await tapNav(t, 'Registrar');
      await tapText(t, 'Tirar foto');
      expect(find.textContaining('Não encontrei um rosto na foto'), findsOneWidget);
      expect(find.text('Usar esta foto'), findsNothing);

      camera.result = const SelfieResult.failed(SelfieProblem.cancelled);
      await tapText(t, 'Tirar foto');
      expect(find.textContaining('Não encontrei um rosto'), findsNothing);
      expect(find.text('A selfie não foi tirada.'), findsNothing);

      camera.result = const SelfieResult.failed(SelfieProblem.unavailable);
      await tapText(t, 'Tirar foto');
      expect(find.text('Câmera indisponível'), findsOneWidget);
      camera.result = SelfieResult.ok(tinyPng);
      await tapText(t, 'Tentar novamente');
      expect(find.text('Confira sua foto'), findsOneWidget);
      expect(writes(server), isEmpty);
    });

    testWidgets('câmera negada: explica, deixa tentar de novo e abre as configurações do app', (t) async {
      final (_, server, _, camera, _) = await pumpReal(t, setup: (_, _, c, _) => c.result = const SelfieResult.failed(SelfieProblem.cameraDenied, detail: 'picker:camera_access_denied'));
      await tapNav(t, 'Registrar');
      await tapText(t, 'Tirar foto');
      expect(find.text('Permita a câmera'), findsOneWidget);
      expect(find.textContaining('(código: picker:camera_access_denied)'), findsOneWidget);
      await tapText(t, 'Abrir configurações do app');
      expect(camera.settings, 1);
      camera.result = SelfieResult.ok(tinyPng);
      await tapText(t, 'Tentar novamente');
      expect(find.text('Confira sua foto'), findsOneWidget);
      expect(writes(server), isEmpty);
    });

    testWidgets('falha na checagem da foto não é confundida com câmera negada', (t) async {
      await pumpReal(t, setup: (_, _, c, _) => c.result = const SelfieResult.failed(SelfieProblem.checkFailed, detail: 'face:MlKitException'));
      await tapNav(t, 'Registrar');
      await tapText(t, 'Tirar foto');
      expect(find.text('Permita a câmera'), findsNothing);
      expect(find.textContaining('Não foi possível conferir a foto agora.'), findsOneWidget);
      expect(find.textContaining('(código: face:MlKitException)'), findsOneWidget);
    });

    testWidgets('localização bloqueada oferece abrir as configurações do app', (t) async {
      final (_, _, _, camera, _) = await pumpReal(t, setup: (_, l, _, _) => l.result = const LocationResult.failed(LocationProblem.deniedForever));
      await tapNav(t, 'Registrar');
      await tapText(t, 'Abrir configurações do app');
      expect(camera.settings, 1);
    });

    testWidgets('tirar outra foto abre a câmera de novo', (t) async {
      final (_, _, _, camera, _) = await pumpReal(t);
      await tapNav(t, 'Registrar');
      await tapText(t, 'Tirar foto');
      await tapText(t, 'Tirar outra foto');
      expect(camera.shots, 2);
      expect(find.text('Confira sua foto'), findsOneWidget);
    });

    testWidgets('validade: localização antiga volta à primeira etapa, sem abrir a câmera', (t) async {
      final (_, server, location, camera, _) = await pumpReal(t);
      await tapNav(t, 'Registrar');
      server.now = server.now.add(const Duration(minutes: 6));
      await tapText(t, 'Tirar foto');
      expect(find.text('A validação expirou'), findsOneWidget);
      expect(camera.shots, 0);
      await tapText(t, 'Tentar novamente');
      expect(find.text('Agora, tire sua foto'), findsOneWidget);
      expect(location.reads, 2);
    });

    testWidgets('validade também na confirmação: nada é gravado com evidência vencida', (t) async {
      final (_, server, _, _, _) = await pumpReal(t);
      await toConfirm(t);
      server.now = server.now.add(const Duration(minutes: 6));
      await press(t, 'Confirmar entrada');
      expect(find.text('A validação expirou'), findsOneWidget);
      expect(writes(server), isEmpty);
    });

    testWidgets('queda de rede ao enviar a foto: tentar de novo usa o MESMO ponto, sem duplicar', (t) async {
      final (_, server, _, _, _) = await pumpReal(t, setup: (s, _, _, _) => s.faceDrops = 1);
      await toConfirm(t);
      await press(t, 'Confirmar entrada');
      expect(find.textContaining('O ponto ainda não foi registrado.'), findsOneWidget);
      expect(find.text('Entrada registrada'), findsNothing);
      await tapText(t, 'Tentar de novo: confirmar entrada');
      expect(find.text('Entrada registrada'), findsOneWidget);
      expect(server.punches, hasLength(1));
      expect(writes(server).where((r) => r.url.path == '/v1/me/punches'), hasLength(1));
    });

    testWidgets('servidor recusa (ponto repetido em menos de um minuto): avisa e não registra', (t) async {
      final (_, server, _, _, _) = await pumpReal(t, setup: (s, _, _, _) => s.registerError = 'punch_too_soon');
      await toConfirm(t);
      await press(t, 'Confirmar entrada');
      expect(find.textContaining('Você acabou de registrar um ponto'), findsOneWidget);
      expect(server.punches, isEmpty);
    });

    testWidgets('servidor recusa a foto: volta para tirar outra', (t) async {
      await pumpReal(t, setup: (s, _, _, _) => s.faceError = 'invalid_selfie');
      await toConfirm(t);
      await press(t, 'Confirmar entrada');
      expect(find.text('Agora, tire sua foto'), findsOneWidget);
      expect(find.text('O servidor não aceitou a foto. Tire outra selfie.'), findsOneWidget);
    });

    testWidgets('sair de + Registrar descarta a sessão; voltar recomeça pela localização; cancelar volta ao início', (t) async {
      final (_, server, location, _, _) = await pumpReal(t);
      await tapNav(t, 'Registrar');
      await tapText(t, 'Tirar foto');
      await tapNav(t, 'Histórico');
      await tapNav(t, 'Registrar');
      expect(find.text('Agora, tire sua foto'), findsOneWidget, reason: 'a foto anterior não vale');
      expect(location.reads, 2);
      await tapText(t, 'Cancelar registro');
      expect(find.text('Bom dia, Ana.').hitTestable(), findsOneWidget);
      expect(writes(server), isEmpty);
    });

    testWidgets('avisos: só agenda depois de a pessoa ativar; sair apaga os avisos do aparelho', (t) async {
      final (s, _, _, _, reminders) = await pumpReal(t);
      expect(reminders.scheduled, isEmpty);
      await tapText(t, 'Ativar avisos');
      expect(find.textContaining('Avisos no horário da escala: ativados'), findsOneWidget);
      // 08:00 no servidor: a entrada de hoje já passou; ficam a saída de hoje e os próximos dias.
      expect(reminders.scheduled.first.kind, PunchKind.exit);
      expect(reminders.scheduled.map((r) => r.date).toSet(), containsAll(['2026-11-11', '2026-11-12', '2026-11-13', '2026-11-16', '2026-11-17']));
      expect(reminders.timeZone, 'America/Sao_Paulo');
      await s.signOut();
      await t.pumpAndSettle();
      expect(reminders.clears, 1);
      expect(reminders.scheduled, isEmpty);
    });

    testWidgets('permissão de avisos negada: continua oferecendo ativar', (t) async {
      final (_, _, _, _, reminders) = await pumpReal(t, setup: (_, _, _, r) => r.grant = false);
      await tapText(t, 'Ativar avisos');
      expect(find.text('Ativar avisos'), findsOneWidget);
      expect(reminders.scheduled, isEmpty);
    });

    testWidgets('conta sem vínculo: o início explica e o + Registrar bloqueia', (t) async {
      await pumpReal(t, setup: (s, _, _, _) => s.links = []);
      expect(find.textContaining('ainda não está ligada a um vínculo ativo'), findsOneWidget);
      await tapNav(t, 'Registrar');
      expect(find.text('Sem vínculo ativo'), findsOneWidget);
    });

    testWidgets('empresa desativada: sem atalho no início e o + Registrar bloqueia', (t) async {
      await pumpReal(t, setup: (s, _, _, _) => s.canPunch = false);
      expect(find.textContaining('A empresa está desativada no sistema'), findsOneWidget);
      await tapNav(t, 'Registrar');
      expect(find.text('Empresa desativada'), findsOneWidget);
    });

    testWidgets('falha ao carregar a jornada: o registro não valida; "Tentar de novo" recarrega', (t) async {
      final (_, server, _, _, _) = await pumpReal(t, setup: (s, _, _, _) => s.attendanceStatus = 500);
      expect(find.textContaining('O servidor não respondeu como esperado'), findsOneWidget);
      await tapNav(t, 'Registrar');
      expect(find.text('Sem conexão com o servidor'), findsOneWidget);
      server.attendanceStatus = 200;
      await tapNav(t, 'Início');
      await tapText(t, 'Tentar de novo');
      expect(find.text('Minha área'), findsOneWidget);
    });

    testWidgets('áreas reais: nome e raio, sem coordenadas', (t) async {
      await pumpReal(t);
      await tapText(t, 'Ver todas');
      expect(find.text('Minhas áreas'), findsOneWidget);
      expect(find.textContaining('a até 150 m do centro desta área'), findsOneWidget);
      expect(find.textContaining('-23.5'), findsNothing);
    });

    for (final dark in [false, true]) {
      testWidgets('capturas: início e etapas (${dark ? 'escuro' : 'claro'})', (t) async {
        final suffix = dark ? 'escuro' : 'claro';
        await pumpReal(t, dark: dark);
        await capture(t, 'ponto-1-inicio-$suffix');
        await tapNav(t, 'Registrar');
        await capture(t, 'ponto-2-foto-$suffix');
        await tapText(t, 'Tirar foto');
        await capture(t, 'ponto-3-conferir-$suffix');
        await tapText(t, 'Usar esta foto');
        await capture(t, 'ponto-4-tipo-$suffix');
        await chooseKind(t, 'Entrada');
        await capture(t, 'ponto-5-confirmar-$suffix');
        await press(t, 'Confirmar entrada');
        await capture(t, 'ponto-6-registrado-$suffix');
      });
    }
  });
}
