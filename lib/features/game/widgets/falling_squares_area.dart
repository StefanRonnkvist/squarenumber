import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:squarenumber/features/game/models/falling_square.dart';
import 'package:squarenumber/features/game/models/floating_points.dart';

/// Owns the falling-square game loop, input handling, scoring, and paused-run
/// persistence for one play area.
class FallingSquaresArea extends StatefulWidget {
  const FallingSquaresArea({
    super.key,
    required this.speedMultiplier,
    required this.minNumber,
    required this.maxNumber,
    this.preferredSquareSize = 59,
    this.isActive = true,
    this.onAreaWidthChanged,
    this.onScoreChanged,
    this.onRunningChanged,
    this.onGameOverChanged,
    this.onGameCompleted,
    this.initialSquaresBuilder,
    this.disableSpawning = false,
  });

  final double speedMultiplier;
  final int minNumber;
  final int maxNumber;
  final double preferredSquareSize;
  final bool isActive;
  final ValueChanged<double>? onAreaWidthChanged;
  final ValueChanged<int>? onScoreChanged;
  final ValueChanged<bool>? onRunningChanged;
  final ValueChanged<bool>? onGameOverChanged;
  final ValueChanged<int>? onGameCompleted;
  final List<FallingSquare> Function(double squareSize)? initialSquaresBuilder;
  final bool disableSpawning;

  @override
  State<FallingSquaresArea> createState() => _FallingSquaresAreaState();
}

class _FallingSquaresAreaState extends State<FallingSquaresArea>
    with
        WidgetsBindingObserver,
        AutomaticKeepAliveClientMixin<FallingSquaresArea> {
  final List<FallingSquare> _squares = [];
  final List<FloatingPoints> _floatingPoints = [];
  final Random _random = Random();
  late final List<Color> _safeDarkColors = generateSafeDarkColors();
  Timer? _updateTimer;
  Timer? _spawnTimer;
  int _score = 0;
  bool _isRunning = false;
  bool _isGameOver = false;
  late double _activePreferredSquareSize;
  int _comboMultiplier = 1;
  bool _hasInitializedInjectedSquares = false;

  double _areaWidth = 0;
  double _areaHeight = 0;
  double _lastObservedWidth = 0;
  double _lastObservedHeight = 0;
  double _lastReportedAreaWidth = -1;
  static const int _fixedColumnsAcross = 5;
  static const String _pausedGameStorageKey = 'paused_game_snapshot_v1';
  _PausedLayoutSnapshot? _pendingPersistedPausedSnapshot;
  bool _isLoadingPersistedPausedSnapshot = false;

  /// Normalizes reversed user settings so random-number generation is valid.
  ({int min, int max}) get _numberBounds {
    return (
      min: min(widget.minNumber, widget.maxNumber),
      max: max(widget.minNumber, widget.maxNumber),
    );
  }

  double _squareSizeForAreaWidth(double areaWidth) {
    if (areaWidth <= 0) {
      return _activePreferredSquareSize;
    }

    final maxSizeForConfiguredAcross = areaWidth / _fixedColumnsAcross;
    return min(_activePreferredSquareSize, maxSizeForConfiguredAcross);
  }

  double get _squareSize {
    return _squareSizeForAreaWidth(_areaWidth);
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _activePreferredSquareSize = widget.preferredSquareSize;
    WidgetsBinding.instance.addObserver(this);
    _loadPersistedPausedSnapshot();
    _updateTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _updateSquares(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _pauseGame();
      _persistPausedSnapshot();
    }
  }

  @override
  void didUpdateWidget(covariant FallingSquaresArea oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isActive && !widget.isActive) {
      _pauseGame();
    }

    // Size changes apply immediately only to an empty, stopped board. An
    // active board keeps one coordinate system until it is remapped on resize.
    final preferredSquareSizeChanged =
        oldWidget.preferredSquareSize != widget.preferredSquareSize;
    final settingsChanged =
        oldWidget.minNumber != widget.minNumber ||
        oldWidget.maxNumber != widget.maxNumber;

    if (preferredSquareSizeChanged &&
        !_isRunning &&
        _squares.isEmpty &&
        mounted) {
      setState(() {
        _activePreferredSquareSize = widget.preferredSquareSize;
      });
    }

    if (!settingsChanged) {
      return;
    }

    final wasRunning = _isRunning;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _resetGame();
      if (wasRunning) {
        setState(() {
          _isRunning = true;
        });
        widget.onRunningChanged?.call(true);
        _spawnSquare();
        _scheduleNextSpawn();
      }
    });
  }

  void _toggleRunning() {
    if (_isGameOver) {
      _startNewGame();
      return;
    }

    final nextRunning = !_isRunning;
    setState(() {
      if (nextRunning && _squares.isEmpty) {
        _activePreferredSquareSize = widget.preferredSquareSize;
      }
      _isRunning = nextRunning;
    });
    widget.onRunningChanged?.call(nextRunning);

    if (nextRunning) {
      _normalizeSquareSpeeds();
      if (_squares.isEmpty &&
          _pendingPersistedPausedSnapshot == null &&
          !_isLoadingPersistedPausedSnapshot) {
        _spawnSquare();
      }
      _scheduleNextSpawn();
      return;
    }

    _persistPausedSnapshot();
  }

  void _pauseGame() {
    if (!_isRunning) return;
    setState(() {
      _isRunning = false;
    });
    widget.onRunningChanged?.call(false);
    _persistPausedSnapshot();
  }

  void _startNewGame() {
    // Report the old run before reset so starting over does not discard score.
    _completeCurrentGame();
    _pendingPersistedPausedSnapshot = null;
    _clearPersistedPausedSnapshot();
    _resetGame();
    setState(() {
      _activePreferredSquareSize = widget.preferredSquareSize;
      _isRunning = true;
    });
    widget.onRunningChanged?.call(true);

    if (_squares.isEmpty) {
      _spawnSquare();
    }
    _scheduleNextSpawn();
  }

  void _resetGame() {
    _spawnTimer?.cancel();
    _spawnTimer = null;
    _pendingPersistedPausedSnapshot = null;
    _clearPersistedPausedSnapshot();

    setState(() {
      _activePreferredSquareSize = widget.preferredSquareSize;
      _squares.clear();
      _score = 0;
      _isRunning = false;
      _isGameOver = false;
      _comboMultiplier = 1;
    });
    widget.onScoreChanged?.call(_score);
    widget.onRunningChanged?.call(false);
    widget.onGameOverChanged?.call(false);
  }

  void _completeCurrentGame() {
    if (_score > 0 && !_isGameOver) {
      widget.onGameCompleted?.call(_score);
    }
  }

  Future<void> _loadPersistedPausedSnapshot() async {
    _isLoadingPersistedPausedSnapshot = true;
    try {
      final preferences = await SharedPreferences.getInstance();
      final rawSnapshot = preferences.getString(_pausedGameStorageKey);
      if (rawSnapshot == null || rawSnapshot.isEmpty || !mounted) {
        return;
      }

      final decoded = jsonDecode(rawSnapshot);
      if (decoded is! Map<String, dynamic>) {
        return;
      }

      final restored = _PausedLayoutSnapshot.fromJson(decoded);
      if (restored == null) {
        return;
      }

      setState(() {
        _pendingPersistedPausedSnapshot = restored;
      });
    } catch (_) {
      // Ignore persistence failures and continue with default game setup.
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPersistedPausedSnapshot = false;
        });
        _restorePersistedPausedSnapshotIfReady();
      } else {
        _isLoadingPersistedPausedSnapshot = false;
      }
    }
  }

  void _persistPausedSnapshot() {
    if (_isGameOver || _squares.isEmpty) {
      _clearPersistedPausedSnapshot();
      return;
    }

    // Drag state is transient input state and must never survive a restart.
    final snapshot = _PausedLayoutSnapshot(
      score: _score,
      comboMultiplier: _comboMultiplier,
      isGameOver: _isGameOver,
      squares: _squares
          .map(
            (square) => FallingSquare(
              x: square.x,
              y: square.y,
              size: square.size,
              color: square.color,
              speed: square.speed,
              number: square.number,
              landed: square.landed,
              placed: square.placed,
              dragging: false,
            ),
          )
          .toList(growable: false),
    );

    unawaited(_savePausedSnapshot(snapshot));
  }

  Future<void> _savePausedSnapshot(_PausedLayoutSnapshot snapshot) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _pausedGameStorageKey,
        jsonEncode(snapshot.toJson()),
      );
    } catch (_) {
      // Ignore persistence failures and continue with in-memory game state.
    }
  }

  void _clearPersistedPausedSnapshot() {
    unawaited(_removePersistedPausedSnapshot());
  }

  Future<void> _removePersistedPausedSnapshot() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(_pausedGameStorageKey);
    } catch (_) {
      // Ignore persistence failures.
    }
  }

  void _restorePersistedPausedSnapshotIfReady() {
    // Coordinates cannot be restored safely until LayoutBuilder has supplied
    // the current board dimensions and grid size.
    final snapshot = _pendingPersistedPausedSnapshot;
    if (snapshot == null ||
        !mounted ||
        _isRunning ||
        _squares.isNotEmpty ||
        _areaWidth <= 0 ||
        _areaHeight <= 0 ||
        _squareSize <= 0) {
      return;
    }

    setState(() {
      _score = snapshot.score;
      _comboMultiplier = snapshot.comboMultiplier;
      _isGameOver = snapshot.isGameOver;
      _squares
        ..clear()
        ..addAll(
          snapshot.squares.map(
            (square) => FallingSquare(
              x: square.x,
              y: square.y,
              size: square.size,
              color: square.color,
              speed: square.speed,
              number: square.number,
              landed: square.landed,
              placed: square.placed,
              dragging: false,
            ),
          ),
        );
      _pendingPersistedPausedSnapshot = null;
      _hasInitializedInjectedSquares = true;
    });

    widget.onScoreChanged?.call(_score);
    widget.onGameOverChanged?.call(_isGameOver);
  }

  void _clampSquaresToAreaBounds() {
    if (_areaWidth <= 0 || _areaHeight <= 0 || _squares.isEmpty) {
      return;
    }

    bool hasChanges = false;
    for (final square in _squares) {
      final clampedX = square.x
          .clamp(0.0, max(0.0, _areaWidth - square.size))
          .toDouble();
      final clampedY = square.y
          .clamp(-square.size, _areaHeight - square.size)
          .toDouble();

      if (square.x != clampedX) {
        square.x = clampedX;
        hasChanges = true;
      }

      if (square.y != clampedY) {
        square.y = clampedY;
        hasChanges = true;
      }
    }

    if (!hasChanges || !mounted) {
      return;
    }

    setState(() {});
  }

  void _remapSquaresForAreaChange({
    required double previousWidth,
    required double previousHeight,
    required double newWidth,
    required double newHeight,
  }) {
    if (_squares.isEmpty ||
        previousWidth <= 0 ||
        previousHeight <= 0 ||
        newWidth <= 0 ||
        newHeight <= 0) {
      return;
    }

    final previousSquareSize = _squareSizeForAreaWidth(previousWidth);
    final newSquareSize = _squareSizeForAreaWidth(newWidth);
    if (previousSquareSize <= 0 || newSquareSize <= 0) {
      return;
    }

    // Preserve each square's grid-relative position and size instead of its
    // old pixel coordinates when the board changes dimensions.
    bool hasChanges = false;
    for (final square in _squares) {
      final columnUnits = square.x / previousSquareSize;
      final rowUnits = square.y / previousSquareSize;
      final sizeUnits = square.size / previousSquareSize;

      final remappedX = columnUnits * newSquareSize;
      final remappedY = rowUnits * newSquareSize;
      final remappedSize = sizeUnits * newSquareSize;

      if (square.x != remappedX) {
        square.x = remappedX;
        hasChanges = true;
      }
      if (square.y != remappedY) {
        square.y = remappedY;
        hasChanges = true;
      }
      if (square.size != remappedSize) {
        square.size = remappedSize;
        hasChanges = true;
      }
    }

    if (hasChanges && mounted) {
      setState(() {});
    }
  }

  void _normalizeSquaresToCurrentGrid() {
    if (_squares.isEmpty) {
      return;
    }

    final targetSize = _squareSize;
    if (targetSize <= 0) {
      return;
    }

    bool hasChanges = false;
    for (final square in _squares) {
      if (square.size <= 0) {
        continue;
      }

      if ((square.size - targetSize).abs() < 0.01) {
        continue;
      }

      final ratio = targetSize / square.size;
      square.x *= ratio;
      square.y *= ratio;
      square.size = targetSize;
      hasChanges = true;
    }

    if (hasChanges && mounted) {
      setState(() {});
    }
  }

  void _endGame() {
    if (_isGameOver) {
      return;
    }

    _completeCurrentGame();
    _spawnTimer?.cancel();
    _spawnTimer = null;
    _clearPersistedPausedSnapshot();

    setState(() {
      _isRunning = false;
      _isGameOver = true;
    });
    widget.onRunningChanged?.call(false);
    widget.onGameOverChanged?.call(true);
  }

  void _spawnSquare() {
    if (widget.disableSpawning) {
      return;
    }

    // A newly spawned piece ends the previous cascade chain.
    _comboMultiplier = 1;

    final squareSize = _squareSize;
    if (_areaWidth <= squareSize || _areaHeight <= squareSize) {
      return;
    }
    final bounds = _numberBounds;
    final number = _random.nextInt(bounds.max - bounds.min + 1) + bounds.min;
    final rawX = _random.nextDouble() * (_areaWidth - squareSize);
    final snappedX = _snapXToColumn(rawX, squareSize);
    setState(() {
      _squares.add(
        FallingSquare(
          x: snappedX,
          y: -squareSize,
          size: squareSize,
          color: _colorForNumber(number),
          speed: 50 + _random.nextDouble() * 35,
          number: number,
        ),
      );
    });
  }

  Color _colorForNumber(int number) {
    // Map the configured numeric range evenly across a deterministic palette.
    final paletteSize = _safeDarkColors.length;
    if (paletteSize == 0) {
      return Colors.black;
    }

    final bounds = _numberBounds;
    final minNumber = bounds.min;
    final maxNumber = bounds.max;
    final spread = maxNumber - minNumber;
    if (spread <= 0) {
      return _safeDarkColors.first;
    }

    final clampedNumber = number.clamp(minNumber, maxNumber);
    final position = (clampedNumber - minNumber) / spread;
    final paletteIndex = (position * (paletteSize - 1)).round();
    return _safeDarkColors[paletteIndex];
  }

  List<Color> generateSafeDarkColors() {
    // Keep every RGB channel dark enough for readable white number labels.
    return List.generate(512, (n) {
      final int r = n ~/ 64;
      final int g = (n ~/ 8) % 8;
      final int b = n % 8;

      return Color.fromARGB(255, 10 + 20 * r, 10 + 20 * g, 10 + 20 * b);
    });
  }

  void _scheduleNextSpawn() {
    if (widget.disableSpawning) {
      return;
    }

    if (!_isRunning || _spawnTimer?.isActive == true || _hasActiveSquare()) {
      return;
    }

    // Defer mutation until the current frame/setState has completed. Before a
    // new piece appears, resolve any cascade left by the previous removal.
    _spawnTimer = Timer(Duration.zero, () {
      _spawnTimer = null;

      if (!mounted || !_isRunning || _hasActiveSquare()) {
        return;
      }

      bool clearedMatches = false;
      setState(() {
        clearedMatches = _clearMatchingSquares();
      });
      if (clearedMatches || _hasActiveSquare()) {
        return;
      }

      _spawnSquare();
    });
  }

  bool _hasActiveSquare() {
    // A piece is active while dragged or while still above its computed floor.
    return _squares.any((square) {
      if (square.dragging) {
        return true;
      }

      final floor = _landingY(square);
      return square.y < floor - 0.1;
    });
  }

  void _startDragging(FallingSquare sq) {
    if (sq.placed) {
      return;
    }
    setState(() {
      sq.dragging = true;
      sq.landed = false;
    });
  }

  void _updateDragging(FallingSquare sq, DragUpdateDetails details) {
    if (sq.placed) {
      return;
    }
    setState(() {
      sq.x = (sq.x + details.delta.dx).clamp(0.0, _areaWidth - sq.size);
      final nextY = sq.y + max(0.0, details.delta.dy);
      final floor = _landingY(sq);
      sq.y = nextY.clamp(-sq.size, floor);
      _clearMatchingSquares();
    });
    _scheduleNextSpawn();
  }

  double _snapXToColumn(double x, double size) {
    if (_squareSize <= 0) return x;
    final col = (x / _squareSize).round();
    return (col * _squareSize).clamp(0.0, _areaWidth - size);
  }

  void _stopDragging(FallingSquare sq) {
    setState(() {
      sq.dragging = false;
      sq.x = _snapXToColumn(sq.x, sq.size);
      _clearMatchingSquares();
    });

    if (_isStackAboveTopBorder()) {
      _endGame();
      return;
    }

    _scheduleNextSpawn();
  }

  void _updateSquares() {
    if (!_isRunning) {
      return;
    }

    // The fixed timestep matches the periodic timer used in initState.
    const dt = 16 / 1000.0;
    bool clearedMatches = false;
    setState(() {
      for (final sq in _squares) {
        final floor = _landingY(sq);
        if (sq.dragging) {
          continue;
        }

        if (sq.y < floor) {
          sq.y += sq.speed * widget.speedMultiplier * dt;
          if (sq.y >= floor) {
            sq.y = floor;
            sq.landed = true;
            sq.placed = true;
          } else {
            sq.landed = false;
          }
          continue;
        }

        // Settled squares may fall after support is cleared, but dragging a
        // piece beneath them must not push them upward.
        if ((sq.y - floor).abs() <= 0.1) {
          sq.y = floor;
          sq.landed = true;
          sq.placed = true;
          continue;
        }

        sq.landed = true;
        sq.placed = true;
      }

      for (final fp in _floatingPoints) {
        fp.update(deltaTime: dt);
      }
      _floatingPoints.removeWhere((fp) => fp.isExpired);

      clearedMatches = _clearMatchingSquares();
    });

    if (_isStackAboveTopBorder()) {
      _endGame();
      return;
    }

    if (clearedMatches || !_hasActiveSquare()) {
      _scheduleNextSpawn();
    }
  }

  bool _isStackAboveTopBorder() {
    return _squares.any((square) => square.placed && square.y < 0);
  }

  bool _clearMatchingSquares() {
    // Each search builds a connected component. Equal values may touch on any
    // edge/corner, while sequential values must be orthogonally aligned.
    final toRemove = <FallingSquare>{};
    final sameNumberVisited = <FallingSquare>{};
    final sequentialVisited = <FallingSquare>{};
    final matchedGroups = <List<FallingSquare>>[];

    for (final square in _squares) {
      if (sameNumberVisited.contains(square)) {
        continue;
      }

      final stack = <FallingSquare>[square];
      final connected = <FallingSquare>[];

      while (stack.isNotEmpty) {
        final current = stack.removeLast();
        if (!sameNumberVisited.add(current)) {
          continue;
        }

        connected.add(current);

        for (final candidate in _squares) {
          if (sameNumberVisited.contains(candidate) ||
              candidate.number != current.number) {
            continue;
          }

          if (_squaresTouch(current, candidate)) {
            stack.add(candidate);
          }
        }
      }

      if (connected.length >= 2) {
        matchedGroups.add(connected);
        toRemove.addAll(connected);
      }
    }

    for (final square in _squares) {
      if (toRemove.contains(square) || sequentialVisited.contains(square)) {
        continue;
      }

      final stack = <FallingSquare>[square];
      final connected = <FallingSquare>[];

      while (stack.isNotEmpty) {
        final current = stack.removeLast();
        if (!sequentialVisited.add(current)) {
          continue;
        }

        connected.add(current);

        for (final candidate in _squares) {
          if (candidate == current ||
              toRemove.contains(candidate) ||
              sequentialVisited.contains(candidate)) {
            continue;
          }

          final isSequential = (candidate.number - current.number).abs() == 1;
          if (!isSequential) {
            continue;
          }

          if (_squaresTouchOrthogonally(current, candidate)) {
            stack.add(candidate);
          }
        }
      }

      if (connected.length >= 3) {
        // A connected chain such as 1-2-1 is not a valid sequence.
        final numbers = connected.map((s) => s.number).toSet();
        if (numbers.length == connected.length) {
          matchedGroups.add(connected);
          toRemove.addAll(connected);
        }
      }
    }

    if (toRemove.isEmpty) {
      return false;
    }

    final basePoints = matchedGroups.fold<int>(0, (total, group) {
      final groupSum = group.fold<int>(0, (sum, square) => sum + square.number);
      // Reward larger matching groups: (sum of values) * group size.
      return total + (groupSum * group.length);
    });
    final multipliedPoints = basePoints * _comboMultiplier;

    // Anchor one score indicator at the centroid of the entire clear.
    if (toRemove.isNotEmpty) {
      double centerX = 0;
      double centerY = 0;
      for (final square in toRemove) {
        centerX += square.x + square.size / 2;
        centerY += square.y + square.size / 2;
      }
      centerX /= toRemove.length;
      centerY /= toRemove.length;

      final displayPoints = _comboMultiplier > 1
          ? multipliedPoints
          : basePoints;
      _floatingPoints.add(
        FloatingPoints(x: centerX, y: centerY, points: displayPoints),
      );
    }

    _score += multipliedPoints;
    widget.onScoreChanged?.call(_score);
    _squares.removeWhere(toRemove.contains);

    // A clear during the next gravity pass is part of the same cascade.
    _comboMultiplier++;

    return true;
  }

  bool _squaresTouch(FallingSquare first, FallingSquare second) {
    return first.x <= second.x + second.size &&
        first.x + first.size >= second.x &&
        first.y <= second.y + second.size &&
        first.y + first.size >= second.y;
  }

  bool _squaresTouchOrthogonally(FallingSquare first, FallingSquare second) {
    // Tolerance absorbs sub-pixel remapping error; the overlap requirement
    // prevents diagonal corner contact from counting as sequential adjacency.
    const edgeTolerance = 1.0;
    final horizontalGap = max(
      0.0,
      max(
        second.x - (first.x + first.size),
        first.x - (second.x + second.size),
      ),
    );
    final verticalGap = max(
      0.0,
      max(
        second.y - (first.y + first.size),
        first.y - (second.y + second.size),
      ),
    );

    if (horizontalGap > edgeTolerance || verticalGap > edgeTolerance) {
      return false;
    }

    final overlapX =
        min(first.x + first.size, second.x + second.size) -
        max(first.x, second.x);
    final overlapY =
        min(first.y + first.size, second.y + second.size) -
        max(first.y, second.y);
    final minimumAlignedOverlap = min(first.size, second.size) * 0.5;

    final sideBySide = overlapY >= minimumAlignedOverlap;
    final stacked = overlapX >= minimumAlignedOverlap;
    return sideBySide || stacked;
  }

  double _landingY(FallingSquare sq) {
    // The nearest overlapping square below the piece becomes its local floor.
    double floor = _areaHeight - sq.size;
    for (final other in _squares) {
      if (other == sq) {
        continue;
      }
      final overlapX = sq.x < other.x + other.size && sq.x + sq.size > other.x;
      final otherIsBelow = other.y >= sq.y;
      if (overlapX && otherIsBelow) {
        final top = other.y - sq.size;
        if (top < floor) {
          floor = top;
        }
      }
    }
    return floor;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _persistPausedSnapshot();
    widget.onRunningChanged?.call(false);
    _updateTimer?.cancel();
    _spawnTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        const double controlRowSpacing = 8;
        final double currentWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 0.0;
        final bool compactControls = currentWidth < 420;
        final bool stackedControls = currentWidth < 330;
        final bool iconOnlyControls = currentWidth < 360;
        final double controlRowHeight = stackedControls
            ? 92
            : (compactControls ? 42 : 48);
        _areaWidth = currentWidth;
        _areaHeight = constraints.maxHeight.isFinite
            ? (constraints.maxHeight - controlRowHeight - controlRowSpacing)
                  .clamp(0.0, double.infinity)
            : 0;

        if ((_lastReportedAreaWidth - _areaWidth).abs() > 0.5) {
          _lastReportedAreaWidth = _areaWidth;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              widget.onAreaWidthChanged?.call(_areaWidth);
            }
          });
        }

        final sizeChanged =
            (_lastObservedWidth - currentWidth).abs() > 0.5 ||
            (_lastObservedHeight - _areaHeight).abs() > 0.5;
        if (_pendingPersistedPausedSnapshot != null &&
            !_isRunning &&
            _squares.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            _restorePersistedPausedSnapshotIfReady();
          });
        }

        final previousWidth = _lastObservedWidth;
        final previousHeight = _lastObservedHeight;
        final hadPreviousSize =
            _lastObservedWidth > 0 && _lastObservedHeight > 0;
        final orientationChanged =
            hadPreviousSize &&
            (_lastObservedWidth >= _lastObservedHeight) !=
                (currentWidth >= _areaHeight);
        if (sizeChanged) {
          // Layout-time mutations are deferred to avoid changing state during
          // build. Remapping also keeps paused boards aligned after rotation.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }

            _remapSquaresForAreaChange(
              previousWidth: previousWidth,
              previousHeight: previousHeight,
              newWidth: _areaWidth,
              newHeight: _areaHeight,
            );
            _normalizeSquaresToCurrentGrid();
            if (_isRunning && orientationChanged) {
              _pauseGame();
            }

            _clampSquaresToAreaBounds();
          });
        }
        _lastObservedWidth = currentWidth;
        _lastObservedHeight = _areaHeight;

        if (_squares.isEmpty &&
            !_isLoadingPersistedPausedSnapshot &&
            _pendingPersistedPausedSnapshot == null &&
            _areaWidth > _squareSize &&
            _areaHeight > _squareSize) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _squares.isNotEmpty) {
              return;
            }

            if (!_hasInitializedInjectedSquares &&
                widget.initialSquaresBuilder != null) {
              final injectedSquares = widget.initialSquaresBuilder!(
                _squareSize,
              );
              _hasInitializedInjectedSquares = true;
              if (injectedSquares.isNotEmpty) {
                setState(() {
                  _squares.addAll(injectedSquares);
                });
              }
              return;
            }

            _spawnSquare();
          });
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: controlRowHeight,
              child: Align(
                alignment: Alignment.topRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (iconOnlyControls)
                      IconButton.outlined(
                        onPressed: _startNewGame,
                        icon: const Icon(Icons.refresh),
                        tooltip: 'New Game',
                      )
                    else
                      OutlinedButton.icon(
                        style: compactControls
                            ? OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                              )
                            : null,
                        onPressed: _startNewGame,
                        icon: Icon(
                          Icons.refresh,
                          size: compactControls ? 18 : 24,
                        ),
                        label: Text(
                          'New Game',
                          style: compactControls
                              ? const TextStyle(fontSize: 15)
                              : null,
                        ),
                      ),
                    if (iconOnlyControls)
                      IconButton.filled(
                        onPressed: _toggleRunning,
                        icon: Icon(
                          _isGameOver
                              ? Icons.replay
                              : (_isRunning ? Icons.pause : Icons.play_arrow),
                        ),
                        tooltip: _isGameOver
                            ? 'Restart'
                            : (_isRunning ? 'Pause' : 'Start'),
                      )
                    else
                      ElevatedButton.icon(
                        style: compactControls
                            ? ElevatedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                              )
                            : null,
                        onPressed: _toggleRunning,
                        icon: Icon(
                          _isGameOver
                              ? Icons.replay
                              : (_isRunning ? Icons.pause : Icons.play_arrow),
                          size: compactControls ? 18 : 24,
                        ),
                        label: Text(
                          _isGameOver
                              ? 'Restart'
                              : (_isRunning ? 'Pause' : 'Start'),
                          style: compactControls
                              ? const TextStyle(fontSize: 15)
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: controlRowSpacing),
            Expanded(
              child: SizedBox(
                width: max(_areaWidth, _activePreferredSquareSize * 6),
                height: _areaHeight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: double.infinity,
                    height: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      border: Border.all(color: Colors.black26, width: 2),
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _ColumnGridPainter(
                              squareSize: _squareSize,
                            ),
                          ),
                        ),
                        ..._squares.map((sq) {
                          final canDragSquare = _isRunning && !sq.placed;
                          return Positioned(
                            left: sq.x,
                            top: sq.y,
                            child: MouseRegion(
                              cursor: canDragSquare
                                  ? SystemMouseCursors.grab
                                  : SystemMouseCursors.basic,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanStart: canDragSquare
                                    ? (_) => _startDragging(sq)
                                    : null,
                                onPanUpdate: canDragSquare
                                    ? (details) => _updateDragging(sq, details)
                                    : null,
                                onPanEnd: canDragSquare
                                    ? (_) => _stopDragging(sq)
                                    : null,
                                onTapDown: canDragSquare
                                    ? (_) => _startDragging(sq)
                                    : null,
                                onTapUp: canDragSquare
                                    ? (_) => _stopDragging(sq)
                                    : null,
                                child: Container(
                                  width: sq.size,
                                  height: sq.size,
                                  decoration: BoxDecoration(
                                    color: sq.color,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x40000000),
                                        blurRadius: 6,
                                        offset: Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  alignment: Alignment.center,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: Text(
                                        sq.number.toString(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 28,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                        ..._floatingPoints.map((fp) {
                          return Positioned(
                            left: fp.x - 20,
                            top: fp.y - 20,
                            child: Opacity(
                              opacity: fp.opacity,
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.9),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '+${fp.points}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                        if (_isGameOver)
                          Positioned.fill(
                            child: Container(
                              color: Colors.black.withValues(alpha: 0.55),
                              alignment: Alignment.center,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Game Over',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium
                                        ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'The stack reached the top border.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: Colors.white70),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(
                                    onPressed: _toggleRunning,
                                    icon: const Icon(Icons.replay),
                                    label: const Text('Restart'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _normalizeSquareSpeeds() {
    for (final square in _squares) {
      if (square.speed <= 0) {
        square.speed = 50 + _random.nextDouble() * 35;
      }
    }
  }
}

class _PausedLayoutSnapshot {
  /// Serializable, input-neutral state needed to resume a paused run.
  const _PausedLayoutSnapshot({
    required this.score,
    required this.comboMultiplier,
    required this.isGameOver,
    required this.squares,
  });

  final int score;
  final int comboMultiplier;
  final bool isGameOver;
  final List<FallingSquare> squares;

  Map<String, Object> toJson() {
    return {
      'score': score,
      'comboMultiplier': comboMultiplier,
      'isGameOver': isGameOver,
      'squares': squares
          .map(
            (square) => {
              'x': square.x,
              'y': square.y,
              'size': square.size,
              'color': square.color.toARGB32(),
              'speed': square.speed,
              'number': square.number,
              'landed': square.landed,
              'placed': square.placed,
            },
          )
          .toList(growable: false),
    };
  }

  static _PausedLayoutSnapshot? fromJson(Map<String, dynamic> json) {
    // Reject the entire snapshot when any required field is malformed. A
    // partially restored board could otherwise create impossible collisions.
    final score = json['score'] as int?;
    final comboMultiplier = json['comboMultiplier'] as int?;
    final isGameOver = json['isGameOver'] as bool?;
    final rawSquares = json['squares'];

    if (score == null ||
        comboMultiplier == null ||
        isGameOver == null ||
        rawSquares is! List) {
      return null;
    }

    final restoredSquares = <FallingSquare>[];
    for (final item in rawSquares) {
      if (item is! Map<String, dynamic>) {
        return null;
      }

      final x = (item['x'] as num?)?.toDouble();
      final y = (item['y'] as num?)?.toDouble();
      final size = (item['size'] as num?)?.toDouble();
      final color = item['color'] as int?;
      final speed = (item['speed'] as num?)?.toDouble();
      final number = item['number'] as int?;
      final landed = item['landed'] as bool?;
      final placed = item['placed'] as bool?;

      if (x == null ||
          y == null ||
          size == null ||
          color == null ||
          speed == null ||
          number == null ||
          landed == null ||
          placed == null) {
        return null;
      }

      restoredSquares.add(
        FallingSquare(
          x: x,
          y: y,
          size: size,
          color: Color(color),
          speed: speed,
          number: number,
          landed: landed,
          placed: placed,
          dragging: false,
        ),
      );
    }

    return _PausedLayoutSnapshot(
      score: score,
      comboMultiplier: comboMultiplier,
      isGameOver: isGameOver,
      squares: restoredSquares,
    );
  }
}

class _ColumnGridPainter extends CustomPainter {
  _ColumnGridPainter({required this.squareSize});

  final double squareSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (squareSize <= 0) return;

    final paint = Paint()
      ..color = Colors.black12
      ..strokeWidth = 1.0;

    double x = squareSize;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      x += squareSize;
    }
  }

  @override
  bool shouldRepaint(_ColumnGridPainter oldDelegate) {
    // Board size alone does not affect line positions; grid cell size does.
    return oldDelegate.squareSize != squareSize;
  }
}
