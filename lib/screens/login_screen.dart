import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/auth_service.dart';

/// In-app browser pointed at the real F95Zone login page. The user signs in
/// normally (captcha and 2FA included); once the long-lived `xf_user`
/// remember-me cookie appears, all f95zone.to cookies are captured into
/// [AuthService] and the screen pops with `true`.
class LoginScreen extends StatefulWidget {
  static const String loginUrl = 'https://f95zone.to/login/';

  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _completed = false;
  double _progress = 0;

  Future<void> _checkForSession() async {
    if (_completed) return;

    final cookies = await CookieManager.instance().getCookies(url: WebUri('https://f95zone.to'));
    final hasUserToken = cookies.any((c) => c.name == 'xf_user');
    if (!hasUserToken) return;

    _completed = true;
    await AuthService.instance.saveCookies({for (final c in cookies) c.name: c.value.toString()});

    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: const Text('Sign in to F95Zone'),
        bottom: _progress < 1.0
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress > 0 ? _progress : null, minHeight: 2),
              )
            : null,
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(LoginScreen.loginUrl)),
        initialSettings: InAppWebViewSettings(
          // The login page renders fine without JS disabled tweaks; keep defaults.
          transparentBackground: true,
        ),
        onProgressChanged: (controller, progress) {
          if (mounted) setState(() => _progress = progress / 100);
        },
        onLoadStop: (controller, url) => _checkForSession(),
      ),
    );
  }
}
