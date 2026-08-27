import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;

class DirectionsService {
  static double calculateDistance(gm.LatLng p1, gm.LatLng p2) {
    const p = 0.017453292519943295;
    final c = math.cos;
    final a = 0.5 -
        c((p2.latitude - p1.latitude) * p) / 2 +
        c(p1.latitude * p) *
            c(p2.latitude * p) *
            (1 - c((p2.longitude - p1.longitude) * p)) /
            2;
    return 12742 * math.asin(math.sqrt(a));
  }
}
