import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

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

  await MobileAds.instance.initialize();

  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
  );

  runApp(const MyApp());
}

/* =========================
   APP
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
  State<SplashScreen> createState() =>
      _SplashScreenState();
}

class _SplashScreenState
    extends State<SplashScreen> {

  @override
  void initState() {
    super.initState();

    loadInterstitial();

    Future.delayed(
      const Duration(milliseconds: 1400),
          () {

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const WebScreen(),
          ),
        );

        Future.delayed(
          const Duration(milliseconds: 800),
              () {

            interstitialAd?.show();

          },
        );
      },
    );
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

/* =========================
   WEBVIEW
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

  final refreshKey = GlobalKey<RefreshIndicatorState>();

  final String homeUrl =
      "https://www.cocbasepro.com";

  bool isOffline = false;

  bool isLoading = true;

  int loadingProgress = 0;

  int openCount = 0;

  bool hasRequestedReview = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    controller = WebViewController()

      ..setJavaScriptMode(
        JavaScriptMode.unrestricted,
      )

      ..setBackgroundColor(
        const Color(0xFF1E88F0),
      )

      ..setNavigationDelegate(
        NavigationDelegate(

          onProgress: (progress) {

            setState(() {
              loadingProgress = progress;
            });
          },

          onPageStarted: (_) {

            setState(() {
              isLoading = true;
            });
          },

          onPageFinished: (url) async {

            setState(() {
              isLoading = false;
            });

            _handleReviewTrigger();

            // 🔥 FIX IMAGE QUALITY
            await controller.runJavaScript("""

document.querySelectorAll('img').forEach(img=>{

img.style.imageRendering='auto';

img.style.backfaceVisibility='hidden';

img.style.transform='translateZ(0)';

});

            """);
          },

          onNavigationRequest:
              (request) async {

            final uri =
            Uri.parse(request.url);

            if (isOffline) {

              return NavigationDecision
                  .prevent;
            }

            if (_isInternal(uri)) {

              return NavigationDecision
                  .navigate;
            }

            // whitelist
            final host = uri.host;

            if (
            host.contains("youtube.com") ||
                host.contains("youtu.be") ||
                host.contains("facebook.com") ||
                host.contains("play.google.com")
            ) {

              await launchUrl(
                uri,
                mode: LaunchMode
                    .externalApplication,
              );

              return NavigationDecision
                  .prevent;
            }

            final ok =
            await _showExternalDialog(
              uri.toString(),
            );

            if (ok) {

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

      ..loadRequest(
        Uri.parse(homeUrl),
      );

    // Android optimize
    if (controller.platform
    is AndroidWebViewController) {

      AndroidWebViewController
          .enableDebugging(false);

      final androidController =
      controller.platform
      as AndroidWebViewController;

      androidController
          .setMediaPlaybackRequiresUserGesture(
        false,
      );
    }

    // connectivity
    netSub = Connectivity()
        .onConnectivityChanged
        .listen((results) {

      final offline =
      results.contains(
        ConnectivityResult.none,
      );

      if (offline == isOffline) return;

      setState(() {
        isOffline = offline;
      });

      if (!offline) {
        controller.reload();
      }
    });

    setupFirebase();
  }

  /* =========================
     APP RESUME
  ========================= */
  @override
  void didChangeAppLifecycleState(
      AppLifecycleState state) {

    if (state ==
        AppLifecycleState.resumed) {

      controller.runJavaScript(
        "window.dispatchEvent(new Event('focus'));",
      );
    }
  }

  /* =========================
     REVIEW
  ========================= */
  void _handleReviewTrigger() {

    if (hasRequestedReview) return;

    openCount++;

    if (openCount >= 4) {

      hasRequestedReview = true;

      Future.delayed(
        const Duration(seconds: 2),
            () {
          _requestReview();
        },
      );
    }
  }

  Future<void> _requestReview() async {

    try {

      final review =
          InAppReview.instance;

      if (await review.isAvailable()) {

        await review.requestReview();
      }

    } catch (_) {}
  }

  /* =========================
     HELPERS
  ========================= */
  bool _isInternal(Uri uri) {

    return uri.host
        .contains("cocbasepro.com");
  }

  Future<bool> _showExternalDialog(
      String url) async {

    final result =
    await showDialog<bool>(

      context: context,

      builder: (ctx) => AlertDialog(

        title:
        const Text("Open external link"),

        content: Text(url),

        actions: [

          TextButton(
            onPressed: () {
              Navigator.pop(ctx, false);
            },
            child: const Text("Cancel"),
          ),

          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx, true);
            },
            child: const Text("Open"),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  Future<void> setupFirebase() async {

    final messaging =
        FirebaseMessaging.instance;

    await messaging.requestPermission();

    final token =
    await messaging.getToken();

    debugPrint("FCM READY");
  }

  Future<void> handleBack() async {

    if (await controller.canGoBack()) {

      await controller.goBack();

    } else {

      SystemNavigator.pop();
    }
  }

  Future<void> refreshPage() async {

    await controller.reload();
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
          (didPop, _) async {

        if (!didPop) {

          await handleBack();
        }
      },

      child: Scaffold(

        backgroundColor:
        const Color(0xFF1E88F0),

        body: SafeArea(

          child: Stack(

            children: [

              RefreshIndicator(

                onRefresh: refreshPage,

                child: WebViewWidget(
                  controller: controller,
                ),
              ),

              // loading
              if (isLoading)

                LinearProgressIndicator(
                  value:
                  loadingProgress / 100,
                  minHeight: 3,
                ),

              // offline
              if (isOffline)

                Container(

                  color: Colors.white,

                  alignment: Alignment.center,

                  child: const Text(
                    "No Internet Connection",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight:
                      FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}