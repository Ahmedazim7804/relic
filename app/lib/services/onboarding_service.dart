import '../data/api.dart';
import '../data/device_directory.dart';
import '../data/http_relay.dart';
import '../data/worker_repo.dart';

class PairedKeyMismatch implements Exception {
  const PairedKeyMismatch();
  String get message =>
      "The key sent by your other device doesn't open this account's vault. "
      'Make sure both devices are signed in to the same Relic account, then try again.';
  @override
  String toString() => message;
}

class OnboardingService {
  final String baseUrl;
  final String deviceId;
  OnboardingService({this.baseUrl = kWorkerBaseUrl, required this.deviceId});

  HttpRelay relayForRepo(WorkerRepo repo) => HttpRelay(
        baseUrl: baseUrl,
        bearer: () async => repo.token,
        deviceId: deviceId,
      );

  HttpRelay relayWith(Future<String?> Function() bearer) =>
      HttpRelay(baseUrl: baseUrl, bearer: bearer, deviceId: deviceId);

  DeviceDirectory devicesWith(Future<String?> Function() bearer) =>
      DeviceDirectory(baseUrl: baseUrl, bearer: bearer, deviceId: deviceId);

  DeviceDirectory devicesForRepo(WorkerRepo repo) => DeviceDirectory(
        baseUrl: baseUrl,
        bearer: () async => repo.token,
        deviceId: deviceId,
      );
}
