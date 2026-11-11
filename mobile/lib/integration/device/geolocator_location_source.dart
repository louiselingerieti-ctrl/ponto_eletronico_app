import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../features/punch/punch_models.dart';

/// Localização do aparelho pelo plugin geolocator.
///
/// Só "durante o uso do app": uma leitura, na hora em que a pessoa registra o
/// ponto. O app NÃO pede localização em segundo plano e não acompanha a
/// pessoa. Coordenadas não são guardadas no aparelho nem registradas em log.
class GeolocatorLocationSource implements LocationSource {
  const GeolocatorLocationSource({this.timeLimit = const Duration(seconds: 20)});
  final Duration timeLimit;

  @override
  Future<LocationResult> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return const LocationResult.failed(LocationProblem.serviceOff);
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return const LocationResult.failed(LocationProblem.denied);
      if (permission == LocationPermission.deniedForever) return const LocationResult.failed(LocationProblem.deniedForever);

      final p = await Geolocator.getCurrentPosition(locationSettings: LocationSettings(accuracy: LocationAccuracy.high, timeLimit: timeLimit));
      return LocationResult.ok(DeviceLocation(latitude: p.latitude, longitude: p.longitude, accuracyM: p.accuracy, mock: p.isMocked));
    } on TimeoutException {
      return const LocationResult.failed(LocationProblem.timeout);
    } on LocationServiceDisabledException {
      return const LocationResult.failed(LocationProblem.serviceOff);
    } on PermissionDeniedException {
      return const LocationResult.failed(LocationProblem.denied);
    } catch (_) {
      return const LocationResult.failed(LocationProblem.timeout);
    }
  }
}
