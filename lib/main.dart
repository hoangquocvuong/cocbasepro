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
          height: 260,
        ),
      ),
    );
  }
}

/* =========================
   WEBVIEW
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

            /* =========================
               INTERNAL LINK (CHO PHÉP)
            ========================= */
            if (_isInternal(uri)) {
              return NavigationDecision.navigate;
            }

            /* =========================
               EXTERNAL LINK (HIỆN POPUP)
            ========================= */
            final ok = await _showExternalDialog(uri.toString());

            if (ok) {
              await launchUrl(
                uri,
                mode: LaunchMode.externalApplication,
              );
            }

            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(homeUri);

    /* =========================
       CONNECTIVITY
    ========================= */
    netSub = Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.contains(ConnectivityResult.none);

      if (offline != isOffline) {
        setState(() => isOffline = offline);

        if (!offline) controller.reload();
      }
    });

    setupFirebase();
  }

  /* =========================
     CHECK INTERNAL DOMAIN
  ========================= */
  bool _isInternal(Uri uri) {
    return uri.host.contains("cocbasepro.com");
  }

  /* =========================
     DIALOG MỞ LINK NGOÀI
  ========================= */
  Future<bool> _showExternalDialog(String url) async {
    if (!mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Open External Link"),
        content: Text(
          "You are leaving the app to open:\n\n$url",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Open"),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  /* =========================
     IOS FIX
  ========================= */
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      try {
        await controller.runJavaScript('''
          document.body.style.opacity='0.99';
          setTimeout(()=>document.body.style.opacity='1',50);
        ''');
      } catch (_) {}
    }
  }

  /* =========================
     FIREBASE
  ========================= */
  Future<void> setupFirebase() async {
    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission();

    final token = await messaging.getToken();
    log("FCM TOKEN: $token");

    FirebaseMessaging.onMessage.listen((_) {
      debugPrint("NOTIFICATION RECEIVED");
    });

    FirebaseMessaging.onMessageOpenedApp.listen((_) {
      log("OPEN FROM NOTIFICATION");
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
            Positioned.fill(
              child: WebViewWidget(controller: controller),
            ),

            if (isOffline)
              Container(
                color: Colors.black,
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.wifi_off,
                          color: Colors.white, size: 70),
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