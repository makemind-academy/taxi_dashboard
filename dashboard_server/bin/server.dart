import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dashboard_server/meter.dart';
import 'package:dashboard_server/screens.dart';
import 'package:dashboard_server/vehicle_link.dart';
import 'package:mcp_server/mcp_server.dart';

/// dashboard_server — four things that used to be four boxes, in one.
///
///   vehicle_bus (C) ──CAN frames──▶ THIS server ──MCP──▶ dashboard  ui://driver
///     speed, door, terminal          meter runs off frames ──MCP──▶ tablet  ui://passenger
///
/// The taxi's problem was never that any one of these boxes was bad. It was
/// that the driver had to be the wire between them: read the meter, work the
/// card reader, watch the dispatch phone, all while driving. So the thing to
/// prove here is not that a screen can show a fare — it is that **nobody presses
/// anything**. The door frame starts the meter, the speed frames build the
/// fare, arrival puts the payment in front of the passenger.
void main(List<String> args) async {
  // `--time-scale=N` slows or speeds the simulated vehicle's clock. The meter
  // is not told: it integrates the timestamps the frames carry, so a trip that
  // is photographed phase by phase and a trip that runs in seven seconds bill
  // the same way.
  final scale = args
      .firstWhere((a) => a.startsWith('--time-scale='), orElse: () => '')
      .replaceFirst('--time-scale=', '');
  final vehicle = VehicleLink();
  await vehicle.start('../vehicle_bus/vehicle_bus',
      args: scale.isEmpty ? const [] : ['--scale', scale]);

  const config = McpServerConfig(
    name: 'Taxi Dashboard',
    version: '1.0.0',
    capabilities: ServerCapabilities(
      tools: ToolsCapability(listChanged: true),
      resources: ResourcesCapability(listChanged: true),
    ),
  );

  final server = McpServer.createServer(config);
  final dashboard = DashboardServer(server, vehicle);

  // Publish before connecting, and before the vehicle has said anything. A
  // client must never be able to ask for a screen that does not exist yet.
  dashboard.register();

  final transport = McpServer.createStdioTransport().get();
  server.connect(transport);

  dashboard.listenToVehicle();

  await Completer<void>().future;
}

class DashboardServer {
  DashboardServer(this.server, this.vehicle);

  /// The cab's plate. Both screens print it, and a receipt that cannot name
  /// the vehicle is not a receipt. A real installation reads it from the
  /// vehicle bus at start-up; this one is registered with the meter.
  static const plate = 'TAXI 34 ML 1234';

  final Server server;
  final VehicleLink vehicle;
  final Meter meter = Meter();

  bool _hired = false;
  bool _payDue = false;
  String _status = 'Waiting for fare';
  String _approval = '-';
  String _notice = '';
  int _lastAuthorizeMs = -1;

  void register() {
    _registerScreens();
    _registerTools();
  }

  // ------------------------------------------------------------- the frames
  //
  // This is the part that replaces the driver's hands.
  void listenToVehicle() {
    vehicle.frames.listen((frame) {
      final t = (frame['t'] as num).toDouble();
      switch (frame['frame']) {
        case 'speed':
          meter.onSpeedFrame((frame['kph'] as num).toDouble(), t);
          if (_hired && meter.running) {
            _status = meter.lastKph < meter.waitingBelowKph
                ? 'Hired — waiting'
                : 'Hired — moving';
          }
          break;

        case 'door':
          final open = frame['open'] == true;
          if (!open) break;
          if (!_hired) {
            // Passenger boarded. The meter starts here, not when a driver
            // remembers to reach for it.
            _hired = true;
            _payDue = false;
            _approval = '-';
            meter.start(t);
            _status = 'Hired — moving';
            _notice = 'Meter started by door frame at t=${t.toStringAsFixed(2)}s';
            stderr.writeln('[trip] hired at t=$t');
          } else if (meter.lastKph == 0) {
            // Door opened while stopped: arrival. Stop the meter and put the
            // fare in front of the passenger.
            meter.stop();
            _hired = false;
            _payDue = true;
            _status = 'Arrived — payment due';
            _notice = 'Fare closed at ${meter.distanceKm.toStringAsFixed(2)} km';
            stderr.writeln('[trip] arrived, fare=${meter.fare}');
          }
          break;
      }
      server.notifyResourceUpdated(_stateUri);
    });
  }

  void _registerScreens() {
    // One app, two pages, and the metadata a launcher reads first — the same
    // resource convention every server app here follows.
    final documents = <String, (String, String, Map<String, dynamic>)>{
      'ui://app': (
        'Taxi — dashboard and trip',
        'One meter, two seats',
        applicationDefinition,
      ),
      'ui://app/info': (
        'App Info',
        'Lightweight application metadata (spec 11.6)',
        appInfoDefinition,
      ),
      'ui://pages/driver': (
        'Taxi Dashboard',
        'Driver-facing meter',
        driverDefinition,
      ),
      'ui://pages/passenger': (
        'Your Trip',
        'Passenger-facing fare and payment',
        passengerDefinition,
      ),
    };
    // The meter as a resource. Both screens subscribe once; every bus frame
    // that moves the fare is pushed to them, nobody polls.
    server.addResource(
      uri: _stateUri,
      name: 'Trip state',
      description: 'The meter and the trip, live',
      mimeType: 'application/json',
      handler: (uri, params) async => ReadResourceResult(contents: [
        ResourceContentInfo(
            uri: _stateUri, mimeType: 'application/json', text: jsonEncode(_stateMap())),
      ]),
    );
    final screens = documents;
    screens.forEach((uri, spec) {
      final (name, description, definition) = spec;
      server.addResource(
        uri: uri,
        name: name,
        description: description,
        mimeType: 'application/json',
        handler: (requestedUri, params) async => ReadResourceResult(
          contents: [
            ResourceContentInfo(
              uri: requestedUri,
              mimeType: 'application/json',
              text: jsonEncode(definition),
            ),
          ],
        ),
      );
    });
  }

  void _registerTools() {
    // Both screens poll this. Nothing here changes the trip.
    server.addTool(
      name: 'trip.state',
      description: 'Current meter and trip state',
      inputSchema: const {'type': 'object', 'properties': {}},
      handler: (args) async => _state(),
    );

    // The passenger taps once. Everything before this happened without anyone
    // touching anything.
    server.addTool(
      name: 'fare.charge',
      description: 'Ask the in-dash card terminal to authorize the fare',
      inputSchema: const {'type': 'object', 'properties': {}},
      handler: (args) async {
        if (!_payDue) {
          _notice = 'No fare to charge';
          return _state();
        }
        final amount = meter.fare;
        final started = DateTime.now();
        try {
          final r = await vehicle.call('terminal.authorize', {'amount': amount});
          _lastAuthorizeMs = DateTime.now().difference(started).inMilliseconds;
          _approval = '${r['approvalCode']} (${r['last4']})';
          _payDue = false;
          _status = 'Paid';
          server.notifyResourceUpdated(_stateUri);
          _notice = 'Approved ${_usd(amount)} in $_lastAuthorizeMs ms';
          stderr.writeln('[fare] approved $amount in $_lastAuthorizeMs ms');
        } on TimeoutException {
          // Same rule as any card path: a timeout is not a decline. Say what we
          // know, which is nothing.
          _notice = 'Terminal did not answer — check the receipt before retrying';
        } on StateError catch (e) {
          _notice = 'Declined: ${e.message}';
        }
        return _state();
      },
    );

    server.addTool(
      name: 'bus.stats',
      description: 'How much of the bus the meter actually consumed',
      inputSchema: const {'type': 'object', 'properties': {}},
      handler: (args) async => CallToolResult(
        content: [
          TextContent(
            text: jsonEncode({
              'framesSeen': vehicle.framesSeen,
              'framesUsed': meter.framesUsed,
              'framesDroppedOutOfOrder': meter.framesDroppedOutOfOrder,
              'requestTranscript': vehicle.transcript,
              'lastAuthorizeMs': _lastAuthorizeMs,
            }),
          ),
        ],
      ),
    );
  }

  /// Money as the cab prints it. Formatted once, here, because two screens
  /// that group digits themselves group them differently.
  /// Money as the meter prints it: cents in, `$12.30` out.
  static String _usd(num cents) {
    final c = cents.round();
    final whole = (c ~/ 100).toString();
    final buf = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) buf.write(',');
      buf.write(whole[i]);
    }
    return '\$$buf.${(c % 100).toString().padLeft(2, '0')}';
  }

  CallToolResult _state() =>
      CallToolResult(content: [TextContent(text: jsonEncode(_stateMap()))]);

  static const _stateUri = 'trip://state';

  Map<String, dynamic> _stateMap() {
    final m = meter.toJson();
    final distanceCharge = meter.perKm * meter.distanceKm;
    final waitingCharge = meter.perWaitingMinute * (meter.waitingSeconds / 60.0);
    final snapshot = <String, dynamic>{
      ...m,
      'status': _status,
      'approval': _approval,
      'notice': _notice,
      'payDue': _payDue,
      // The plate is the cab's identity, and both screens show it: a receipt
      // that cannot name the vehicle is not a receipt.
      'plate': plate,
      // Labels, not numbers. The breakdown adds up to the fare above it, and
      // the passenger can check that without trusting the total.
      'fareLabel': _usd(meter.fare),
      'flagfallLabel': _usd(meter.flagfall),
      'distanceChargeLabel': _usd(distanceCharge),
      'waitingChargeLabel': _usd(waitingCharge),
      'distanceLabel': '${meter.distanceKm.toStringAsFixed(2)} km',
      'waitingLabel': '${meter.waitingSeconds.toStringAsFixed(1)} s',
      'kphLabel': '${meter.lastKph.toStringAsFixed(1)} km/h',
      // The rule the meter runs by, in the words a passenger would use. It
      // lives with the meter, not on a screen.
      'meterRule': 'Waiting time bills below '
          '${meter.waitingBelowKph.toStringAsFixed(0)} km/h',
    };
    return snapshot;
  }
}
