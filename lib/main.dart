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

// ⭐ ADD
import 'package:in_app_review/in_app_review.dart';

/* =========================
   BACKGROUND NOTIFICATION
========================= */
Future<void> firebaseBgHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

/* =========================
   ADMOB
========================= */
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

/* =========================
   MAIN
========================= */
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }

  FirebaseMessaging.onBackgroundMessage(firebaseBgHandler);

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  await MobileAds.instance.initialize();

  runApp(const MyApp());
}

/* =========================
   ROOT APP
========================= */
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

    loadInterstitial();

    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WebScreen()),
      );

      Future.delayed(const Duration(seconds: 1), () {
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
          width: 260,
        ),
      ),
    );
  }
}

/* =========================
   WEBVIEW PRO MAX + REVIEW
========================= */
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
  bool isDialogShowing = false;

  String currentUrl = "";

  final String homeUrl = "https://www.cocbasepro.com";
  Uri get homeUri => Uri.parse(homeUrl);

  // ⭐ REVIEW CONTROL
  int openCount = 0;
  bool hasRequestedReview = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF1E88F0))
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) async {
            final uri = Uri.parse(request.url);

            // 🔥 BLOCK FIREBASE
            if (_isFirebaseNoise(uri)) {
              return NavigationDecision.prevent;
            }

            if (isOffline) return NavigationDecision.prevent;

            if (_isInternal(uri)) {
              currentUrl = uri.toString();
              return NavigationDecision.navigate;
            }

            if (_isBuyMeCoffee(uri)) {
              final ok = await _showExternalDialog(uri.toString());

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

          // ⭐ trigger review sau khi user dùng web
          onPageFinished: (url) {
            _handleReviewTrigger();
          },
        ),
      )
      ..loadRequest(homeUri);

    netSub = Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.contains(ConnectivityResult.none);

      if (offline == isOffline) return;

      setState(() => isOffline = offline);

      if (offline) {
        _closeAllDialogs();
      }
    });

    setupFirebase();
  }

  /* =========================
     ⭐ REVIEW LOGIC (SMART)
  ========================= */
  void _handleReviewTrigger() {
    if (hasRequestedReview) return;

    openCount++;

    // 👉 chỉ trigger sau 3 lần load trang
    if (openCount >= 3) {
      hasRequestedReview = true;

      Future.delayed(const Duration(seconds: 2), () {
        _requestReview();
      });
    }
  }

  Future<void> _requestReview() async {
    final review = InAppReview.instance;

    if (await review.isAvailable()) {
      review.requestReview();
    } else {
      final uri = Uri.parse(
        "https://play.google.com/store/apps/details?id=YOUR_PACKAGE_NAME",
      );

      await launchUrl(uri,
          mode: LaunchMode.externalApplication);
    }
  }

  /* =========================
     FIREBASE BLOCK
  ========================= */
  bool _isFirebaseNoise(Uri uri) {
    final url = uri.toString().toLowerCase();

    return uri.host.contains("firebaseio.com") ||
        uri.path.contains(".lp") ||
        uri.query.contains("dframe") ||
        url.contains("firebase");
  }

  bool _isInternal(Uri uri) {
    return uri.host.contains("cocbasepro.com");
  }

  bool _isBuyMeCoffee(Uri uri) {
    return uri.host.contains("buymeacoffee.com");
  }

  Future<bool> _showExternalDialog(String url) async {
    if (!mounted || isDialogShowing || isOffline) return false;

    isDialogShowing = true;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Support Creator ❤️"),
        content: Text("Open link?\n\n$url"),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(ctx, rootNavigator: true).pop(false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.of(ctx, rootNavigator: true).pop(true),
            child: const Text("Open"),
          ),
        ],
      ),
    );

    isDialogShowing = false;
    return result ?? false;
  }

  void _closeAllDialogs() {
    if (!mounted) return;

    while (Navigator.canPop(context)) {
      Navigator.pop(context);
    }

    isDialogShowing = false;
  }

  Future<void> setupFirebase() async {
    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission();

    final token = await messaging.getToken();
    log("FCM TOKEN: $token");

    FirebaseMessaging.onMessage.listen((_) {
      if (isOffline) return;
    });
  }

  Future<void> handleBack() async {
    if (await controller.canGoBack()) {
      await controller.goBack();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    netSub.cancel();
    interstitialAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await handleBack();
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
                color: Colors.black,
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.wifi_off, color: Colors.white, size: 70),
                      SizedBox(height: 10),
                      Text(
                        "No Internet Connection",
                        style: TextStyle(color: Colors.white),
                      ),
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