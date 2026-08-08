import 'dart:async';

import 'package:smart_monitor/core/api_client.dart';

/// Runs once around the whole suite — Flutter picks this file up by name.
///
/// The API client logs every request in a debug build, and the tests run in
/// one, so without this each stubbed call would print a request and a response
/// line and bury the actual test output. Anything checking the logging itself
/// turns it back on for its own test.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  ApiClient.logRequests = false;
  await testMain();
}
