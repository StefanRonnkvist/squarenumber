import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:squarenumber/features/game/widgets/falling_squares_area.dart';
import 'package:squarenumber/features/settings/widgets/settings_tab.dart';

/// Top-level application shell that coordinates layout, settings, and scores.
class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> with TickerProviderStateMixin {
  static const String _scoreHistoryStorageKey = 'score_history';
  static const String _bestScoreStorageKey = 'best_score';
  static const int _maxScoreHistoryEntries = 10;
  static const double _minSpeed = 0.2;
  static const double _maxSpeed = 1.5;
  static const double _speedStep = 0.1;
  static const int _pointsPerSpeedStep = 500;
  static const int _fixedColumnsAcross = 5;

  double _speedMultiplier = 0.6;
  int _minNumber = 1;
  int _maxNumber = 20;
  double? _customSquareSize;
  double _currentGameAreaWidth = 0;
  int _currentScore = 0;
  int _bestScore = 0;
  final List<ScoreHistoryEntryData> _scoreHistory = [];
  ThemeMode _themeMode = ThemeMode.system;
  bool _isGameRunning = false;
  bool _isGameOver = false;
  late final TabController _phoneTabController;
  bool _isGameTabActive = true;

  @override
  void initState() {
    super.initState();
    _phoneTabController = TabController(length: 2, vsync: this);
    _loadPersistedScoreState();
    _phoneTabController.addListener(() {
      final isGameTab = _phoneTabController.index == 0;
      if (_isGameTabActive != isGameTab) {
        setState(() {
          _isGameTabActive = isGameTab;
        });
      }
    });
  }

  Future<void> _loadPersistedScoreState() async {
    // History entries are stored independently so a missing/corrupt entry
    // cannot prevent the separately persisted best score from loading.
    final preferences = await SharedPreferences.getInstance();
    final persistedBestScore = preferences.getInt(_bestScoreStorageKey);
    final rawEntries = preferences.getStringList(_scoreHistoryStorageKey);

    if (persistedBestScore != null && persistedBestScore > 0 && mounted) {
      setState(() {
        _bestScore = persistedBestScore;
      });
    }

    if (rawEntries == null || rawEntries.isEmpty || !mounted) {
      return;
    }

    final loadedEntries = <ScoreHistoryEntryData>[];
    for (final rawEntry in rawEntries) {
      try {
        final decoded = jsonDecode(rawEntry);
        if (decoded is Map<String, dynamic>) {
          loadedEntries.add(ScoreHistoryEntryData.fromJson(decoded));
        }
      } catch (_) {
        continue;
      }
    }

    if (loadedEntries.isEmpty) {
      return;
    }

    final normalizedEntries = _normalizedScoreHistory(loadedEntries);
    final highestLoadedScore = normalizedEntries.fold<int>(0, (highest, entry) {
      return entry.score > highest ? entry.score : highest;
    });

    if (mounted) {
      setState(() {
        _scoreHistory
          ..clear()
          ..addAll(normalizedEntries);
        if (highestLoadedScore > _bestScore) {
          _bestScore = highestLoadedScore;
        }
      });
    }
    if (highestLoadedScore > _bestScore) {
      await _saveBestScore();
    }
  }

  Future<void> _saveScoreHistory() async {
    final preferences = await SharedPreferences.getInstance();
    final serializedEntries = _scoreHistory
        .take(_maxScoreHistoryEntries)
        .map((entry) => jsonEncode(entry.toJson()))
        .toList(growable: false);
    await preferences.setStringList(_scoreHistoryStorageKey, serializedEntries);
    await _saveBestScore();
  }

  Future<void> _saveBestScore() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_bestScoreStorageKey, _bestScore);
  }

  List<ScoreHistoryEntryData> _normalizedScoreHistory(
    Iterable<ScoreHistoryEntryData> entries,
  ) {
    // The leaderboard contract is descending score order with at most ten
    // entries, regardless of the order found in persistent storage.
    final normalizedEntries = entries.toList(growable: false)
      ..sort((left, right) => right.score.compareTo(left.score));
    if (normalizedEntries.length <= _maxScoreHistoryEntries) {
      return normalizedEntries;
    }

    return normalizedEntries
        .take(_maxScoreHistoryEntries)
        .toList(growable: false);
  }

  void _recordCompletedGame(ScoreHistoryEntryData entry) {
    // Stored runs are never marked current; that marker belongs only to the
    // transient entry assembled by _displayScoreHistory.
    final completedEntry = entry.copyWith(isCurrent: false);
    final nextBestScore = entry.score > _bestScore ? entry.score : _bestScore;
    if (nextBestScore != _bestScore) {
      _bestScore = nextBestScore;
      unawaited(_saveBestScore());
    }
    _scoreHistory
      ..add(completedEntry)
      ..sort((left, right) => right.score.compareTo(left.score));
    if (_scoreHistory.length > _maxScoreHistoryEntries) {
      _scoreHistory.removeRange(_maxScoreHistoryEntries, _scoreHistory.length);
    }
  }

  List<ScoreHistoryEntryData> _displayScoreHistory(_ViewportLayout layout) {
    // Preview a positive in-progress score only when it can enter the top ten.
    // This avoids persisting the same run repeatedly while its score changes.
    final entries = _scoreHistory.toList(growable: false);
    if (_currentScore <= 0) {
      return entries;
    }

    final currentEntry = ScoreHistoryEntryData(
      score: _currentScore,
      speedMultiplier: _effectiveSpeedMultiplier,
      layout: _layoutLabel(layout),
      isCurrent: true,
    );

    if (entries.isEmpty) {
      return _normalizedScoreHistory([currentEntry]);
    }

    final hasCurrentEntry = entries.any((entry) => entry.isCurrent);
    if (!hasCurrentEntry) {
      if (entries.length < _maxScoreHistoryEntries ||
          currentEntry.score > entries.last.score) {
        return _normalizedScoreHistory([...entries, currentEntry]);
      }
    }

    return entries;
  }

  @override
  void dispose() {
    _phoneTabController.dispose();
    super.dispose();
  }

  static const double _phoneBreakpoint = 700;
  static const double _tabletBreakpoint = 1100;
  static const double _phoneLikeGameAreaMaxWidth = 210;
  static const double _phoneGameAreaWidthFactor = 0.9;

  _ViewportLayout _layoutForWidth(double width) {
    if (width < _phoneBreakpoint) {
      return _ViewportLayout.phone;
    }
    if (width < _tabletBreakpoint) {
      return _ViewportLayout.tablet;
    }
    return _ViewportLayout.desktop;
  }

  double _effectiveGameAreaWidthForViewport(
    double viewportWidth,
    _ViewportLayout layout,
  ) {
    // Phone boards scale with the viewport; larger layouts intentionally keep
    // the same narrow five-column play surface for consistent gameplay.
    final availableWidth = (viewportWidth - 36).clamp(0.0, viewportWidth);
    if (layout == _ViewportLayout.phone) {
      return availableWidth * _phoneGameAreaWidthFactor;
    }
    return availableWidth.clamp(0.0, _phoneLikeGameAreaMaxWidth);
  }

  String _layoutLabel(_ViewportLayout layout) {
    switch (layout) {
      case _ViewportLayout.phone:
        return 'Phone';
      case _ViewportLayout.tablet:
        return 'Tablet';
      case _ViewportLayout.desktop:
        return 'Desktop';
    }
  }

  double _calculatedSquareSize({required double displayWidth}) {
    final safeDisplayWidth = displayWidth <= 0 ? 1.0 : displayWidth;
    final safeMinSquaresAcross = _fixedColumnsAcross;
    return (safeDisplayWidth / safeMinSquaresAcross).roundToDouble().clamp(
      24.0,
      200.0,
    );
  }

  double get _effectiveSpeedMultiplier {
    // Every score threshold adds one speed step without exceeding game limits.
    final bonusSteps = _currentScore ~/ _pointsPerSpeedStep;
    final bonus = bonusSteps * _speedStep;
    return (_speedMultiplier + bonus).clamp(_minSpeed, _maxSpeed).toDouble();
  }

  int get _highestScoreAchieved {
    var highest = _bestScore;
    if (_currentScore > highest) {
      highest = _currentScore;
    }
    for (final entry in _scoreHistory) {
      if (entry.score > highest) {
        highest = entry.score;
      }
    }
    return highest;
  }

  ThemeData _buildThemeData(Brightness brightness) {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      colorScheme: baseScheme.copyWith(
        surface: isDark ? const Color(0xFF1B1B1F) : const Color(0xFFF7F7F7),
        surfaceContainerHighest: isDark
            ? const Color(0xFF2B2B31)
            : const Color(0xFFE5E1E9),
        onSurface: isDark ? const Color(0xFFE6E1E5) : const Color(0xFF1C1B1F),
        onSurfaceVariant: isDark
            ? const Color(0xFFCAC4D0)
            : const Color(0xFF49454F),
        outline: isDark ? const Color(0xFF938F99) : const Color(0xFF79747E),
      ),
      scaffoldBackgroundColor: isDark
          ? const Color(0xFF121212)
          : const Color(0xFFF2F2F2),
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark
            ? const Color(0xFF1D1B20)
            : const Color(0xFFF8FAFC),
        foregroundColor: isDark
            ? const Color(0xFFE6E1E5)
            : const Color(0xFF1C1B1F),
        titleTextStyle: TextStyle(
          color: isDark ? const Color(0xFFE6E1E5) : const Color(0xFF1C1B1F),
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: isDark ? const Color(0xFFE6E1E5) : const Color(0xFF1C1B1F),
        unselectedLabelColor: isDark
            ? const Color(0xFFCAC4D0)
            : const Color(0xFF49454F),
      ),
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
        bodyColor: isDark ? const Color(0xFFE6E1E5) : const Color(0xFF1C1B1F),
        displayColor: isDark
            ? const Color(0xFFE6E1E5)
            : const Color(0xFF1C1B1F),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: _buildThemeData(Brightness.light),
      darkTheme: _buildThemeData(Brightness.dark),
      home: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final layout = _layoutForWidth(width);
          final estimatedGameAreaWidth = _effectiveGameAreaWidthForViewport(
            width,
            layout,
          );
          final currentDisplayWidth = _currentGameAreaWidth > 0
              ? _currentGameAreaWidth
              : estimatedGameAreaWidth;
          final calculatedSquareSize = _calculatedSquareSize(
            displayWidth: currentDisplayWidth,
          );
          final preferredSquareSize = _customSquareSize ?? calculatedSquareSize;
          return _buildAdaptiveLayout(
            layout: layout,
            preferredSquareSize: preferredSquareSize,
            currentDisplayWidth: currentDisplayWidth,
          );
        },
      ),
    );
  }

  Widget _buildAdaptiveLayout({
    required _ViewportLayout layout,
    required double preferredSquareSize,
    required double currentDisplayWidth,
  }) {
    switch (layout) {
      case _ViewportLayout.phone:
        return _buildPhoneLayout(
          preferredSquareSize: preferredSquareSize,
          currentDisplayWidth: currentDisplayWidth,
        );
      case _ViewportLayout.tablet:
        return _buildTabletLayout(
          preferredSquareSize: preferredSquareSize,
          currentDisplayWidth: currentDisplayWidth,
        );
      case _ViewportLayout.desktop:
        return _buildDesktopLayout(
          preferredSquareSize: preferredSquareSize,
          currentDisplayWidth: currentDisplayWidth,
        );
    }
  }

  Widget _buildPhoneLayout({
    required double preferredSquareSize,
    required double currentDisplayWidth,
  }) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Square Number'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: _buildStatusSummary(compact: true)),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kTextTabBarHeight),
          child: TabBar(
            controller: _phoneTabController,
            tabs: const [
              Tab(text: 'Game'),
              Tab(text: 'Settings'),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _phoneTabController,
        physics: _isGameRunning ? const NeverScrollableScrollPhysics() : null,
        children: [
          _buildGameArea(
            layout: _ViewportLayout.phone,
            preferredSquareSize: preferredSquareSize,
            isActive: _isGameTabActive,
          ),
          _buildSettingsPanel(
            layout: _ViewportLayout.phone,
            currentSquareSize: preferredSquareSize,
            currentDisplayWidth: currentDisplayWidth,
          ),
        ],
      ),
    );
  }

  Widget _buildTabletLayout({
    required double preferredSquareSize,
    required double currentDisplayWidth,
  }) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 84,
        titleSpacing: 24,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Square Number',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            _buildStatusSummary(),
          ],
        ),
      ),
      body: SafeArea(
        minimum: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 5,
              child: _buildGameSurface(
                title: 'Game Board',
                child: _buildGameArea(
                  layout: _ViewportLayout.tablet,
                  preferredSquareSize: preferredSquareSize,
                ),
              ),
            ),
            const SizedBox(width: 20),
            SizedBox(
              width: 360,
              child: _buildSettingsSurface(
                title: 'Settings',
                layout: _ViewportLayout.tablet,
                currentSquareSize: preferredSquareSize,
                currentDisplayWidth: currentDisplayWidth,
                maxContentWidth: 520,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopLayout({
    required double preferredSquareSize,
    required double currentDisplayWidth,
  }) {
    return Scaffold(
      body: SafeArea(
        minimum: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1480),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 7,
                  child: _buildGameSurface(
                    title: 'Square Number',
                    trailing: _buildStatusSummary(),
                    child: _buildGameArea(
                      layout: _ViewportLayout.desktop,
                      preferredSquareSize: preferredSquareSize,
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                SizedBox(
                  width: 420,
                  child: _buildSettingsSurface(
                    title: 'Controls',
                    layout: _ViewportLayout.desktop,
                    currentSquareSize: preferredSquareSize,
                    currentDisplayWidth: currentDisplayWidth,
                    maxContentWidth: 640,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGameArea({
    required _ViewportLayout layout,
    required double preferredSquareSize,
    bool isActive = true,
  }) {
    final gameAreaChild = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: FallingSquaresArea(
        key: const PageStorageKey<String>('game-area'),
        speedMultiplier: _effectiveSpeedMultiplier,
        minNumber: _minNumber,
        maxNumber: _maxNumber,
        preferredSquareSize: preferredSquareSize,
        isActive: isActive,
        onAreaWidthChanged: (value) {
          // Feed the measured board width back into square-size calculation.
          if ((_currentGameAreaWidth - value).abs() < 0.5) {
            return;
          }
          setState(() {
            _currentGameAreaWidth = value;
          });
        },
        onScoreChanged: (score) {
          if (_currentScore == score) {
            return;
          }
          final previousBestScore = _bestScore;
          final nextBestScore = score > previousBestScore
              ? score
              : previousBestScore;
          setState(() {
            _currentScore = score;
            _bestScore = nextBestScore;
          });
          if (nextBestScore != previousBestScore) {
            unawaited(_saveBestScore());
          }
        },
        onRunningChanged: (isRunning) {
          if (_isGameRunning == isRunning) {
            return;
          }
          setState(() {
            _isGameRunning = isRunning;
            if (isRunning) {
              _isGameOver = false;
            }
          });
          if (layout == _ViewportLayout.phone) {
            // Keep phone layout in portrait while running or paused.
            SystemChrome.setPreferredOrientations([
              DeviceOrientation.portraitUp,
            ]);
          } else {
            // Allow all orientations on tablet and desktop layouts.
            SystemChrome.setPreferredOrientations([
              DeviceOrientation.portraitUp,
              DeviceOrientation.portraitDown,
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]);
          }
        },
        onGameOverChanged: (isGameOver) {
          if (_isGameOver == isGameOver) {
            return;
          }
          setState(() {
            _isGameOver = isGameOver;
          });
        },
        onGameCompleted: (score) {
          // The game widget emits once before resetting or entering game-over.
          setState(() {
            _recordCompletedGame(
              ScoreHistoryEntryData(
                score: score,
                speedMultiplier: _effectiveSpeedMultiplier,
                layout: _layoutLabel(layout),
              ),
            );
          });
          unawaited(_saveScoreHistory());
        },
      ),
    );

    final safeAreaPadding = layout == _ViewportLayout.phone
        ? const EdgeInsets.fromLTRB(8, 4, 8, 6)
        : const EdgeInsets.symmetric(horizontal: 12, vertical: 10);

    return SafeArea(
      minimum: safeAreaPadding,
      child: Center(
        child: layout == _ViewportLayout.phone
            ? FractionallySizedBox(
                widthFactor: _phoneGameAreaWidthFactor,
                child: gameAreaChild,
              )
            : ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: _phoneLikeGameAreaMaxWidth,
                ),
                child: gameAreaChild,
              ),
      ),
    );
  }

  Widget _buildSettingsPanel({
    required _ViewportLayout layout,
    required double currentSquareSize,
    required double currentDisplayWidth,
    double maxContentWidth = 420,
  }) {
    return SettingsTab(
      speedMultiplier: _speedMultiplier,
      currentScore: _currentScore,
      minNumber: _minNumber,
      maxNumber: _maxNumber,
      squareSize: currentSquareSize,
      themeMode: _themeMode,
      scoreHistory: _displayScoreHistory(layout),
      onClearScoreHistory: () {
        setState(() {
          _scoreHistory.clear();
        });
        _saveScoreHistory();
      },
      maxContentWidth: maxContentWidth,
      onSpeedChanged: (value) {
        setState(() {
          _speedMultiplier = value.clamp(_minSpeed, _maxSpeed);
        });
      },
      onMinNumberChanged: (value) {
        setState(() {
          _minNumber = value < 1 ? 1 : value;
          if (_minNumber >= _maxNumber) {
            _maxNumber = _minNumber + 10;
          }
        });
      },
      onMaxNumberChanged: (value) {
        if (value <= 0) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Invalid Number'),
              content: const Text(
                'The highest number must be a positive number greater than zero.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          return;
        }
        setState(() {
          _maxNumber = value;
          if (_maxNumber <= _minNumber) {
            _minNumber = (_minNumber - 10).clamp(0, _minNumber);
          }
        });
      },
      onSquareSizeChanged: (value) {
        setState(() {
          _customSquareSize = value.clamp(24.0, 200.0);
        });
      },
      onThemeModeChanged: (value) {
        setState(() {
          _themeMode = value;
        });
      },
    );
  }

  Widget _buildGameSurface({
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
      color: colorScheme.onSurface,
      fontWeight: FontWeight.w600,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            blurRadius: 24,
            offset: Offset(0, 10),
            color: Color(0x14000000),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(title, style: titleStyle),
                if (trailing != null) ...[
                  const SizedBox(width: 16),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: trailing,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsSurface({
    required String title,
    required _ViewportLayout layout,
    required double currentSquareSize,
    required double currentDisplayWidth,
    required double maxContentWidth,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
      color: colorScheme.onSurface,
      fontWeight: FontWeight.w600,
    );
    final bodyStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            blurRadius: 24,
            offset: Offset(0, 10),
            color: Color(0x14000000),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: titleStyle),
            const SizedBox(height: 8),
            Text(
              'Adjust pacing, number range, and theme without leaving the game.',
              style: bodyStyle,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _buildSettingsPanel(
                layout: layout,
                currentSquareSize: currentSquareSize,
                currentDisplayWidth: currentDisplayWidth,
                maxContentWidth: maxContentWidth,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusSummary({bool compact = false}) {
    final chips = <Widget>[
      _buildStatusChip('Score: $_currentScore'),
      _buildStatusChip(
        'Speed: ${_effectiveSpeedMultiplier.toStringAsFixed(2)}x',
      ),
      _buildStatusChip('Highest score: $_highestScoreAchieved'),
      if (_isGameOver) _buildStatusChip('Game Over'),
    ];

    if (compact) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            _buildStatusChip('$_currentScore pts'),
            _buildStatusChip('High: $_highestScoreAchieved'),
          ],
        ),
      );
    }

    return Wrap(spacing: 10, runSpacing: 10, children: chips);
  }

  Widget _buildStatusChip(String text) {
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    );
  }
}

enum _ViewportLayout { phone, tablet, desktop }
