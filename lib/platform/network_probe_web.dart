import 'package:web/web.dart' as web;

Future<bool> probeNetworkReachable() async => web.window.navigator.onLine;

bool isSocketError(Object error) => false;
