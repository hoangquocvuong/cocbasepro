import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // chạy app trước
  runApp(const MyApp());

  // init ads SAU khi render để tránh iOS black screen
  Future.delayed(const Duration(seconds: 1), () {
    MobileAds.instance.initialize();
  });

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
}

/* =========================
   ROOT APP
========================= */
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(),
    );
  }
}

/* =========================
   SPLASH
========================= */
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AppGate()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Text(
          "COC BASE PRO",
          style: TextStyle(color: Colors.white, fontSize: 22),
        ),
      ),
    );
  }
}

/* =========================
   INTERNET CHECK
========================= */
class AppGate extends StatefulWidget {
  const AppGate({super.key});

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  bool loading = true;
  bool hasInternet = true;

  @override
  void initState() {
    super.initState();
    checkNet();
  }

  Future<void> checkNet() async {
    final result = await Connectivity().checkConnectivity();

    setState(() {
      hasInternet = result != ConnectivityResult.none;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return hasInternet ? const WebScreen() : const NoInternet();
  }
}

/* =========================
   NO INTERNET
========================= */
class NoInternet extends StatelessWidget {
  const NoInternet({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 60),
            const SizedBox(height: 10),
            const Text("No Internet"),
            ElevatedButton(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const AppGate()),
                );
              },
              child: const Text("Retry"),
            )
          ],
        ),
      ),
    );
  }
}

/* =========================
   WEBVIEW SCREEN
========================= */
class WebScreen extends StatefulWidget {
  const WebScreen({super.key});

  @override
  State<WebScreen> createState() => _WebScreenState();
}

class _WebScreenState extends State<WebScreen> {
  late final WebViewController controller;
  bool loading = true;

  final url = "https://www.cocbasepro.com";

  @override
  void initState() {
    super.initState();

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => loading = true),
          onPageFinished: (_) => setState(() => loading = false),
          onNavigationRequest: (request) async {
            final uri = Uri.parse(request.url);

            if (uri.scheme == "http" || uri.scheme == "https") {
              return NavigationDecision.navigate;
            }

            if (await canLaunchUrl(uri)) {
              await launchUrl(uri);
            }

            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            WebViewWidget(controller: controller),

            if (loading)
              const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}