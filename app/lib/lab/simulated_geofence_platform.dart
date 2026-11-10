import 'package:presenca_core/presenca_lab.dart';

/// ================================================================
///  PLATAFORMA DE GEOFENCE SIMULADA — não registra nada no sistema.
/// ================================================================
/// Não pede localização, não usa a API de geolocalização do navegador e não
/// detecta nada sozinha. Só guarda quais áreas "estariam" registradas e
/// monta o callback quando o laboratório pede uma transição sintética.
class SimulatedGeofencePlatform {
  final Map<String, _Registration> _registered = {};

  /// "Registra" as áreas vigentes e devolve os `areaId` aceitos.
  Set<String> register(PresenceConfig config, DateTime at) {
    _registered.clear();
    for (final a in config.areasValidAt(at)) {
      _registered[a.areaId] = _Registration(
          config.employmentLinkId, config.configRevision, a.areaId, a.revision);
    }
    return _registered.keys.toSet();
  }

  bool get hasRegistrations => _registered.isNotEmpty;

  /// Callback sintético. Sem leitura de localização: `observedAt` e
  /// `location` ficam ausentes (a plataforma simulada não os fornece), e o
  /// relógio não tem monotônico nem boot (o navegador não os oferece).
  GeofenceCallback? syntheticTransition(String areaId, Transition t, DateTime wall) {
    final r = _registered[areaId];
    if (r == null) return null;
    return GeofenceCallback(
      employmentLinkId: r.linkId,
      configRevision: r.configRevision,
      areaId: r.areaId,
      areaRevision: r.areaRevision,
      transition: t,
      sample: ClockSample(wall: wall),
    );
  }
}

class _Registration {
  const _Registration(this.linkId, this.configRevision, this.areaId, this.areaRevision);
  final String linkId;
  final String configRevision;
  final String areaId;
  final int areaRevision;
}
