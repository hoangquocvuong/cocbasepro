// =========================
// (1) IMPORTS
// =========================
import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:webview_flutter/webview_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:in_app_review/in_app_review.dart';


// =========================
// (2) FIREBASE BACKGROUND
// =========================
Future<void> firebaseBgHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}


// =========================
// (3) ADMOB
// =========================
InterstitialAd? interstitialAd;

void loadInterstitial() {
  InterstitialAd.load(
    adUnitId: 'ca-app-pub-9371341402256787/5085734937',
    request: const AdRequest(),
    adLoadCallback: InterstitialAdLoadCallback(
      onAdLoaded: (ad) => interstitialAd = ad,
      onAdFailedToLoad: (error) => debugPrint(error.toString()),
    ),
  );
}


// =========================
// (4) MAIN
// =========================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }

  FirebaseMessaging.onBackgroundMessage(firebaseBgHandler);

  await MobileAds.instance.initialize();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(const MyApp());
}


// =========================
// (5) ROOT APP
// =========================
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SplashScreen(),
    );
  }
}


// =========================
// (6) SPLASH
// =========================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {

  @override
  void initState() {
    super.initState();

    loadInterstitial();

    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WebScreen()),
      );

      Future.delayed(const Duration(milliseconds: 800), () {
        interstitialAd?.show();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF1E88F0),
      body: Center(
        child: Image(
          image: AssetImage("assets/icon.png"),
          width: 240,
        ),
      ),
    );
  }
}


// =========================
// (7) WEBVIEW
// =========================
class WebScreen extends StatefulWidget {
  const WebScreen({super.key});

  @override
  State<WebScreen> createState() => _WebScreenState();
}

class _WebScreenState extends State<WebScreen>
    with WidgetsBindingObserver {

  // (7.1)
  late final WebViewController controller;
  late StreamSubscription<List<ConnectivityResult>> netSub;

  bool isOffline = false;
  String currentUrl = "";

  final String homeUrl = "https://www.cocbasepro.com";
  Uri get homeUri => Uri.parse(homeUrl);

  int openCount = 0;
  bool hasRequestedReview = false;


  // =========================
  // (7.2) INIT
  // =========================
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF1E88F0))
      ..setNavigationDelegate(_navigation())
      ..loadRequest(homeUri);

    _setupConnectivity();
    _setupFirebase();
  }


  // =========================
  // (7.3) NAVIGATION
  // =========================
  NavigationDelegate _navigation() {
    return NavigationDelegate(
      onNavigationRequest: (request) async {
        final uri = Uri.parse(request.url);

        if (_isFirebaseNoise(uri)) {
          return NavigationDecision.prevent;
        }

        if (isOffline) return NavigationDecision.prevent;

        // ✅ INTERNAL
        if (_isInternal(uri)) {
          currentUrl = uri.toString();
          return NavigationDecision.navigate;
        }

        // 🔥 ONLY BUYMEACOFFEE → SHOW DIALOG
        if (_isBuyMeCoffee(uri)) {
          final ok = await _showDonateDialog(uri.toString());

          if (ok) {
            await launchUrl(uri,
                mode: LaunchMode.externalApplication);
          }

          return NavigationDecision.prevent;
        }

        // ✅ ALL OTHER EXTERNAL → OPEN ALWAYS
        await launchUrl(uri,
            mode: LaunchMode.externalApplication);

        return NavigationDecision.prevent;
      },

      onPageFinished: (_) => _handleReview(),
    );
  }


  // =========================
  // (7.4) FILTER
  // =========================
  bool _isFirebaseNoise(Uri uri) {
    final url = uri.toString().toLowerCase();
    return uri.host.contains("firebaseio.com") || url.contains("firebase");
  }

  bool _isInternal(Uri uri) {
    return uri.host.contains("cocbasepro.com");
  }

  bool _isBuyMeCoffee(Uri uri) {
    return uri.host.toLowerCase().contains("buymeacoffee");
  }


  // =========================
  // (7.5) DONATE DIALOG
  // =========================
  Future<bool> _showDonateDialog(String url) async {
    if (!mounted) return false;

    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Open external link"),
        content: const Text(
            "This link will open in your browser."
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Support"),
          ),
        ],
      ),
    ) ??
        false;
  }


  // =========================
  // (7.6) CONNECTIVITY
  // =========================
  void _setupConnectivity() {
    netSub = Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.contains(ConnectivityResult.none);

      if (offline == isOffline) return;

      if (!mounted) return;

      setState(() => isOffline = offline);

      if (!offline) _reload();
    });
  }


  // =========================
  // (7.7) RELOAD FIX
  // =========================
  void _reload() async {
    try {
      await controller.loadRequest(
        currentUrl.isNotEmpty ? Uri.parse(currentUrl) : homeUri,
      );
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reload();
    }
  }


  // =========================
  // (7.8) REVIEW ⭐
  // =========================
  void _handleReview() {
    if (hasRequestedReview) return;

    openCount++;

    if (openCount >= 3) {
      hasRequestedReview = true;
      _requestReview();
    }
  }

  Future<void> _requestReview() async {
    final review = InAppReview.instance;

    if (await review.isAvailable()) {
      await review.requestReview();
    }
  }


  // =========================
  // (7.9) FIREBASE
  // =========================
  Future<void> _setupFirebase() async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();

    final token = await messaging.getToken();
    log("FCM: $token");
  }


  // =========================
  // (7.10) BACK
  // =========================
  Future<void> _back() async {
    if (await controller.canGoBack()) {
      await controller.goBack();
    }
  }


  // =========================
  // (7.11) DISPOSE
  // =========================
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    netSub.cancel();
    interstitialAd?.dispose();
    super.dispose();
  }


  // =========================
  // (7.12) UI
  // =========================
  @override
  // =========================
// (7.12) UI
// =========================
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _back();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1E88F0),
        body: Stack(
          children: [
            SafeArea(
              child: WebViewWidget(controller: controller),
            ),

            if (isOffline)
              Container(
                color: Colors.black.withValues(alpha: 0.85),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.wifi_off,
                          size: 48,
                          color: Colors.white70,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          "No Internet Connection",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Check your connection and try again.",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),

                        // Retry button (nhẹ, không ép user)
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                          ),
                          onPressed: () {
                            controller.reload();
                          },
                          child: const Text("Retry"),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}