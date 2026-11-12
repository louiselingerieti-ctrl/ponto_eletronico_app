import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../features/punch/punch_models.dart';
import 'session_store.dart';

/// Ponto no backend REAL, com a mesma sessão por cookie do login.
///
/// Contrato (backend, módulo punches, migração 0010):
/// - GET  /v1/me/attendance                 → escala de 7 dias, áreas e pontos de hoje
/// - POST /v1/me/punches                    → ponto provisório com a localização
/// - POST /v1/me/punches/{id}/face          → a foto confirma o ponto
/// O app só chama as duas escritas na confirmação, uma em seguida da outra.
/// Todas levam `X-Tenant-Id`. As escritas levam `Origin` igual à origem da
/// API, que o servidor aceita para o app nativo.
///
/// Nunca registra (log) cookie, coordenadas, selfie ou corpo de resposta.
class BackendPunchGateway implements PunchGateway {
  BackendPunchGateway({required Uri baseUrl, required SessionStore store, http.Client? client, this.timeout = const Duration(seconds: 20)})
      : _base = baseUrl.replace(path: ''),
        // ignore: prefer_initializing_formals
        _store = store,
        _client = client ?? http.Client();

  final Uri _base;
  final SessionStore _store;
  final http.Client _client;
  final Duration timeout;

  Uri _u(String path) => _base.replace(path: path);

  Future<Map<String, String>> _headers(String tenantId, {bool write = false}) async {
    final cookie = await _store.read();
    if (cookie == null) throw const PunchException(PunchFailure.sessionExpired);
    return {
      'accept': 'application/json',
      'cookie': cookie,
      'x-tenant-id': tenantId,
      if (write) 'content-type': 'application/json',
      if (write) 'origin': _base.origin,
    };
  }

  Future<http.Response> _send(Future<http.Response> Function() call) async {
    try {
      return await call().timeout(timeout);
    } on TimeoutException {
      throw const PunchException(PunchFailure.network);
    } on http.ClientException {
      throw const PunchException(PunchFailure.network);
    }
  }

  @override
  Future<Attendance> attendance(String tenantId) async {
    final headers = await _headers(tenantId);
    final r = await _send(() => _client.get(_u('/v1/me/attendance'), headers: headers));
    if (r.statusCode != 200) throw PunchException(_failure(r));
    final j = _json(r);
    final links = j['links'];
    final serverTime = DateTime.tryParse('${j['serverTime']}');
    if (links is! List || serverTime == null || j['today'] is! String || j['timeZone'] is! String || j['faceWindowSeconds'] is! int) {
      throw const PunchException(PunchFailure.server);
    }
    return Attendance(
      serverTime: serverTime.toUtc(),
      today: j['today'] as String,
      timeZone: j['timeZone'] as String,
      faceWindowSeconds: j['faceWindowSeconds'] as int,
      links: [for (final raw in links) _link(raw)],
    );
  }

  @override
  Future<PunchRecord> register(String tenantId,
      {required String employmentLinkId, required String clientEventId, required PunchKind kind, required DeviceLocation? location}) async {
    final headers = await _headers(tenantId, write: true);
    final body = jsonEncode({
      'employmentLinkId': employmentLinkId,
      'clientEventId': clientEventId,
      'kind': kind.wire,
      'deviceTime': DateTime.now().toUtc().toIso8601String(),
      'location': location == null
          ? null
          : {
              'latitude': location.latitude,
              'longitude': location.longitude,
              if (location.accuracyM != null) 'accuracyM': location.accuracyM,
              'mock': location.mock,
            },
    });
    final r = await _send(() => _client.post(_u('/v1/me/punches'), headers: headers, body: body));
    if (r.statusCode != 201 && r.statusCode != 200) throw PunchException(_failure(r));
    return _punch(_json(r));
  }

  @override
  Future<PunchRecord> confirm(String tenantId, String punchId, Uint8List selfie) async {
    final headers = await _headers(tenantId, write: true);
    final body = jsonEncode({'dataBase64': base64Encode(selfie)});
    final r = await _send(() => _client.post(_u('/v1/me/punches/$punchId/face'), headers: headers, body: body));
    if (r.statusCode != 200) throw PunchException(_failure(r));
    return _punch(_json(r));
  }

  // ---------------------------------------------------------------- leitura

  static LinkAttendance _link(Object? raw) {
    if (raw is! Map) throw const PunchException(PunchFailure.server);
    final days = raw['days'];
    final punches = raw['punchesToday'];
    final areas = raw['areas'];
    if (raw['employmentLinkId'] is! String || raw['companyName'] is! String || raw['canPunch'] is! bool || days is! List || punches is! List || areas is! List) {
      throw const PunchException(PunchFailure.server);
    }
    return LinkAttendance(
      employmentLinkId: raw['employmentLinkId'] as String,
      companyName: raw['companyName'] as String,
      establishmentName: raw['establishmentName'] as String?,
      canPunch: raw['canPunch'] as bool,
      nextKind: PunchKind.parse(raw['nextKind']),
      days: [for (final d in days) _day(d)],
      punchesToday: [for (final p in punches) _punch(p)],
      areas: [for (final a in areas) _area(a)],
    );
  }

  static WorkArea _area(Object? raw) {
    if (raw is! Map || raw['id'] is! String || raw['name'] is! String || raw['latitude'] is! num || raw['longitude'] is! num || raw['radiusM'] is! num) {
      throw const PunchException(PunchFailure.server);
    }
    return WorkArea(
      id: raw['id'] as String,
      name: raw['name'] as String,
      latitude: (raw['latitude'] as num).toDouble(),
      longitude: (raw['longitude'] as num).toDouble(),
      radiusM: (raw['radiusM'] as num).round(),
    );
  }

  static DayPlan _day(Object? raw) {
    if (raw is! Map || raw['date'] is! String) throw const PunchException(PunchFailure.server);
    final kind = switch (raw['kind']) {
      'work' => DayKind.work,
      'off' => DayKind.off,
      'outside' => DayKind.outside,
      _ => DayKind.unassigned,
    };
    return DayPlan(
      date: raw['date'] as String,
      kind: kind,
      startsAt: raw['startsAt'] as String?,
      endsAt: raw['endsAt'] as String?,
      overnight: raw['overnight'] == true,
      scheduleName: raw['scheduleName'] as String?,
    );
  }

  static PunchRecord _punch(Object? raw) {
    if (raw is! Map || raw['id'] is! String) throw const PunchException(PunchFailure.server);
    final recordedAt = DateTime.tryParse('${raw['recordedAt']}');
    if (recordedAt == null) throw const PunchException(PunchFailure.server);
    final deadline = raw['faceDeadline'] is String ? DateTime.tryParse(raw['faceDeadline'] as String) : null;
    return PunchRecord(
      id: raw['id'] as String,
      kind: PunchKind.parse(raw['kind']),
      recordedAt: recordedAt.toUtc(),
      status: raw['status'] == 'confirmed' ? PunchStatus.confirmed : PunchStatus.pendingFace,
      verdict: switch (raw['locationStatus']) {
        'inside' => LocationVerdict.inside,
        'outside' => LocationVerdict.outside,
        'no_area' => LocationVerdict.noArea,
        _ => LocationVerdict.unavailable,
      },
      areaName: raw['areaName'] as String?,
      distanceM: raw['distanceM'] as int?,
      mockLocation: raw['mockLocation'] == true,
      faceDeadline: deadline?.toUtc(),
    );
  }

  PunchFailure _failure(http.Response r) {
    final code = _errorCode(r);
    return switch ((r.statusCode, code)) {
      (401, _) => PunchFailure.sessionExpired,
      (_, 'punch_too_soon') => PunchFailure.tooSoon,
      (_, 'punch_face_window_expired') => PunchFailure.windowExpired,
      (_, 'punch_already_confirmed') => PunchFailure.alreadyConfirmed,
      (_, 'invalid_selfie') || (_, 'selfie_too_large') => PunchFailure.invalidSelfie,
      (_, 'employment_link_not_found') || (_, 'time_punch_not_found') => PunchFailure.noLink,
      (_, 'company_inactive') => PunchFailure.companyInactive,
      _ => PunchFailure.server,
    };
  }

  static Map<String, Object?> _json(http.Response r) {
    try {
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (d is Map<String, Object?>) return d;
    } on FormatException {
      // cai no erro abaixo
    }
    throw const PunchException(PunchFailure.server);
  }

  static String? _errorCode(http.Response r) {
    try {
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (d is Map && d['error'] is Map) return (d['error'] as Map)['code'] as String?;
    } catch (_) {
      // sem corpo legível
    }
    return null;
  }
}
