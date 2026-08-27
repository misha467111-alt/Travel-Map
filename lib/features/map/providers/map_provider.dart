import 'package:geolocator/geolocator.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'map_provider.g.dart';

@riverpod
Future<Position> currentPosition(Ref ref) async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    throw const LocationServiceDisabledException();
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied) {
    throw const PermissionDeniedException('Дозвіл на геолокацію відхилено.');
  }
  if (permission == LocationPermission.deniedForever) {
    throw const PermissionDeniedException(
      'Дозвіл на геолокацію заблоковано назавжди. Увімкніть його в налаштуваннях пристрою.',
    );
  }

  return Geolocator.getCurrentPosition(
    desiredAccuracy: LocationAccuracy.high,
  );
}
