import 'dart:async';

import 'package:flutter/material.dart';
import 'package:squarenumber/app/main_app.dart';
import 'package:squarenumber/app/splash_screen.dart';

/// Starts the lightweight bootstrap that owns the timed splash transition.
void main() {
  runApp(const SquareNumberBootstrap());
}

/// Displays the splash screen before replacing it with the stateful main app.
class SquareNumberBootstrap extends StatefulWidget {
  const SquareNumberBootstrap({super.key});

  @override
  State<SquareNumberBootstrap> createState() => _SquareNumberBootstrapState();
}

class _SquareNumberBootstrapState extends State<SquareNumberBootstrap> {
  static const _splashDuration = Duration(seconds: 3);

  Timer? _splashTimer;
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    // Keep splash timing outside SplashScreen so that screen remains purely
    // presentational and cannot accidentally construct the main app twice.
    _splashTimer = Timer(_splashDuration, () {
      if (mounted) {
        setState(() => _showSplash = false);
      }
    });
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: SplashScreen(),
      );
    }

    return const MainApp();
  }
}
