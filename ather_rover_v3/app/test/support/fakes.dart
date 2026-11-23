import 'dart:async';

import 'package:ather_rover/core/transport.dart';

/// In-memory stand-in for the WebSocket.
class FakeLink implements RoverLink {
  final _in = StreamController<String>();
  final sent = <String>[];
  bool closed = false;

  @override
  Stream<String> get incoming => _in.stream;

  @override
  void send(String message) {
    if (closed) throw StateError('closed');
    sent.add(message);
  }

  @override
  Future<void> close() async {
    closed = true;
    _in.close();
  }

  void push(String line) => _in.add(line);

  /// Simulates the rover dropping the connection.
  void drop() => _in.close();
}

/// Hands out links in order; a `false` entry fails like an unreachable rover.
class FakeNetwork {
  FakeNetwork(this.plan);

  final List<bool> plan; // true = succeed, false = fail
  final links = <FakeLink>[];
  int attempts = 0;

  Future<RoverLink> open(Uri uri, Duration timeout) async {
    final ok = attempts < plan.length ? plan[attempts] : true;
    attempts++;
    if (!ok) throw TimeoutException('no rover');
    final l = FakeLink();
    links.add(l);
    return l;
  }
}
