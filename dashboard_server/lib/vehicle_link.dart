import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Host side of the vehicle bus.
///
/// Two kinds of traffic arrive on one wire and they are not the same thing:
///
///   * **frames** — pushed by the vehicle, unasked, whenever it feels like it.
///     Nobody is waiting on them and there is nothing to reply to.
///   * **replies** — answers to something we asked, matched by id.
///
/// Conflating the two is the classic way to break a dashboard: a frame that
/// happens to arrive while an authorization is in flight gets handed to the
/// code waiting for the approval. So the split happens here, once, at the point
/// where bytes become meaning.
class VehicleLink {
  VehicleLink({this.requestTimeout = const Duration(seconds: 3)});

  final Duration requestTimeout;

  late final Process _proc;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  int _nextId = 1;

  /// Every frame the vehicle pushed, in order.
  final _frames = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get frames => _frames.stream;

  int framesSeen = 0;
  final List<String> transcript = <String>[];

  Future<void> start(String executable, {List<String> args = const []}) async {
    _proc = await Process.start(executable, args);
    _proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine);
    _proc.stderr.drain<void>();
  }

  void _onLine(String line) {
    if (line.trim().isEmpty) return;
    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(line) as Map<String, dynamic>;
    } on FormatException {
      // A bus carries noise. A malformed frame is not a reason to take the
      // dashboard down mid-fare; drop it and keep listening.
      return;
    }

    if (msg.containsKey('frame')) {
      framesSeen++;
      _frames.add(msg);
      return;
    }
    // Only replies are worth keeping in the transcript — the frame stream is
    // thousands of lines and the interesting part is what we asked for.
    transcript.add('<= $line');
    _pending.remove(msg['id'] as int?)?.complete(msg);
  }

  Future<Map<String, dynamic>> call(
    String tool, [
    Map<String, dynamic> args = const {},
  ]) async {
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    final request = jsonEncode({'id': id, 'tool': tool, 'args': args});
    transcript.add('=> $request');
    _proc.stdin.writeln(request);

    final reply = await completer.future.timeout(
      requestTimeout,
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('vehicle did not answer $tool', requestTimeout);
      },
    );
    if (reply['ok'] != true) {
      throw StateError('vehicle refused $tool: ${reply['error']}');
    }
    return (reply['result'] as Map).cast<String, dynamic>();
  }

  void dispose() {
    _frames.close();
    _proc.kill();
  }
}
