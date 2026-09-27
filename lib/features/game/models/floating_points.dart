/// Short-lived score indicator that rises and fades after a clear.
class FloatingPoints {
  double x;
  double y;
  final int points;
  double opacity;
  final DateTime createdAt;

  FloatingPoints({
    required this.x,
    required this.y,
    required this.points,
    this.opacity = 1.0,
  }) : createdAt = DateTime.now();

  bool get isExpired {
    final elapsed = DateTime.now().difference(createdAt).inMilliseconds;
    return elapsed > 1500;
  }

  /// Advances the indicator by [deltaTime] seconds.
  void update({required double deltaTime}) {
    y -= 20 * deltaTime;

    final elapsed = DateTime.now().difference(createdAt).inMilliseconds;
    opacity = (1.0 - (elapsed / 1500)).clamp(0.0, 1.0);
  }
}
