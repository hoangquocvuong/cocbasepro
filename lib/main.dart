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

    Future.delayed(const Duration(milliseconds: 2200), () {
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

  late final WebViewController controller;
  late StreamSubscription<List<ConnectivityResult>> netSub;

  bool isOffline = false;
  String currentUrl = "";

  final String homeUrl = "https://www.cocbasepro.com";
  Uri get homeUri => Uri.parse(homeUrl);

  int openCount = 0;
  bool hasRequestedReview = false;

  bool isPageLoaded = false;
  bool isReloading = false;

  DateTime lastLoadedTime = DateTime.now();
  DateTime lastReloadTime = DateTime.now();


  // =========================
  // INIT
  // =========================
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    lastReloadTime = DateTime.now();

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF1E88F0))
      ..setNavigationDelegate(_navigation())
      ..loadRequest(homeUri);

    _setupConnectivity();
    _setupFirebase();
  }


  // =========================
  // NAVIGATION
  // =========================
  NavigationDelegate _navigation() {
    return NavigationDelegate(
      onNavigationRequest: (request) async {
        final uri = Uri.parse(request.url);

        if (_isFirebaseNoise(uri)) {
          return NavigationDecision.prevent;
        }

        if (isOffline) return NavigationDecision.prevent;

        if (_isInternal(uri)) {
          currentUrl = uri.toString();
          return NavigationDecision.navigate;
        }

        if (_isBuyMeCoffee(uri)) {
          final ok = await _showDialog();

          if (ok) {
            await launchUrl(uri,
                mode: LaunchMode.externalApplication);
          }

          return NavigationDecision.prevent;
        }

        await launchUrl(uri,
            mode: LaunchMode.externalApplication);

        return NavigationDecision.prevent;
      },

      onPageStarted: (_) {
        isPageLoaded = false;
      },

      onPageFinished: (_) {
        isPageLoaded = true;
        isReloading = false;
        lastLoadedTime = DateTime.now();
        _handleReview();
      },
    );
  }


  // =========================
  // FILTER
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
  // SIMPLE DIALOG (APPSTORE SAFE)
  // =========================
  Future<bool> _showDialog() async {
    if (!mounted) return false;

    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Open link"),
        content: const Text("Open in browser?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Open"),
          ),
        ],
      ),
    ) ?? false;
  }


  // =========================
  // CONNECTIVITY
  // =========================
  void _setupConnectivity() {
    netSub = Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.contains(ConnectivityResult.none);

      if (offline == isOffline) return;
      if (!mounted) return;

      setState(() => isOffline = offline);

      if (!offline) {
        final diff = DateTime.now()
            .difference(lastReloadTime)
            .inSeconds;

        if (diff > 5) {
          _reload();
        }
      }
    });
  }


  // =========================
  // SMART RELOAD (ANTI LOOP)
  // =========================
  Future<void> _reload() async {
    if (isReloading) return;

    final now = DateTime.now();
    final diff = now.difference(lastReloadTime).inSeconds;

    if (diff < 10) return;

    isReloading = true;
    lastReloadTime = now;

    try {
      await controller.runJavaScript("window.location.reload()");
    } catch (_) {
      try {
        await controller.loadRequest(
          currentUrl.isNotEmpty
              ? Uri.parse(currentUrl)
              : homeUri,
        );
      } catch (_) {}
    }

    await Future.delayed(const Duration(seconds: 2));
    isReloading = false;
  }


  // =========================
  // FIX iOS DEAD
  // =========================
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkWebViewAlive();
    }
  }

  Future<void> _checkWebViewAlive() async {
    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;

    final diff = DateTime.now()
        .difference(lastLoadedTime)
        .inSeconds;

    if (diff < 5) return;
    if (!isPageLoaded) return;

    if (diff > 45) {
      _reload();
    }
  }


  // =========================
  // REVIEW
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
  // FIREBASE
  // =========================
  Future<void> _setupFirebase() async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();

    final token = await messaging.getToken();
    log("FCM: $token");
  }


  // =========================
  // BACK
  // =========================
  Future<void> _back() async {
    if (await controller.canGoBack()) {
      await controller.goBack();
    }
  }


  // =========================
  // DISPOSE
  // =========================
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    netSub.cancel();
    interstitialAd?.dispose();
    super.dispose();
  }


  // =========================
  // UI
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off,
                          size: 48, color: Colors.white70),
                      const SizedBox(height: 12),
                      const Text("No Internet",
                          style: TextStyle(color: Colors.white)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => controller.reload(),
                        child: const Text("Retry"),
                      )
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}