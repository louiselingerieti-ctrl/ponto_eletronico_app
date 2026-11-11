import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../features/punch/punch_models.dart';

/// Avisos LOCAIS no horário da escala: o celular vibra e mostra a mensagem
/// para registrar o ponto. São agendados no próprio aparelho, a partir da
/// escala recebida do servidor; nenhum servidor de push é usado.
///
/// O horário é "inexato" de propósito: o Android pode atrasar alguns minutos
/// para poupar bateria, e em troca o app não precisa da permissão especial de
/// alarmes exatos. O aviso é um lembrete; quem registra o ponto é a pessoa.
class LocalPunchReminders implements PunchReminders {
  LocalPunchReminders({FlutterLocalNotificationsPlugin? plugin}) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();
  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _ready;

  static const _channel = AndroidNotificationDetails(
    'ponto_horario',
    'Hora do ponto',
    channelDescription: 'Avisa no horário de entrada e de saída da sua escala.',
    importance: Importance.high,
    priority: Priority.high,
    enableVibration: true,
    category: AndroidNotificationCategory.reminder,
  );

  Future<void> _init() => _ready ??= () async {
        tzdata.initializeTimeZones();
        await _plugin.initialize(settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      }();

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> enabled() async {
    try {
      await _init();
      return await _android?.areNotificationsEnabled() ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> request() async {
    try {
      await _init();
      return await _android?.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> schedule(List<PunchReminder> reminders, {required String timeZone}) async {
    await _init();
    await _plugin.cancelAllPendingNotifications();
    final tz.Location location;
    try {
      location = tz.getLocation(timeZone);
    } catch (_) {
      return; // fuso desconhecido: melhor não avisar do que avisar na hora errada
    }
    final now = tz.TZDateTime.now(location);
    for (final r in reminders) {
      final when = tz.TZDateTime(
        location,
        int.parse(r.date.substring(0, 4)),
        int.parse(r.date.substring(5, 7)),
        int.parse(r.date.substring(8, 10)),
        int.parse(r.time.substring(0, 2)),
        int.parse(r.time.substring(3, 5)),
      );
      if (!when.isAfter(now)) continue;
      await _plugin.zonedSchedule(
        id: r.id,
        scheduledDate: when,
        notificationDetails: const NotificationDetails(android: _channel),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: r.title,
        body: r.body,
      );
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _init();
      await _plugin.cancelAll();
    } catch (_) {
      // sem avisos para apagar
    }
  }
}
