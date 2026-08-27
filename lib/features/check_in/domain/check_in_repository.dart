class CheckInResult {
  const CheckInResult({required this.id, required this.xpAwarded});
  final String id;
  final int xpAwarded;
}

abstract interface class CheckInRepository {
  Future<CheckInResult> checkIn({
    required String locationId,
    required double latitude,
    required double longitude,
    required double accuracyMeters,
  });
}
