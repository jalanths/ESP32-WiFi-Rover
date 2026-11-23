/// Network link to the rover, behind an interface so the controller can be
/// tested with a fake link and no real Wi-Fi.
library;

import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

abstract class RoverLink {
  /// Text frames from the rover. Single subscription: listen once.
  Stream<String> get incoming;

  /// Throws if the link is already closed.
  void send(String message);

  Future<void> close();
}

/// Opens a link or throws (timeout, refused, no route).
typedef LinkOpener = Future<RoverLink> Function(Uri uri, Duration timeout);

class WebSocketLink implements RoverLink {
  WebSocketLink._(this._channel);

  final WebSocketChannel _channel;

  static Future<RoverLink> open(Uri uri, Duration timeout) async {
    final channel = WebSocketChannel.connect(uri);
    try {
      await channel.ready.timeout(timeout);
    } catch (_) {
      // Closing a socket that never opened can wait forever, so don't
      // block on it: release it in the background and report the failure.
      unawaited(channel.sink.close().then<void>((_) {}, onError: (Object _) {}));
      rethrow;
    }
    return WebSocketLink._(channel);
  }

  @override
  Stream<String> get incoming =>
      _channel.stream.where((e) => e is String).cast<String>();

  @override
  void send(String message) => _channel.sink.add(message);

  @override
  Future<void> close() async {
    try {
      await _channel.sink.close().timeout(const Duration(seconds: 1));
    } catch (_) {
      // closing a broken socket can throw; the link is gone either way
    }
  }
}
