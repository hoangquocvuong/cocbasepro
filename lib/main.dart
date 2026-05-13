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
   BACKGROUND NOTI HANDLER
========================= */
Future<void> firebaseBgHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

/* =========================
   ADMOB
========================= */

late BannerAd bannerAd;
InterstitialAd? interstitialAd;

void loadInterstitial() {
  InterstitialAd.load(
    adUnitId: 'ca-app-pub-9371341402256787/5085734937',
    request: const AdRequest(),
    adLoadCallback: InterstitialAdLoadCallback(
      onAdLoaded: (ad) {
        interstitialAd = ad;
      },
      onAdFailedToLoad: (error) {
        debugPrint(error.toString());
      },
    ),
  );
}

/* =========================
   MAIN
========================= */
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

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

    bannerAd = BannerAd(
      size: AdSize.banner,
      adUnitId: 'ca-app-pub-9371341402256787/8085634494',
      listener: BannerAdListener(),
      request: const AdRequest(),
    )..load();

    loadInterstitial();

    Future.delayed(const Duration(milliseconds: 1800), () {
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
    return Scaffold(
      backgroundColor: const Color(0xFF1E88F0),
      body: Center(
        child: Image.asset(
          "assets/icon.png",
          width: 260,
          height: 260,
        ),
      ),
    );
  }
}

/* =========================
   WEB SCREEN (FIXED FULL)
========================= */
class WebScreen extends StatefulWidget {
  const WebScreen({super.key});

  @override
  State<WebScreen> createState() => _WebScreenState();
}

class _WebScreenState extends State<WebScreen>
    with WidgetsBindingObserver {
  late final WebViewController controller;
  late StreamSubscription netSub;

  bool isOffline = false;
  bool webviewLoaded = false;

  final String url = "https://www.cocbasepro.com";

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF1E88F0))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            if (!webviewLoaded) {
              setState(() => webviewLoaded = true);
            }
          },
          onNavigationRequest: (request) async {
            final uri = Uri.parse(request.url);

            if (uri.scheme == 'http' || uri.scheme == 'https') {
              return NavigationDecision.navigate;
            }

            if (await canLaunchUrl(uri)) {
              await launchUrl(
                uri,
                mode: LaunchMode.externalApplication,
              );
            }

            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(url));

    netSub = Connectivity().onConnectivityChanged.listen((result) {
      final offline = result.contains(ConnectivityResult.none);

      if (offline != isOffline) {
        setState(() => isOffline = offline);

        if (!offline) {
          controller.reload();
        }
      }
    });

    setupFirebase();
  }

  Future<void> setupFirebase() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    await messaging.requestPermission();
    String? token = await messaging.getToken();

    log("FCM TOKEN: $token");

    FirebaseMessaging.onMessage.listen((message) {
      debugPrint("NOTIFICATION RECEIVED");
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      log("OPEN FROM NOTIFICATION");
    });
  }

  Future<bool> handleBack() async {
    if (await controller.canGoBack()) {
      await controller.goBack();
      return false;
    }
    return true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    netSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bannerHeight = bannerAd.size.height.toDouble();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await handleBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1E88F0),

        // =========================
        // WEBVIEW (CÓ CHỖ CHO BANNER)
        // =========================
        body: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.only(bottom: bannerHeight),
                child: WebViewWidget(controller: controller),
              ),
            ),

            if (!webviewLoaded)
              Container(
                color: const Color(0xFF1E88F0),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
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

        // =========================
        // BANNER FIX CHUẨN
        // =========================
        bottomNavigationBar: SafeArea(
          child: SizedBox(
            width: bannerAd.size.width.toDouble(),
            height: bannerHeight,
            child: AdWidget(ad: bannerAd),
          ),
        ),
      ),
    );
  }
}