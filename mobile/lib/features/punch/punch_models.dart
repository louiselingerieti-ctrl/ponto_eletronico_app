import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;

/// Ponto REAL pelo app. Na tela (+ Registrar) a ordem é: validar a
/// localização atual → tirar a foto → escolher Entrada/Saída → confirmar.
/// Só na confirmação o app fala com o servidor, em duas chamadas seguidas:
///  1. POST /v1/me/punches: cria o ponto provisório com a localização;
///  2. POST /v1/me/punches/{id}/face: a foto confirma o ponto.
/// Sem localização validada dentro de uma área não há foto nem ponto. O
/// horário oficial é o do servidor.
enum PunchKind {
  entry('entrada', 'Entrada'),
  exit('saída', 'Saída');

  const PunchKind(this.lower, this.label);
  final String lower;
  final String label;
  String get wire => name;
  static PunchKind parse(Object? v) => v == 'exit' ? PunchKind.exit : PunchKind.entry;
}

enum PunchStatus { pendingFace, confirmed }

/// Como o servidor avaliou a localização do ponto.
enum LocationVerdict { inside, outside, noArea, unavailable }

/// O que a escala prevê para um dia.
enum DayKind { work, off, unassigned, outside }

@immutable
class DayPlan {
  const DayPlan({required this.date, required this.kind, this.startsAt, this.endsAt, this.overnight = false, this.scheduleName});

  /// Dia civil AAAA-MM-DD no fuso da operação.
  final String date;
  final DayKind kind;

  /// HH:MM; null fora de dia trabalhado.
  final String? startsAt;
  final String? endsAt;

  /// A saída cai no dia seguinte.
  final bool overnight;
  final String? scheduleName;

  String get summary => switch (kind) {
        DayKind.work => '$startsAt às $endsAt${overnight ? ' (do dia seguinte)' : ''}',
        DayKind.off => 'Folga',
        DayKind.unassigned => 'Sem escala definida',
        DayKind.outside => 'Fora do período do vínculo',
      };
}

@immutable
class PunchRecord {
  const PunchRecord({
    required this.id,
    required this.kind,
    required this.recordedAt,
    required this.status,
    required this.verdict,
    this.areaName,
    this.distanceM,
    this.mockLocation = false,
    this.faceDeadline,
  });

  final String id;
  final PunchKind kind;

  /// Horário oficial (do servidor), em UTC.
  final DateTime recordedAt;
  final PunchStatus status;
  final LocationVerdict verdict;
  final String? areaName;
  final int? distanceM;
  final bool mockLocation;

  /// Só no ponto provisório: até quando a selfie ainda é aceita (UTC).
  final DateTime? faceDeadline;

  bool get confirmed => status == PunchStatus.confirmed;

  /// O que dizer à pessoa sobre onde o ponto foi registrado.
  String get locationText => switch (verdict) {
        LocationVerdict.inside => 'Dentro de ${areaName ?? 'uma área de trabalho'}',
        LocationVerdict.outside =>
          'Fora da área de trabalho${distanceM == null ? '' : ' (a ${_distance(distanceM!)} de ${areaName ?? 'a mais próxima'})'}',
        LocationVerdict.noArea => 'A empresa ainda não cadastrou a área de trabalho',
        LocationVerdict.unavailable => 'Sem localização do aparelho',
      };

  /// Fora do esperado: o ponto vale, mas o RH vai avaliar.
  bool get flagged => verdict == LocationVerdict.outside || verdict == LocationVerdict.unavailable || mockLocation;

  static String _distance(int m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km' : '$m m';
}

/// Área de trabalho do vínculo, como o servidor informa (centro e raio).
@immutable
class WorkArea {
  const WorkArea({required this.id, required this.name, required this.latitude, required this.longitude, required this.radiusM});
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final int radiusM;
}

@immutable
class LinkAttendance {
  const LinkAttendance({
    required this.employmentLinkId,
    required this.companyName,
    required this.canPunch,
    required this.nextKind,
    required this.days,
    required this.punchesToday,
    required this.areas,
    this.establishmentName,
  });

  final String employmentLinkId;
  final String companyName;
  final String? establishmentName;

  /// false quando a empresa está desativada.
  final bool canPunch;
  final PunchKind nextKind;

  /// Hoje e os 6 dias seguintes.
  final List<DayPlan> days;
  final List<PunchRecord> punchesToday;

  /// Áreas autorizadas a este vínculo (só as dele, vindas do servidor).
  final List<WorkArea> areas;
  bool get hasArea => areas.isNotEmpty;

  DayPlan? get today => days.isEmpty ? null : days.first;

}

@immutable
class Attendance {
  const Attendance({required this.serverTime, required this.today, required this.timeZone, required this.faceWindowSeconds, required this.links});
  final DateTime serverTime;
  final String today;
  final String timeZone;
  final int faceWindowSeconds;
  final List<LinkAttendance> links;
}

@immutable
class DeviceLocation {
  const DeviceLocation({required this.latitude, required this.longitude, this.accuracyM, this.mock = false});
  final double latitude;
  final double longitude;
  final double? accuracyM;

  /// O sistema sinalizou localização simulada (app de GPS falso).
  final bool mock;
}

/// Por que o aparelho não entregou a localização. Sem localização validada
/// não há registro de ponto.
enum LocationProblem {
  denied('Você não permitiu o acesso à localização.'),
  deniedForever('O acesso à localização está bloqueado nas configurações do aparelho.'),
  serviceOff('A localização do aparelho está desligada.'),
  timeout('O aparelho não conseguiu obter a localização a tempo.');

  const LocationProblem(this.message);
  final String message;
}

@immutable
class LocationResult {
  const LocationResult.ok(DeviceLocation this.location) : problem = null;
  const LocationResult.failed(LocationProblem this.problem) : location = null;
  final DeviceLocation? location;
  final LocationProblem? problem;
}

/// Resultado da câmera. A checagem de rosto é feita no aparelho e só confere
/// que há UM rosto na foto; ela não identifica a pessoa.
enum SelfieProblem {
  cancelled('A selfie não foi tirada.'),
  noFace('Não encontrei um rosto na foto. Fique de frente para a câmera, em um lugar iluminado, e tente de novo.'),
  manyFaces('Há mais de um rosto na foto. A selfie precisa ser só sua.'),
  tooLarge('A foto ficou grande demais para enviar. Tente de novo.'),
  unavailable('Não foi possível usar a câmera agora.');

  const SelfieProblem(this.message);
  final String message;
}

@immutable
class SelfieResult {
  const SelfieResult.ok(Uint8List this.bytes) : problem = null;
  const SelfieResult.failed(SelfieProblem this.problem) : bytes = null;
  final Uint8List? bytes;
  final SelfieProblem? problem;
}

/// Falhas ao falar com o servidor, já traduzidas para a tela.
enum PunchFailure {
  network('Sem conexão com o servidor. Verifique a internet e tente de novo.'),
  sessionExpired('Sua sessão terminou. Entre novamente.'),
  tooSoon('Você acabou de registrar um ponto. Aguarde um minuto para registrar outro.'),
  windowExpired('O tempo para a selfie acabou. Registre o ponto de novo.'),
  alreadyConfirmed('Este ponto já estava confirmado.'),
  invalidSelfie('O servidor não aceitou a foto. Tire outra selfie.'),
  noLink('Sua conta não está ligada a um vínculo ativo. Procure o RH.'),
  companyInactive('A empresa está desativada no sistema. Procure o RH.'),
  server('O servidor não respondeu como esperado. Tente de novo em instantes.');

  const PunchFailure(this.message);
  final String message;
}

final class PunchException implements Exception {
  const PunchException(this.failure);
  final PunchFailure failure;
  @override
  String toString() => 'PunchException(${failure.name})';
}

/// Porta do servidor (implementação real em lib/integration/backend).
abstract interface class PunchGateway {
  Future<Attendance> attendance(String tenantId);

  /// Etapa 1. [clientEventId] torna o envio repetível sem duplicar o ponto.
  Future<PunchRecord> register(String tenantId,
      {required String employmentLinkId, required String clientEventId, required PunchKind kind, required DeviceLocation? location});

  /// Etapa 2: a selfie (JPEG) confirma o ponto.
  Future<PunchRecord> confirm(String tenantId, String punchId, Uint8List selfie);
}

/// Porta da localização do aparelho (lib/integration/device).
abstract interface class LocationSource {
  /// Pede a permissão se preciso e lê a posição atual, uma vez.
  Future<LocationResult> current();
}

/// Porta da câmera frontal + checagem de rosto no aparelho.
abstract interface class SelfieCamera {
  Future<SelfieResult> capture();
}

/// Um aviso agendado para o horário da escala.
@immutable
class PunchReminder {
  const PunchReminder({required this.id, required this.date, required this.time, required this.kind, required this.companyName});
  final int id;

  /// Dia civil AAAA-MM-DD e hora HH:MM no fuso da operação.
  final String date;
  final String time;
  final PunchKind kind;
  final String companyName;

  String get title => 'Hora de registrar a ${kind.lower}';
  String get body => 'Abra o app e toque em + Registrar: localização e foto. ($companyName)';
}

/// Porta dos avisos locais (vibram e aparecem no horário da escala).
abstract interface class PunchReminders {
  /// Os avisos já podem ser mostrados? Não pede nada à pessoa.
  Future<bool> enabled();

  /// Pede a permissão de notificações (só em resposta a um toque).
  Future<bool> request();

  /// Substitui todos os avisos agendados por estes.
  Future<void> schedule(List<PunchReminder> reminders, {required String timeZone});
  Future<void> clear();
}

/// Avisos dos próximos dias: entrada e saída de cada dia trabalhado que ainda
/// não passou. O ponto de hoje que já foi CONFIRMADO não gera aviso.
List<PunchReminder> buildReminders(Attendance a, {required String nowDate, required String nowTime}) {
  final out = <PunchReminder>[];
  var id = 1000;
  for (final link in a.links.where((l) => l.canPunch)) {
    final done = {for (final p in link.punchesToday.where((p) => p.confirmed)) p.kind};
    for (final day in link.days.where((d) => d.kind == DayKind.work && d.startsAt != null && d.endsAt != null)) {
      final exitDate = day.overnight ? _nextDay(day.date) : day.date;
      final slots = [(PunchKind.entry, day.date, day.startsAt!), (PunchKind.exit, exitDate, day.endsAt!)];
      for (final (kind, date, time) in slots) {
        id++;
        final past = date.compareTo(nowDate) < 0 || (date == nowDate && time.compareTo(nowTime) <= 0);
        if (past || (day.date == a.today && done.contains(kind))) continue;
        out.add(PunchReminder(id: id, date: date, time: time, kind: kind, companyName: link.companyName));
      }
    }
  }
  return out;
}

String _nextDay(String date) {
  final d = DateTime.utc(int.parse(date.substring(0, 4)), int.parse(date.substring(5, 7)), int.parse(date.substring(8, 10)) + 1);
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
