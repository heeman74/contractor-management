import 'package:flutter/material.dart';

/// Splash screen — shown while the app bootstraps and determines auth state.
///
/// In a real app, this is where we'd check stored tokens, validate sessions,
/// and determine if the user should go to onboarding or home.
/// The go_router redirect will automatically navigate away once auth state resolves.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.build_circle_outlined,
              size: 80,
              color: Colors.blue,
            ),
            SizedBox(height: 24),
            Text(
              'ContractorHub',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 16),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
