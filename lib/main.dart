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
   FIREBASE BG
========================= */
Future<void> firebaseBgHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

/* =========================
   ADS
========================= */
BannerAd? bannerAd;
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

  await Firebase.initializeApp();

  FirebaseMessaging.onBackgroundMessage(firebaseBgHandler);

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  await MobileAds.instance.initialize();

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
      home: MainScreen(),
    );
  }
}

/* =========================
   MAIN SCREEN (PRO)
========================= */
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with WidgetsBindingObserver {
  late final WebViewController controller;
  late StreamSubscription netSub;

  bool isOffline = false;
  bool isLoading = true;

  int currentIndex = 0;

  final List<String> pages = [
    "https://www.cocbasepro.com",
    "https://www.cocbasepro.com/th17",
    "https://www.cocbasepro.com/builder",
    "https://www.cocbasepro.com/pro",
  ];

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    /* ADS */
    bannerAd = BannerAd(
      size: AdSize.banner,
      adUnitId: 'ca-app-pub-9371341402256787/8085634494',
      request: const AdRequest(),
      listener: BannerAdListener(),
    )..load();

    loadInterstitial();

    /* WEBVIEW */
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF1E88F0))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) async {
            setState(() => isLoading = false);

            /* 🔥 INJECT JS (XỊN NHẤT) */
            await controller.runJavaScript("""
              document.querySelector('header')?.remove();
              document.querySelector('footer')?.remove();
              document.body.style.marginTop='0px';
              document.body.style.paddingBottom='60px';
            """);
          },
          onNavigationRequest: (request) async {
            final uri = Uri.parse(request.url);

            if (uri.scheme == 'http' || uri.scheme == 'https') {
              return NavigationDecision.navigate;
            }

            if (await canLaunchUrl(uri)) {
              await launchUrl(uri,
                  mode: LaunchMode.externalApplication);
            }

            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(pages[0]));

    /* NETWORK */
    netSub = Connectivity().onConnectivityChanged.listen((result) {
      final offline = result.contains(ConnectivityResult.none);

      if (offline != isOffline) {
        setState(() => isOffline = offline);

        if (!offline) controller.reload();
      }
    });

    setupFirebase();
  }

  /* FIREBASE */
  Future<void> setupFirebase() async {
    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission();

    String? token = await messaging.getToken();
    log("FCM TOKEN: $token");

    FirebaseMessaging.onMessage.listen((_) {
      debugPrint("NOTI RECEIVED");
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final url = message.data['url'];
      if (url != null) {
        controller.loadRequest(Uri.parse(url));
      }
    });
  }

  /* LIFECYCLE FIX */
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      try {
        await controller.runJavaScript(
            "document.body.style.opacity='0.99';setTimeout(()=>document.body.style.opacity='1',50);");
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    bannerAd?.dispose();
    netSub.cancel();
    super.dispose();
  }

  /* NAVIGATION */
  void onTab(int index) {
    setState(() {
      currentIndex = index;
      isLoading = true;
    });

    controller.loadRequest(Uri.parse(pages[index]));

    /* show interstitial nhẹ */
    if (index != 0) {
      interstitialAd?.show();
    }
  }

  /* BACK */
  Future<bool> handleBack() async {
    if (await controller.canGoBack()) {
      await controller.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await handleBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1E88F0),

        body: Column(
          children: [
            /* WEBVIEW + REFRESH */
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  controller.reload();
                },
                child: Stack(
                  children: [
                    WebViewWidget(controller: controller),

                    if (isLoading)
                      const Center(
                        child: CircularProgressIndicator(
                            color: Colors.white),
                      ),

                    if (isOffline)
                      Container(
                        color: Colors.black,
                        child: const Center(
                          child: Column(
                            mainAxisAlignment:
                            MainAxisAlignment.center,
                            children: [
                              Icon(Icons.wifi_off,
                                  color: Colors.white,
                                  size: 70),
                              SizedBox(height: 10),
                              Text("No Internet",
                                  style: TextStyle(
                                      color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            /* BOTTOM NAV */
            BottomNavigationBar(
              currentIndex: currentIndex,
              onTap: onTab,
              type: BottomNavigationBarType.fixed,
              items: const [
                BottomNavigationBarItem(
                    icon: Icon(Icons.home), label: "Home"),
                BottomNavigationBarItem(
                    icon: Icon(Icons.shield), label: "TH17"),
                BottomNavigationBarItem(
                    icon: Icon(Icons.build), label: "Builder"),
                BottomNavigationBarItem(
                    icon: Icon(Icons.star), label: "Pro"),
              ],
            ),

            /* BANNER */
            if (bannerAd != null)
              SafeArea(
                top: false,
                child: SizedBox(
                  width: bannerAd!.size.width.toDouble(),
                  height: bannerAd!.size.height.toDouble(),
                  child: AdWidget(ad: bannerAd!),
                ),
              ),
          ],
        ),
      ),
    );
  }
}