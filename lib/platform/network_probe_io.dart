import 'dart:io';

Future<bool> probeNetworkReachable() async {
  try {
    final ipv4 = await InternetAddress.lookup(
      'firestore.googleapis.com',
      type: InternetAddressType.IPv4,
    );
    if (ipv4.isNotEmpty) {
      final socket = await Socket.connect(ipv4.first, 443, timeout: const Duration(seconds: 3));
      socket.destroy();
      return true;
    }
  } catch (_) {}
  try {
    final socket = await Socket.connect(InternetAddress('1.1.1.1'), 443, timeout: const Duration(seconds: 2));
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

bool isSocketError(Object error) => error is SocketException;
