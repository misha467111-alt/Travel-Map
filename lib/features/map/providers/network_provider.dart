import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum NetworkStatus { online, offline }

final networkStatusProvider = StreamProvider<NetworkStatus>((ref) async* {
  final connectivity = Connectivity();

  NetworkStatus mapResults(List<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none)
        ? NetworkStatus.online
        : NetworkStatus.offline;
  }

  yield mapResults(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(mapResults).distinct();
});

final isOnlineProvider = Provider<bool>((ref) {
  return ref.watch(networkStatusProvider).value == NetworkStatus.online;
});
