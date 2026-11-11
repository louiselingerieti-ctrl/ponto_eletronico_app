/// Configuração de presença de UM vínculo (`GET /v1/me/presence-config`,
/// rascunho `presenca-v1`). Validação estrita: campo desconhecido, tipo errado
/// ou valor fora da faixa recusa a configuração inteira.
library;

import 'package:meta/meta.dart';

enum AreaKind { establishment, externalSite, temporaryException }

@immutable
class PresenceArea {
  const PresenceArea({
    required this.areaId,
    required this.revision,
    required this.label,
    required this.kind,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.validFrom,
    this.validTo,
  });

  final String areaId;
  final int revision;
  final String label;
  final AreaKind kind;
  final double latitude;
  final double longitude;
  final int radiusMeters;
  final DateTime validFrom;
  final DateTime? validTo;

  bool isValidAt(DateTime t) =>
      !t.isBefore(validFrom) && (validTo == null || t.isBefore(validTo!));
}

@immutable
class PresenceConfig {
  const PresenceConfig({
    required this.employmentLinkId,
    required this.configRevision,
    required this.policyRevision,
    required this.serverTime,
    required this.validUntil,
    required this.areas,
    required this.maxFixAgeSeconds,
    required this.maxAccuracyMeters,
    required this.dwellSeconds,
    required this.manualAllowed,
    required this.manualReasonRequired,
    required this.manualLocationRequired,
    required this.maxEventAgeHours,
    required this.maxQueuedEvents,
  });

  final String employmentLinkId;
  final String configRevision;
  final String policyRevision;
  final DateTime serverTime;
  final DateTime validUntil;
  final List<PresenceArea> areas;
  final int maxFixAgeSeconds;
  final int maxAccuracyMeters;
  final int dwellSeconds;
  final bool manualAllowed;
  final bool manualReasonRequired;
  final bool manualLocationRequired;
  final int maxEventAgeHours;
  final int maxQueuedEvents;

  List<PresenceArea> areasValidAt(DateTime t) =>
      [for (final a in areas) if (a.isValidAt(t)) a];

  /// [expectedLinkId] é o vínculo PEDIDO; uma resposta de outro vínculo é
  /// recusada (o app não associa configuração a vínculo por conta própria).
  static PresenceConfig parse(Object? json, {required String expectedLinkId}) {
    final v = _V();
    final m = v.obj(json, 'config', const {
      'employmentLinkId', 'configRevision', 'policyRevision', 'serverTime',
      'validUntil', 'areas', 'detection', 'manualPunch', 'offline',
    });
    if (m == null) throw ConfigValidationError(v.errors);

    final link = v.str(m, 'employmentLinkId', max: 64);
    if (link != null && link != expectedLinkId) {
      v.errors.add('employmentLinkId diferente do vínculo solicitado');
    }
    final cfgRev = v.str(m, 'configRevision', max: 64);
    final polRev = v.str(m, 'policyRevision', max: 64);
    final serverTime = v.time(m, 'serverTime');
    final validUntil = v.time(m, 'validUntil');
    if (serverTime != null && validUntil != null && !validUntil.isAfter(serverTime)) {
      v.errors.add('validUntil deve ser posterior a serverTime');
    }

    final areas = <PresenceArea>[];
    final rawAreas = m['areas'];
    if (rawAreas is! List) {
      v.errors.add('areas ausente ou inválido');
    } else if (rawAreas.length > 20) {
      v.errors.add('areas acima de 20');
    } else {
      final seen = <String>{};
      for (var i = 0; i < rawAreas.length; i++) {
        final a = v.obj(rawAreas[i], 'areas[$i]', const {
          'areaId', 'revision', 'label', 'kind', 'center', 'radiusMeters',
          'validFrom', 'validTo',
        });
        if (a == null) continue;
        final id = v.str(a, 'areaId', max: 64);
        if (id != null && !seen.add(id)) v.errors.add('areaId repetido: $id');
        final rev = v.int_(a, 'revision', min: 1);
        final label = v.str(a, 'label', max: 200);
        final kind = v.enumOf(a, 'kind', const {
          'establishment': AreaKind.establishment,
          'external_site': AreaKind.externalSite,
          'temporary_exception': AreaKind.temporaryException,
        });
        final c = v.obj(a['center'], 'areas[$i].center', const {'latitude', 'longitude'});
        final lat = c == null ? null : v.num_(c, 'latitude', min: -90, max: 90);
        final lon = c == null ? null : v.num_(c, 'longitude', min: -180, max: 180);
        final radius = v.int_(a, 'radiusMeters', min: 50, max: 10000);
        final from = v.time(a, 'validFrom');
        final to = v.time(a, 'validTo', nullable: true);
        if (from != null && to != null && !to.isAfter(from)) {
          v.errors.add('areas[$i]: validTo deve ser posterior a validFrom');
        }
        if ([id, rev, label, kind, lat, lon, radius, from].contains(null)) continue;
        areas.add(PresenceArea(
          areaId: id!, revision: rev!, label: label!, kind: kind!,
          latitude: lat!, longitude: lon!, radiusMeters: radius!,
          validFrom: from!, validTo: to,
        ));
      }
    }

    final det = v.obj(m['detection'], 'detection',
        const {'maxFixAgeSeconds', 'maxAccuracyMeters', 'dwellSeconds'});
    final man = v.obj(m['manualPunch'], 'manualPunch',
        const {'allowed', 'reasonRequired', 'locationRequired'});
    final off = v.obj(m['offline'], 'offline', const {'maxEventAgeHours', 'maxQueuedEvents'});

    final maxFix = det == null ? null : v.int_(det, 'maxFixAgeSeconds', min: 1);
    final maxAcc = det == null ? null : v.int_(det, 'maxAccuracyMeters', min: 1);
    final dwell = det == null ? null : v.int_(det, 'dwellSeconds', min: 0);
    final mAllowed = man == null ? null : v.bool_(man, 'allowed');
    final mReason = man == null ? null : v.bool_(man, 'reasonRequired');
    final mLoc = man == null ? null : v.bool_(man, 'locationRequired');
    final maxAge = off == null ? null : v.int_(off, 'maxEventAgeHours', min: 1);
    final maxQ = off == null ? null : v.int_(off, 'maxQueuedEvents', min: 1);

    if (v.errors.isNotEmpty) throw ConfigValidationError(v.errors);
    return PresenceConfig(
      employmentLinkId: link!, configRevision: cfgRev!, policyRevision: polRev!,
      serverTime: serverTime!, validUntil: validUntil!, areas: List.unmodifiable(areas),
      maxFixAgeSeconds: maxFix!, maxAccuracyMeters: maxAcc!, dwellSeconds: dwell!,
      manualAllowed: mAllowed!, manualReasonRequired: mReason!,
      manualLocationRequired: mLoc!, maxEventAgeHours: maxAge!, maxQueuedEvents: maxQ!,
    );
  }
}

final class ConfigValidationError implements Exception {
  ConfigValidationError(List<String> errors) : errors = List.unmodifiable(errors);
  final List<String> errors;
  @override
  String toString() => 'ConfigValidationError(${errors.join('; ')})';
}

class _V {
  final errors = <String>[];

  Map<String, Object?>? obj(Object? raw, String where, Set<String> allowed) {
    if (raw is! Map) {
      errors.add('$where ausente ou não é objeto');
      return null;
    }
    final m = raw.cast<String, Object?>();
    for (final k in m.keys) {
      if (!allowed.contains(k)) errors.add('$where: campo desconhecido "$k"');
    }
    return m;
  }

  String? str(Map<String, Object?> m, String k, {required int max}) {
    final v = m[k];
    if (v is! String || v.isEmpty || v.length > max) {
      errors.add('$k inválido');
      return null;
    }
    return v;
  }

  int? int_(Map<String, Object?> m, String k, {int? min, int? max}) {
    final v = m[k];
    if (v is! int || (min != null && v < min) || (max != null && v > max)) {
      errors.add('$k inválido');
      return null;
    }
    return v;
  }

  double? num_(Map<String, Object?> m, String k, {required num min, required num max}) {
    final v = m[k];
    if (v is! num || v < min || v > max || v.isNaN) {
      errors.add('$k inválido');
      return null;
    }
    return v.toDouble();
  }

  bool? bool_(Map<String, Object?> m, String k) {
    final v = m[k];
    if (v is! bool) {
      errors.add('$k inválido');
      return null;
    }
    return v;
  }

  DateTime? time(Map<String, Object?> m, String k, {bool nullable = false}) {
    final v = m[k];
    if (v == null && nullable && m.containsKey(k)) return null;
    if (v == null && nullable) return null;
    // Exige fuso explícito (Z ou ±hh:mm): horário sem fuso é ambíguo.
    if (v is! String || !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(v)) {
      errors.add('$k inválido');
      return null;
    }
    final t = DateTime.tryParse(v);
    if (t == null) {
      errors.add('$k inválido');
      return null;
    }
    return t.toUtc();
  }

  T? enumOf<T>(Map<String, Object?> m, String k, Map<String, T> values) {
    final v = m[k];
    final r = v is String ? values[v] : null;
    if (r == null) errors.add('$k inválido');
    return r;
  }
}
