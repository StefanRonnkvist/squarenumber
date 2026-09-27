import 'package:flutter/material.dart';
import 'package:squarenumber/contact/contact_page.dart';
import 'package:squarenumber/contact/submissions_csv_page.dart';

/// Serializable leaderboard row shared by the app shell and settings view.
class ScoreHistoryEntryData {
  const ScoreHistoryEntryData({
    required this.score,
    required this.speedMultiplier,
    required this.layout,
    this.isCurrent = false,
  });

  final int score;
  final double speedMultiplier;
  final String layout;
  final bool isCurrent;

  Map<String, Object> toJson() {
    return {
      'score': score,
      'speedMultiplier': speedMultiplier,
      'layout': layout,
      'isCurrent': isCurrent,
    };
  }

  factory ScoreHistoryEntryData.fromJson(Map<String, dynamic> json) {
    // Tolerant defaults allow older or partially malformed history records to
    // load without discarding the rest of the leaderboard.
    final rawScore = json['score'];
    final rawSpeedMultiplier = json['speedMultiplier'];
    final rawLayout = json['layout'];
    final rawIsCurrent = json['isCurrent'];

    return ScoreHistoryEntryData(
      score: rawScore is int ? rawScore : 0,
      speedMultiplier: rawSpeedMultiplier is num
          ? rawSpeedMultiplier.toDouble()
          : 0,
      layout: rawLayout is String && rawLayout.isNotEmpty
          ? rawLayout
          : 'Unknown',
      isCurrent: rawIsCurrent is bool ? rawIsCurrent : false,
    );
  }

  ScoreHistoryEntryData copyWith({
    int? score,
    double? speedMultiplier,
    String? layout,
    bool? isCurrent,
  }) {
    return ScoreHistoryEntryData(
      score: score ?? this.score,
      speedMultiplier: speedMultiplier ?? this.speedMultiplier,
      layout: layout ?? this.layout,
      isCurrent: isCurrent ?? this.isCurrent,
    );
  }
}

class SettingsTab extends StatefulWidget {
  const SettingsTab({
    super.key,
    required this.speedMultiplier,
    required this.currentScore,
    required this.minNumber,
    required this.maxNumber,
    required this.squareSize,
    required this.themeMode,
    required this.scoreHistory,
    required this.onClearScoreHistory,
    this.maxContentWidth = 420,
    required this.onSpeedChanged,
    required this.onMinNumberChanged,
    required this.onMaxNumberChanged,
    required this.onSquareSizeChanged,
    required this.onThemeModeChanged,
  });

  final double speedMultiplier;
  final int currentScore;
  final int minNumber;
  final int maxNumber;
  final double? squareSize;
  final ThemeMode themeMode;
  final List<ScoreHistoryEntryData> scoreHistory;
  final VoidCallback onClearScoreHistory;
  final double maxContentWidth;
  final ValueChanged<double> onSpeedChanged;
  final ValueChanged<int> onMinNumberChanged;
  final ValueChanged<int> onMaxNumberChanged;
  final ValueChanged<double> onSquareSizeChanged;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  static final Uri _supportContactUri = Uri.parse(
    'https://stefanronnkvist.com/contact.php',
  );

  late final TextEditingController _minNumberController;
  late final TextEditingController _maxNumberController;
  late final FocusNode _minNumberFocusNode;
  late final FocusNode _maxNumberFocusNode;

  @override
  void initState() {
    super.initState();
    _minNumberController = TextEditingController(text: _formattedMinNumber);
    _maxNumberController = TextEditingController(text: _formattedMaxNumber);
    _minNumberFocusNode = FocusNode();
    _maxNumberFocusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant SettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Reflect parent-side range corrections only when doing so will not
    // overwrite text that the user is actively editing.
    final nextMinNumber = _formattedMinNumber;
    if (!_minNumberFocusNode.hasFocus &&
        _minNumberController.text != nextMinNumber) {
      _minNumberController.text = nextMinNumber;
    }

    final nextMaxNumber = _formattedMaxNumber;
    if (!_maxNumberFocusNode.hasFocus &&
        _maxNumberController.text != nextMaxNumber) {
      _maxNumberController.text = nextMaxNumber;
    }
  }

  String get _formattedMinNumber => '${widget.minNumber}';
  String get _formattedMaxNumber => '${widget.maxNumber}';

  @override
  void dispose() {
    _minNumberController.dispose();
    _maxNumberController.dispose();
    _minNumberFocusNode.dispose();
    _maxNumberFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxContentWidth),
        child: DefaultTabController(
          length: 4,
          initialIndex: widget.currentScore == 0 ? 3 : 0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              const TabBar(
                isScrollable: true,
                tabs: [
                  Tab(text: 'Controls'),
                  Tab(text: 'Score History'),
                  Tab(text: 'Information'),
                  Tab(text: 'Help'),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildControlsTab(context),
                    _buildHistoryTab(),
                    _buildInformationTab(context),
                    _buildHelpTab(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlsTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Movement Speed',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Slider(
            value: widget.speedMultiplier,
            min: 0.2,
            max: 1.5,
            divisions: 13,
            label: '${widget.speedMultiplier.toStringAsFixed(2)}x',
            onChanged: widget.onSpeedChanged,
          ),
          const SizedBox(height: 8),
          Text(
            'Current speed: ${widget.speedMultiplier.toStringAsFixed(2)}x',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const Text(
            'Lower values make the squares fall more slowly.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _minNumberController,
            focusNode: _minNumberFocusNode,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Lowest Number',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              final parsed = int.tryParse(value);
              if (parsed != null) {
                widget.onMinNumberChanged(parsed);
              }
            },
            onFieldSubmitted: (value) {
              final parsed = int.tryParse(value);
              if (parsed != null) {
                widget.onMinNumberChanged(parsed);
              }
              setState(() {});
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _maxNumberController,
            focusNode: _maxNumberFocusNode,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Highest Number',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              final parsed = int.tryParse(value);
              if (parsed != null) {
                widget.onMaxNumberChanged(parsed);
              }
            },
            onFieldSubmitted: (value) {
              final parsed = int.tryParse(value);
              if (parsed != null) {
                widget.onMaxNumberChanged(parsed);
              }
              setState(() {});
            },
          ),
          const SizedBox(height: 16),
          Text('Theme Mode', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment<ThemeMode>(
                value: ThemeMode.system,
                label: Text('System'),
                icon: Icon(Icons.brightness_auto),
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.light,
                label: Text('Light'),
                icon: Icon(Icons.light_mode),
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.dark,
                label: Text('Dark'),
                icon: Icon(Icons.dark_mode),
              ),
            ],
            selected: {widget.themeMode},
            onSelectionChanged: (selection) {
              if (selection.isNotEmpty) {
                widget.onThemeModeChanged(selection.first);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    final entries = widget.scoreHistory;
    if (entries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No leaderboard entries yet. Start a run to place a score in the top 10.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 420;
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      'Top scores: ${entries.length}/10',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (compact)
                    IconButton(
                      onPressed: widget.onClearScoreHistory,
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Clear History',
                    )
                  else
                    TextButton.icon(
                      onPressed: widget.onClearScoreHistory,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Clear History'),
                    ),
                ],
              );
            },
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = entries[index];
              final rank = index + 1;
              final colorScheme = Theme.of(context).colorScheme;
              return Card(
                color: item.isCurrent ? colorScheme.secondaryContainer : null,
                child: ListTile(
                  leading: CircleAvatar(child: Text('$rank')),
                  title: Text('Score: ${item.score}'),
                  subtitle: Text(
                    'Game speed: ${item.speedMultiplier.toStringAsFixed(2)}x • ${item.layout}',
                  ),
                  trailing: item.isCurrent
                      ? const Chip(label: Text('Current'))
                      : null,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildInformationTab(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Information',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Send feedback, bug reports, or gameplay questions directly from this tab.',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ContactPage(
            serverUri: _supportContactUri,
            showAppBar: false,
            wrapInScaffold: false,
          ),
          const SizedBox(height: 24),
          Text(
            'Hosted Submissions',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Recent content returned by the host for this app is shown below.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 320,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: const SubmissionsCsvCardsView(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpTab(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'How to Play',
            style: textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Guide each falling square into a match, trigger cascades, and keep the stack below the top border.',
            style: textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.touch_app_outlined),
                    title: Text('Move the active square'),
                    subtitle: Text(
                      'Select Start, then drag the falling square sideways or down. It snaps to one of five columns when released. Placed squares cannot be moved.',
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.grid_on_outlined),
                    title: Text('Make a clear'),
                    subtitle: Text(
                      'Clear 2+ equal squares that touch at an edge or corner. You can also clear 3+ unique consecutive values connected vertically or horizontally.',
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.calculate_outlined),
                    title: Text('Score and build cascades'),
                    subtitle: Text(
                      'A clear scores (sum of its values) x (squares removed). Clears caused by falling squares earn an increasing cascade multiplier until the next square appears.',
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.speed_outlined),
                    title: Text('Survive the rising pace'),
                    subtitle: Text(
                      'Effective speed increases by 0.10x every 500 points, up to 1.50x. The run ends when a placed square extends above the top border.',
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.save_outlined),
                    title: Text('Pause, restore, and restart'),
                    subtitle: Text(
                      'Pause at any time. Moving the app to the background pauses and saves a non-empty board, which is restored paused on your next launch. New Game records a positive score before restarting.',
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.leaderboard_outlined),
                    title: Text('Track your scores'),
                    subtitle: Text(
                      'Score History keeps your 10 best completed runs on this device. A qualifying run appears as Current while you play, and your highest score is saved separately.',
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.tune_outlined),
                    title: Text('Tune the game'),
                    subtitle: Text(
                      'Controls lets you choose base speed, generated number range, and system, light, or dark theme. Changing the number range starts a fresh board.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
