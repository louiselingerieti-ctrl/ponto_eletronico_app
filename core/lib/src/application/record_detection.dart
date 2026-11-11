import '../domain/clock_quality.dart';
import '../domain/pending_policies.dart';
import '../domain/presence_event.dart';
import '../domain/queued_event.dart';
import 'config_lifecycle.dart';
import 'persistence.dart';
import 'ports.dart';

/// Dados que chegam do callback nativo de geofence. Vínculo, revisão e área
/// vêm do identificador com que o PRÓPRIO app registrou o geofence; o app
/// nunca associa uma transição a todos os vínculos da pessoa.
class GeofenceCallback {
  const GeofenceCallback({
    required this.employmentLinkId,
    required this.configRevision,
    required this.areaId,
    required this.areaRevision,
    required this.transition,
    required this.sample,
    this.observedAt,
    this.location,
  });

  final String employmentLinkId;
  final String configRevision;
  final String areaId;
  final int areaRevision;
  final Transition transition;
  final ClockSample sample;

  /// Só quando o SO forneceu a leitura que disparou a transição.
  final DateTime? observedAt;
  final LocationFix? location;
}

/// Contexto local gravado junto ao evento (fora do payload do contrato).
abstract final class CaptureFlag {
  static const configExpired = 'config_expired';
  static const linkRevoked = 'link_revoked';
  static const afterAuthLoss = 'after_auth_loss';
  static const configNotConfirmed = 'config_not_confirmed';
  static const configSuperseded = 'config_superseded';
}

enum RefusalReason { unknownLink, unknownConfigRevision, areaNotInConfig, pendingDecision }

sealed class RecordOutcome {
  const RecordOutcome();
}

final class Recorded extends RecordOutcome {
  const Recorded(this.event, this.flags);
  final QueuedEvent event;
  final Set<String> flags;
}

final class Refused extends RecordOutcome {
  const Refused(this.reason, {this.decision});
  final RefusalReason reason;

  /// Preenchido quando a recusa veio de uma decisão pendente configurada
  /// como [PendingCaseHandling.refuse].
  final String? decision;
}

class RecordDetection {
  RecordDetection({
    required this.store,
    required this.stamper,
    required this.policies,
    required this.appVersion,
  });

  final LocalPersistence store;
  final ClockStamper stamper;
  final PendingPolicies policies;
  final String appVersion;

  RecordOutcome call(GeofenceCallback cb) {
    return store.tx(() {
      final configs = store.configs;
      if (configs.current(cb.employmentLinkId) == null) {
        return const Refused(RefusalReason.unknownLink);
      }
      final cfg = configs.byRevision(cb.employmentLinkId, cb.configRevision);
      if (cfg == null) return const Refused(RefusalReason.unknownConfigRevision);
      final inConfig = cfg.config.areas.any(
          (a) => a.areaId == cb.areaId && a.revision == cb.areaRevision);
      if (!inConfig) return const Refused(RefusalReason.areaNotInConfig);

      final flags = <String>{};
      if (cfg.supersededAt != null) flags.add(CaptureFlag.configSuperseded);
      if (cfg.stage != ApplyStage.applied) flags.add(CaptureFlag.configNotConfirmed);

      Refused? check(bool hit, PendingCaseHandling h, String decision, String flag) {
        if (!hit) return null;
        if (h == PendingCaseHandling.refuse) {
          return Refused(RefusalReason.pendingDecision, decision: decision);
        }
        flags.add(flag);
        return null;
      }

      final halt = store.queue.deliveryHalt();
      final refusal = check(
            configs.activeRevocation(cb.employmentLinkId) != null,
            policies.revokedLink, PendingDecision.revokedLink, CaptureFlag.linkRevoked) ??
          check(!cb.sample.wall.isBefore(cfg.config.validUntil),
              policies.expiredConfig, PendingDecision.expiredConfig,
              CaptureFlag.configExpired) ??
          check(
              halt != null &&
                  (halt.reason == DeliveryHaltReason.unauthenticated ||
                      halt.reason == DeliveryHaltReason.forbidden),
              policies.afterAuthLoss, PendingDecision.afterAuthLoss,
              CaptureFlag.afterAuthLoss);
      if (refusal != null) return refusal;

      final ev = store.queue.append(
        AreaTransitionDraft(
          employmentLinkId: cb.employmentLinkId,
          configRevision: cb.configRevision,
          appVersion: appVersion,
          clock: stamper.stamp(cb.sample),
          areaId: cb.areaId,
          areaRevision: cb.areaRevision,
          transition: cb.transition,
          observedAt: cb.observedAt,
          location: cb.location,
        ),
        now: cb.sample.wall,
        captureFlags: flags,
      );
      return Recorded(ev, Set.unmodifiable(flags));
    });
  }
}
