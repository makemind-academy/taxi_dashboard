/// The taximeter.
///
/// The bus never sends a distance. It sends a speed, now and then, at whatever
/// rate it feels like. Turning that into a fare is the whole job of this file,
/// and it is where a dashboard is easy to get subtly wrong.
class Meter {
  Meter({
    this.flagfall = 350, // cents
    this.perKm = 200, // cents per km
    this.perWaitingMinute = 700,
    this.waitingBelowKph = 5.0,
  });

  /// Base fare on hiring.
  final int flagfall;

  /// Charged per kilometre travelled.
  final int perKm;

  /// Charged per minute spent below [waitingBelowKph] — a taxi stuck at a light
  /// is still working, and a meter that only counted distance would bill the
  /// driver for the city's traffic.
  final int perWaitingMinute;
  final double waitingBelowKph;

  bool running = false;
  double distanceKm = 0;
  double waitingSeconds = 0;
  double lastKph = 0;
  double _lastT = 0;
  int framesUsed = 0;
  int framesDroppedOutOfOrder = 0;

  void start(double t) {
    running = true;
    distanceKm = 0;
    waitingSeconds = 0;
    _lastT = t;
    framesUsed = 0;
    framesDroppedOutOfOrder = 0;
  }

  void stop() => running = false;

  /// Fold one speed frame into the trip.
  ///
  /// Two things make this more than `distance += speed * interval`.
  ///
  /// First, the interval is not a constant. Frames arrive when the bus sends
  /// them, and under load they arrive late. So the elapsed time carried by the
  /// frames themselves is used, never a nominal period — assuming 100 ms and
  /// being handed 140 ms is a 40% overcharge, quietly, on every fare.
  ///
  /// Second, speed changes across the gap. Taking the newest reading and
  /// multiplying overstates every acceleration and understates every braking.
  /// Averaging the two ends (the trapezoid) is one line more and is right at
  /// both ends.
  void onSpeedFrame(double kph, double t) {
    if (!running) {
      lastKph = kph;
      _lastT = t;
      return;
    }
    final dt = t - _lastT;
    if (dt <= 0) {
      // Frames can arrive out of order on a busy bus. A negative interval would
      // subtract distance from the fare, so drop it and say that we did.
      framesDroppedOutOfOrder++;
      return;
    }

    final averageKph = (lastKph + kph) / 2;
    distanceKm += averageKph * dt / 3600.0;
    if (averageKph < waitingBelowKph) waitingSeconds += dt;

    lastKph = kph;
    _lastT = t;
    framesUsed++;
  }

  /// Fare in cents, rounded to the nearest 10 the way a printed receipt is.
  int get fare {
    if (!running && distanceKm == 0) return 0;
    final raw = flagfall +
        perKm * distanceKm +
        perWaitingMinute * (waitingSeconds / 60.0);
    return (raw / 10).round() * 10;
  }

  Map<String, dynamic> toJson() => {
        'running': running,
        'distanceKm': double.parse(distanceKm.toStringAsFixed(2)),
        'waitingSeconds': double.parse(waitingSeconds.toStringAsFixed(1)),
        'kph': double.parse(lastKph.toStringAsFixed(1)),
        'fare': fare,
        'framesUsed': framesUsed,
        'framesDroppedOutOfOrder': framesDroppedOutOfOrder,
      };
}
