import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/auth_service.dart';
import 'login_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _signIn(BuildContext context) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sign-in is not available in the web build.')));
      return;
    }

    final success = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const LoginScreen()));

    if (success == true && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Signed in — API requests now use your account.')));
    }
  }

  Future<void> _signOut() async {
    await AuthService.instance.logout();
    // Also clear the webview's cookie jar so the next sign-in starts fresh.
    try {
      await CookieManager.instance().deleteAllCookies();
    } catch (e) {
      debugPrint('Webview cookie cleanup skipped: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      body: ListenableBuilder(
        listenable: AuthService.instance,
        builder: (context, _) {
          final loggedIn = AuthService.instance.isLoggedIn;

          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    loggedIn ? Icons.verified_user_outlined : Icons.person_outline,
                    size: 64,
                    color: loggedIn ? colorScheme.primary : Colors.grey[600],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    loggedIn ? 'Signed in to F95Zone' : 'Not signed in',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    loggedIn
                        ? 'API requests use your account session.'
                        : 'Anonymous browsing is rate-limited per hour.\nSign in to lift the limit.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[400], fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  if (loggedIn)
                    OutlinedButton.icon(
                      onPressed: _signOut,
                      icon: const Icon(Icons.logout),
                      label: const Text('Sign out'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: () => _signIn(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      ),
                      icon: const Icon(Icons.login),
                      label: const Text('Sign in to F95Zone'),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
