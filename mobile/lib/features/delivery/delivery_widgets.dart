import '../../demo/demo_backend.dart';
import '../../shared/format/dates_pt.dart';
import '../../shared/icons/lucide.dart';
import '../../shared/widgets/cdf_widgets.dart';

/// Linha de detecção com o estado de ENTREGA (não de jornada).
EventRow detectionRow(DetectionView d) => EventRow(
      icon: d.isEntry ? Lucide.logIn : Lucide.logOut,
      title: d.title,
      area: d.area,
      time: DatesPt.hm(d.detectedAt),
      badge: StatusBadge(
        d.delivery.label,
        tone: d.delivery.ok ? BadgeTone.ok : BadgeTone.pending,
        small: true,
      ),
    );

String pendingText(int n) => n == 1 ? '1 evento' : '$n eventos';
