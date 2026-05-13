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

  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }

  FirebaseMessaging.onBackgroundMessage(firebaseBgHandler);

  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
  );

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
   SPLASH SCREEN
========================= */
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() =>
      _SplashScreenState();
}

class _SplashScreenState
    extends State<SplashScreen> {

  @override
  void initState() {
    super.initState();

    /* LOAD INTERSTITIAL */
    loadInterstitial();

    /* OPEN WEBVIEW */
    Future.delayed(
      const Duration(milliseconds: 1200),
          () {

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const WebScreen(),
          ),
        );

        /* SHOW INTERSTITIAL */
        Future.delayed(
          const Duration(seconds: 1),
              () {
            interstitialAd?.show();
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
      const Color(0xFF1E88F0),

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
   WEBVIEW SCREEN
========================= */
class WebScreen extends StatefulWidget {
  const WebScreen({super.key});

  @override
  State<WebScreen> createState() =>
      _WebScreenState();
}

class _WebScreenState
    extends State<WebScreen>
    with WidgetsBindingObserver {

  late final WebViewController controller;

  late StreamSubscription<List<ConnectivityResult>>
  netSub;

  bool isOffline = false;

  final String url =
      "https://www.cocbasepro.com";

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance
        .addObserver(this);

    /* =========================
       WEBVIEW
    ========================= */
    controller = WebViewController()

      ..setJavaScriptMode(
        JavaScriptMode.unrestricted,
      )

      ..setBackgroundColor(
        const Color(0xFF1E88F0),
      )

      ..setNavigationDelegate(
        NavigationDelegate(

          onPageFinished: (url) {},

          onNavigationRequest:
              (request) async {

            final uri =
            Uri.parse(request.url);

            /* NORMAL LINKS */
            if (uri.scheme == 'http' ||
                uri.scheme == 'https') {

              return NavigationDecision
                  .navigate;
            }

            /* OPEN EXTERNAL APP */
            if (await canLaunchUrl(uri)) {

              await launchUrl(
                uri,
                mode: LaunchMode
                    .externalApplication,
              );
            }

            return NavigationDecision
                .prevent;
          },
        ),
      )

      ..loadRequest(Uri.parse(url));

    /* =========================
       CONNECTIVITY
    ========================= */
    netSub = Connectivity()
        .onConnectivityChanged
        .listen((results) {

      final offline = results.contains(
        ConnectivityResult.none,
      );

      if (offline != isOffline) {

        setState(() {
          isOffline = offline;
        });

        if (!offline) {
          controller.reload();
        }
      }
    });

    setupFirebase();
  }

  /* =========================
     IOS BLACK SCREEN FIX
  ========================= */
  @override
  void didChangeAppLifecycleState(
      AppLifecycleState state) async {

    if (state ==
        AppLifecycleState.resumed) {

      try {

        await controller.runJavaScript(
          """
          document.body.style.opacity='0.99';
          setTimeout(function(){
            document.body.style.opacity='1';
          },50);
          """,
        );

      } catch (_) {}
    }
  }

  /* =========================
     FIREBASE
  ========================= */
  Future<void> setupFirebase() async {

    FirebaseMessaging messaging =
        FirebaseMessaging.instance;

    await messaging.requestPermission();

    String? token =
    await messaging.getToken();

    log("FCM TOKEN: $token");

    FirebaseMessaging.onMessage
        .listen((message) {

      debugPrint(
        "NOTIFICATION RECEIVED",
      );
    });

    FirebaseMessaging
        .onMessageOpenedApp
        .listen((message) {

      log("OPEN FROM NOTIFICATION");
    });
  }

  /* =========================
     BACK BUTTON
  ========================= */
  Future<bool> handleBack() async {

    if (await controller.canGoBack()) {

      await controller.goBack();

      return false;
    }

    return true;
  }

  @override
  void dispose() {

    WidgetsBinding.instance
        .removeObserver(this);

    netSub.cancel();

    interstitialAd?.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    return PopScope(
      canPop: false,

      onPopInvokedWithResult:
          (didPop, result) async {

        if (didPop) return;

        await handleBack();
      },

      child: Scaffold(

        resizeToAvoidBottomInset: false,

        backgroundColor:
        const Color(0xFF1E88F0),

        body: Stack(
          children: [

            /* WEBVIEW */
            Positioned.fill(
              child: WebViewWidget(
                controller: controller,
              ),
            ),

            /* OFFLINE */
            if (isOffline)
              Container(
                color: Colors.black,

                child: const Center(
                  child: Column(
                    mainAxisAlignment:
                    MainAxisAlignment
                        .center,

                    children: [

                      Icon(
                        Icons.wifi_off,
                        color: Colors.white,
                        size: 70,
                      ),

                      SizedBox(height: 10),

                      Text(
                        "No Internet Connection",
                        style: TextStyle(
                          color:
                          Colors.white,
                          fontSize: 16,
                        ),
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