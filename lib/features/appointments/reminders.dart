import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../services/notification_service.dart';
import '../../services/providers.dart';
import '../../shared/format.dart';
import 'day_schedule_provider.dart';

/// Termini prijavljenog korisnika za prozor danas → +2 dana — koriste se za
/// zakazivanje podsjetnika (da se ažurira status po završetku termina).
///
/// Za ne-admina server vraća samo NJEGOVE termine (ne šaljemo `employeeId` —
/// vidi napomenu o 403). Admin dobija svoje po svom `employeeId` (ako ga ima).
final myReminderAppointmentsProvider =
    FutureProvider.autoDispose<List<AppointmentResponse>>((ref) async {
  final api = ref.watch(apiServiceProvider);
  final auth = ref.watch(authControllerProvider);
  final now = DateTime.now();
  final from = DateTime(now.year, now.month, now.day);
  final to = from.add(const Duration(days: 3)); // danas + naredna 2 dana

  final employeeId = auth.isAdmin ? auth.employeeId : null;
  final page = await api.getAppointments(
    from: from.toUtc().toIso8601String(),
    to: to.toUtc().toIso8601String(),
    employeeId: employeeId,
    page: 0,
    size: 200,
    sort: 'startTime,asc',
  );
  return page.content;
});

/// „Tihi" widget koji drži podsjetnike usklađenim sa terminima. Omotava sadržaj
/// aplikacije (unutar AppShell-a). Radi samo na telefonu; drugdje je bez efekta.
class RemindersController extends ConsumerStatefulWidget {
  final Widget child;
  const RemindersController({super.key, required this.child});

  @override
  ConsumerState<RemindersController> createState() =>
      _RemindersControllerState();
}

class _RemindersControllerState extends ConsumerState<RemindersController>
    with WidgetsBindingObserver {
  bool _askedPermission = false;

  // Podsjetnici imaju smisla samo na pravom telefonu (Android/iOS).
  bool get _isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    if (!_isMobile) return;
    WidgetsBinding.instance.addObserver(this);
    // Poslije prvog kadra: inicijalizuj servis i (jednom) zatraži dozvolu.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await notificationService.init();
      if (!_askedPermission) {
        _askedPermission = true;
        await notificationService.requestPermission();
      }
    });
  }

  @override
  void dispose() {
    if (_isMobile) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Na povratak u aplikaciju osvježi termine (uhvati promjene sa servera / novi dan).
    if (_isMobile && state == AppLifecycleState.resumed) {
      ref.invalidate(myReminderAppointmentsProvider);
    }
  }

  /// Poništi sve pa zakaži podsjetnike za termine koji su još „zakazani".
  /// Time se već ažurirani (završen/otkazan/nije se pojavio) automatski preskaču.
  Future<void> _reconcile(List<AppointmentResponse> appts) async {
    await notificationService.cancelAll();
    for (final a in appts) {
      final id = a.id;
      // Kraj termina: iz endTime, ili izračunat iz početka + trajanja (server
      // ne vraća uvijek endTime). Bez ijednog → preskoči.
      final start = a.startTime?.toLocal();
      final end = a.endTime?.toLocal() ??
          (start != null && a.duration != null
              ? start.add(Duration(minutes: a.duration!))
              : null);
      if (id == null || end == null) continue;
      // Samo zakazani (ne već ažurirani) i ne pauze.
      if (a.status != null && a.status != AppointmentStatus.scheduled) continue;
      if (isBreakNote(a.note)) continue;

      final name = (a.customerName ?? '').trim();
      final who = name.isEmpty ? 'Termin' : name;
      final range =
          '${Format.time(a.startTime?.toLocal())}–${Format.time(end)}';

      await notificationService.scheduleStatusReminder(
        id: id,
        whenLocal: end.add(const Duration(minutes: 1)),
        title: 'Ažuriraj status termina',
        body: '$who ($range) je završen. Označi status.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Kad se lista termina (ponovo) učita, uskladi podsjetnike.
    if (_isMobile) {
      ref.listen<AsyncValue<List<AppointmentResponse>>>(
        myReminderAppointmentsProvider,
        (prev, next) => next.whenData(_reconcile),
      );
    }
    return widget.child;
  }
}
