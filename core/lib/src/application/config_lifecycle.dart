import 'dart:convert';

import '../domain/clock_quality.dart';
import '../domain/pending_policies.dart';
import '../domain/presence_config.dart';
import '../domain/presence_event.dart';
import '../domain/queued_event.dart';
import 'persistence.dart';

/// Etapa 1: RECEBIDA. Só em memória; ainda não sobrevive a reinício.
class ConfigReceived {
  const ConfigReceived._(this.config, this.canonicalJson, this.receivedAt, this.reference);
  final PresenceConfig config;
  final String canonicalJson;
  final DateTime receivedAt;
  final ServerTimeReference? reference;
}

sealed class PersistResult {
  const PersistResult();
}

/// Etapa 2: PERSISTIDA (commit na base cifrada). Ainda não aplicada.
final class ConfigPersisted extends PersistResult {
  const ConfigPersisted(this.stored);
  final StoredConfig stored;
}

final class ConfigUnchanged extends PersistResult {
  const ConfigUnchanged(this.stored);
  final StoredConfig stored;
}

/// Resposta mais antiga (por `serverTime`) que a atual: ignorada.
final class ConfigStale extends PersistResult {
  const ConfigStale(this.currentRevision);
  final String currentRevision;
}

/// Mesma revisão com outro conteúdo: recusada; a gravada é preservada.
final class ConfigRevisionConflict extends PersistResult {
  const ConfigRevisionConflict(this.revision);
  final String revision;
}

final class ConfigRefusedRevoked extends PersistResult {
  const ConfigRefusedRevoked(this.revocation);
  final Revocation revocation;
}

sealed class ApplyResult {
  const ApplyResult();
}

/// Etapa 3: APLICADA — a camada nativa confirmou o registro de TODAS as
/// áreas vigentes desta revisão.
final class ConfigApplied extends ApplyResult {
  const ConfigApplied(this.stored, this.event);
  final StoredConfig stored;
  final QueuedEvent event;
}

final class ApplyAlreadyConfirmed extends ApplyResult {
  const ApplyAlreadyConfirmed(this.stored);
  final StoredConfig stored;
}

/// Registro parcial, com áreas a mais ou falha informada pela plataforma.
final class ApplyFailed extends ApplyResult {
  const ApplyFailed(this.stored, this.event, {this.missing = const {}, this.unexpected = const {}});
  final StoredConfig stored;
  final QueuedEvent event;
  final Set<String> missing;
  final Set<String> unexpected;
}

/// A revisão não é a atual (ou não existe): nada muda.
final class ApplyNotCurrent extends ApplyResult {
  const ApplyNotCurrent(this.revision);
  final String revision;
}

enum ConfigStatus { none, persisted, applied, applyFailed }

class ConfigAssessment {
  const ConfigAssessment({
    required this.status,
    required this.expired,
    this.current,
    this.revocation,
    this.pendingDecisions = const [],
  });

  final ConfigStatus status;
  final StoredConfig? current;

  /// `validUntil` ultrapassado segundo o relógio informado (que pode estar
  /// errado; ver a qualidade do relógio).
  final bool expired;
  final Revocation? revocation;

  /// Decisões operacionais em aberto que afetam este vínculo agora.
  final List<String> pendingDecisions;
}

/// Ciclo de vida da configuração: recebida → persistida → aplicada,
/// com substituição, vencimento e revogação.
class ConfigLifecycle {
  ConfigLifecycle({
    required this.store,
    required this.stamper,
    required this.appVersion,
  });

  final LocalPersistence store;
  final ClockStamper stamper;
  final String appVersion;

  ConfigRepository get _configs => store.configs;

  /// Valida a resposta. Não grava nada. Lança [ConfigValidationError] ou
  /// [FormatException].
  ConfigReceived receive(
    String rawJson, {
    required String expectedLinkId,
    required DateTime receivedAt,
    ServerTimeReference? reference,
  }) {
    final decoded = jsonDecode(rawJson);
    final cfg = PresenceConfig.parse(decoded, expectedLinkId: expectedLinkId);
    return ConfigReceived._(cfg, _canonical(decoded), receivedAt, reference);
  }

  PersistResult persist(ConfigReceived r, {required DateTime now}) {
    final link = r.config.employmentLinkId;
    return store.tx(() {
      final rev = _configs.activeRevocation(link);
      if (rev != null) return ConfigRefusedRevoked(rev);

      final same = _configs.byRevision(link, r.config.configRevision);
      final cur = _configs.current(link);
      if (same != null) {
        if (same.rawJson != r.canonicalJson) {
          return ConfigRevisionConflict(r.config.configRevision);
        }
        // Reentrega de uma revisão já substituída não volta a ser a atual.
        return same.supersededAt == null
            ? ConfigUnchanged(same)
            : ConfigStale(cur!.config.configRevision);
      }
      if (cur != null && r.config.serverTime.isBefore(cur.config.serverTime)) {
        return ConfigStale(cur.config.configRevision);
      }
      _configs.insertCurrent(r.config,
          rawJson: r.canonicalJson, receivedAt: r.receivedAt, persistedAt: now,
          reference: r.reference);
      return ConfigPersisted(_configs.current(link)!);
    });
  }

  /// A plataforma confirma quais áreas (por `areaId`) ficaram registradas.
  /// Confirmação e evento `config_applied` no MESMO commit.
  ApplyResult confirmApplied(
    String link,
    String revision, {
    required Set<String> registeredAreaIds,
    required ClockSample sample,
  }) {
    return store.tx(() {
      final cur = _configs.current(link);
      if (cur == null || cur.config.configRevision != revision) {
        return ApplyNotCurrent(revision);
      }
      if (cur.stage == ApplyStage.applied) return ApplyAlreadyConfirmed(cur);

      final expected = {for (final a in cur.config.areasValidAt(sample.wall)) a.areaId};
      final missing = expected.difference(registeredAreaIds);
      final unexpected = registeredAreaIds.difference(expected);
      if (missing.isNotEmpty || unexpected.isNotEmpty) {
        return _fail(cur, sample,
            'registro divergente: faltam ${missing.length}, sobram ${unexpected.length}',
            missing: missing, unexpected: unexpected);
      }
      final ev = store.queue.append(
          _status(cur, DetectionStatus.configApplied, sample, null),
          now: sample.wall);
      _configs.setApplyResult(link, revision,
          stage: ApplyStage.applied, at: sample.wall, eventId: ev.eventId);
      return ConfigApplied(_configs.current(link)!, ev);
    });
  }

  /// A plataforma informou falha ao registrar os geofences.
  ApplyResult reportApplyFailure(
    String link,
    String revision, {
    required String detail,
    required ClockSample sample,
  }) {
    return store.tx(() {
      final cur = _configs.current(link);
      if (cur == null || cur.config.configRevision != revision) {
        return ApplyNotCurrent(revision);
      }
      return _fail(cur, sample, detail);
    });
  }

  ApplyFailed _fail(StoredConfig cur, ClockSample sample, String detail,
      {Set<String> missing = const {}, Set<String> unexpected = const {}}) {
    final d = detail.length > 200 ? detail.substring(0, 200) : detail;
    final ev = store.queue.append(
        _status(cur, DetectionStatus.geofenceRegistrationFailed, sample, d),
        now: sample.wall);
    _configs.setApplyResult(cur.config.employmentLinkId, cur.config.configRevision,
        stage: ApplyStage.applyFailed, at: sample.wall, detail: d, eventId: ev.eventId);
    return ApplyFailed(_configs.current(cur.config.employmentLinkId)!, ev,
        missing: missing, unexpected: unexpected);
  }

  ConfigAssessment assess(String link, {required DateTime now}) {
    final cur = _configs.current(link);
    final rev = _configs.activeRevocation(link);
    final expired = cur != null && !now.isBefore(cur.config.validUntil);
    return ConfigAssessment(
      status: switch (cur?.stage) {
        null => ConfigStatus.none,
        ApplyStage.persisted => ConfigStatus.persisted,
        ApplyStage.applied => ConfigStatus.applied,
        ApplyStage.applyFailed => ConfigStatus.applyFailed,
      },
      current: cur,
      expired: expired,
      revocation: rev,
      pendingDecisions: [
        if (expired) PendingDecision.expiredConfig,
        if (rev != null) PendingDecision.revokedLink,
      ],
    );
  }

  /// Registra o FATO do vencimento (evento `config_expired`), uma vez por
  /// revisão. Não decide o que fazer depois (D-CFG-1).
  QueuedEvent? noteExpiry(String link, {required ClockSample sample}) {
    return store.tx(() {
      final cur = _configs.current(link);
      if (cur == null || sample.wall.isBefore(cur.config.validUntil)) return null;
      if (cur.expiredEventId != null) return null;
      final ev = store.queue.append(
          _status(cur, DetectionStatus.configExpired, sample, null),
          now: sample.wall);
      _configs.setExpiredEvent(link, cur.config.configRevision, ev.eventId);
      return ev;
    });
  }

  /// Revogação informada pelo servidor (vínculo `suspended`/`ended`,
  /// `presenceEnabled: false`, 403/404 na configuração). O que o app faz com
  /// detecções depois disso é D-LINK-1.
  void revoke(String link, {required String reason, required DateTime at}) =>
      _configs.revoke(link, reason: reason, at: at);

  void liftRevocation(String link, {required DateTime at}) =>
      _configs.liftRevocation(link, at: at);

  DetectionStatusDraft _status(
          StoredConfig cur, DetectionStatus s, ClockSample sample, String? detail) =>
      DetectionStatusDraft(
        employmentLinkId: cur.config.employmentLinkId,
        configRevision: cur.config.configRevision,
        appVersion: appVersion,
        clock: stamper.stamp(sample),
        status: s,
        detail: detail,
      );

  static String _canonical(Object? v) {
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      return '{${keys.map((k) => '${jsonEncode(k)}:${_canonical(v[k])}').join(',')}}';
    }
    if (v is List) return '[${v.map(_canonical).join(',')}]';
    return jsonEncode(v);
  }
}

/// Carimba o relógio com a referência mais recente gravada.
class ClockStamper {
  ClockStamper({
    required this.configs,
    required this.policy,
    required this.timeZone,
  });

  final ConfigRepository configs;
  final ClockQualityPolicy policy;

  /// Fuso IANA informado pela plataforma.
  final String Function() timeZone;

  ClockAssessment assess(ClockSample s) =>
      assessClock(s, configs.latestClockReference(), policy);

  DeviceClock stamp(ClockSample s) =>
      stampDeviceClock(s, assess(s), timeZone: timeZone());
}
