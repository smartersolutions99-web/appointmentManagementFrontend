import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Lokalne notifikacije-podsjetnici — samo na telefonu (Android/iOS).
///
/// Na webu i desktopu su SVE operacije „no-op" (vidi [_supported]), pa je servis
/// bezbjedno pozivati bilo gdje. Koristi se za podsjetnik da se ažurira status
/// termina nakon što se termin završi.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  // Notifikacije šaljemo samo na pravim telefonima (Android/iOS).
  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static const String _channelId = 'appointment_status';
  static const String _channelName = 'Podsjetnici za status termina';
  static const String _channelDesc =
      'Podsjeća da ažuriraš status termina nakon završetka.';

  /// Inicijalizacija (jednom): timezone baza + kanal notifikacija.
  Future<void> init() async {
    if (!_supported || _ready) return;

    // Timezone (za tačno zakazivanje po lokalnom vremenu, uz ljetnje/zimsko).
    tzdata.initializeTimeZones();
    try {
      final tzInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
    } catch (_) {
      // Ako ne uspije, ostaje podrazumijevana zona — bolje išta nego pad.
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: darwin),
    );
    _ready = true;
  }

  /// Da li je servis uopšte aktivan (Android/iOS). Za dijagnostiku.
  bool get debugSupported => _supported;

  /// Da li su notifikacije trenutno uključene (Android). Za dijagnostiku.
  Future<bool?> areEnabled() async {
    if (!_supported) return false;
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return android?.areNotificationsEnabled();
  }

  /// Zatraži dozvolu za notifikacije (i tačne alarme na Androidu).
  /// Vraća da li je dozvola data (Android/iOS); `false` na nepodržanoj platformi.
  Future<bool> requestPermission() async {
    if (!_supported) return false;
    await init();
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission() ?? false;
      await android?.requestExactAlarmsPermission();
      return granted;
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(
              alert: true, badge: true, sound: true) ??
          false;
    }
    return false;
  }

  /// Zakaži podsjetnik za termin ([id] = id termina) u trenutku [whenLocal].
  Future<void> scheduleStatusReminder({
    required int id,
    required DateTime whenLocal,
    required String title,
    required String body,
  }) async {
    if (!_supported) return;
    await init();

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );

    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime.from(whenLocal, tz.local);
    // Ako je vrijeme već prošlo (termin se upravo završio), prikaži uskoro.
    if (!when.isAfter(now)) {
      when = now.add(const Duration(seconds: 5));
    }

    // Prvo probaj TAČAN alarm; ako nije dozvoljen (Android 12+), padni na približan.
    for (final mode in const [
      AndroidScheduleMode.exactAllowWhileIdle,
      AndroidScheduleMode.inexactAllowWhileIdle,
    ]) {
      try {
        await _plugin.zonedSchedule(
          id: _safeId(id),
          title: title,
          body: body,
          scheduledDate: when,
          notificationDetails: details,
          androidScheduleMode: mode,
        );
        return;
      } catch (_) {
        // Probaj sljedeći način zakazivanja.
      }
    }
  }

  /// Sažetak ZAKAZANIH (pending) notifikacija — za dijagnostiku (šta je stvarno
  /// u redu za okidanje).
  Future<List<String>> pendingSummary() async {
    if (!_supported) return const [];
    await init();
    final list = await _plugin.pendingNotificationRequests();
    return [for (final p in list) '#${p.id} ${p.title ?? ''}'];
  }

  /// Odmah prikaži notifikaciju — za test (provjera da dozvole/kanal rade).
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_supported) return;
    await init();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _plugin.show(
      id: _safeId(id),
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  /// Otkaži podsjetnik za dati termin (npr. kad se status ažurira).
  Future<void> cancel(int id) async {
    if (!_supported) return;
    await init();
    await _plugin.cancel(id: _safeId(id));
  }

  /// Otkaži sve podsjetnike (koristi se prije ponovnog usklađivanja).
  Future<void> cancelAll() async {
    if (!_supported) return;
    await init();
    await _plugin.cancelAll();
  }

  // ID notifikacije mora da stane u 32-bitni int (Android). Id termina mapiramo
  // u stabilan pozitivan 32-bitni broj (isti termin → isti id).
  int _safeId(int appointmentId) => appointmentId.abs() % 2147483647;
}

/// Kratica do jedine instance servisa.
final notificationService = NotificationService.instance;
