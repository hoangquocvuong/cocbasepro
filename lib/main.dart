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
   WEBVIEW PRO MAX
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

  final String homeUrl = "https://www.cocbasepro.com";

  Uri get homeUri => Uri.parse(homeUrl);

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

            // ❌ OFFLINE → chặn hết
            if (isOffline) return NavigationDecision.prevent;

            // ✅ internal
            if (_isInternal(uri)) {
              return NavigationDecision.navigate;
            }

            // ⭐ chỉ popup với BuyMeCoffee
            if (_isBuyMeCoffee(uri)) {
              final ok = await _showExternalDialog(uri.toString());

              if (ok) {
                await launchUrl(uri,
                    mode: LaunchMode.externalApplication);
              }
              return NavigationDecision.prevent;
            }

            // ✅ link ngoài khác → mở luôn
            await launchUrl(uri,
                mode: LaunchMode.externalApplication);

            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(homeUri);

    /* =========================
       CONNECTIVITY FIX PRO
    ========================= */
    netSub = Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.contains(ConnectivityResult.none);

      if (offline != isOffline) {
        setState(() => isOffline = offline);

        if (offline) {
          _closeAllDialogs(); // 💥 đóng popup
        } else {
          controller.reload();
        }
      }
    });

    setupFirebase();
  }

  bool _isInternal(Uri uri) {
    return uri.host.contains("cocbasepro.com");
  }

  bool _isBuyMeCoffee(Uri uri) {
    return uri.host.contains("buymeacoffee.com");
  }

  /* =========================
     DIALOG (ANTI BUG)
  ========================= */
  Future<bool> _showExternalDialog(String url) async {
    if (!mounted || isDialogShowing || isOffline) return false;

    isDialogShowing = true;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Support Creator ❤️"),
        content: Text("Open support link?\n\n$url"),
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

  /* =========================
     FIREBASE FIX
  ========================= */
  Future<void> setupFirebase() async {
    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission();

    final token = await messaging.getToken();
    log("FCM TOKEN: $token");

    FirebaseMessaging.onMessage.listen((_) {
      if (isOffline) return; // ❌ chặn khi offline
      debugPrint("NOTIFICATION");
    });
  }

  /* =========================
     BACK BUTTON
  ========================= */
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