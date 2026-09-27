import 'package:flutter/material.dart';

/// Mutable simulation state for one numbered square on the board.
///
/// Position and speed are updated every game tick. [placed] permanently
/// disables dragging after landing, while [landed] describes current support.
class FallingSquare {
  double x;
  double y;
  double size;
  Color color;
  double speed;
  int number;
  bool landed;
  bool placed;
  bool dragging;

  FallingSquare({
    required this.x,
    required this.y,
    required this.size,
    required this.color,
    required this.speed,
    required this.number,
    this.landed = false,
    this.placed = false,
    this.dragging = false,
  });
}
