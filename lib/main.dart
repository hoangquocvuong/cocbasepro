// =========================
// (0) IMPORTS
// =========================
import 'dart:async';
import 'dart:developer';
import 'dart:io';
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
// (1) FIREBASE BACKGROUND
// =========================
Future<void> firebaseBgHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

// =========================
// (2) INTERSTITIAL AD
// =========================
InterstitialAd? interstitialAd;

void loadInterstitial() {
  InterstitialAd.load(
    adUnitId: 'ca-app-pub-9371341402256787/5085734937',
    request: const AdRequest(nonPersonalizedAds: true),
    adLoadCallback: InterstitialAdLoadCallback(
      onAdLoaded: (ad) => interstitialAd = ad,
      onAdFailedToLoad: (error) => debugPrint(error.toString()),
    ),
  );
}

// =========================
// (3) MAIN
// =========================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase error: $e');
  }

  FirebaseMessaging.onBackgroundMessage(firebaseBgHandler);

  await MobileAds.instance.initialize();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(const MyApp());
}

// =========================
// (4) APP ROOT
// =========================
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WebScreen(),
    );
  }
}

// =========================
// (5) SPLASH SCREEN
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

    Future.delayed(const Duration(milliseconds: 1600), () {
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
          image: AssetImage('assets/icon.png'),
          width: 240,
        ),
      ),
    );
  }
}

// =========================
// (6) WEB SCREEN
// =========================
class WebScreen extends StatefulWidget {
  const WebScreen({super.key});

  @override
  State<WebScreen> createState() => _WebScreenState();
}

// =========================
// (7) STATE
// =========================
class _WebScreenState extends State<WebScreen>
    with WidgetsBindingObserver {

  late WebViewController controller;
  late StreamSubscription<List<ConnectivityResult>> netSub;

  final homeUrl = 'https://www.cocbasepro.com';

  bool isOffline = false;
  bool isReloading = false;
  bool isHomePage = true;
  Color navBgColor = Colors.white;
  Color navIconColor = Colors.black;
  Timer? themeTimer;
  bool lastDarkMode = false;
  bool pageLoaded = false;
  int unreadNews = 0;
  Timer? newsTimer;
  bool appJustResumed = false;

  String currentUrl = '';

  int openCount = 0;
  bool hasRequestedReview = false;

  // ===== FIX WEBVIEW DIE =====
  bool isCheckingAlive = false;
  DateTime lastPaused = DateTime.now();

  // =========================
// (7.1) INIT
// =========================
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    currentUrl = homeUrl;

    _createWebView();

    _setupConnectivity();
    _setupFirebase();

    // THEME WATCHER
    themeTimer = Timer.periodic(
      const Duration(
        milliseconds: 500,
      ),
          (_) {
        _watchThemeChange();
      },
    );


  }

  // =========================
  // (7.2) CREATE WEBVIEW
  // =========================
  void _createWebView() {
    controller = WebViewController()
      ..setJavaScriptMode(
        JavaScriptMode.unrestricted,
      )

    // APP MODE FOR IOS
      ..setUserAgent(
        Platform.isIOS
            ? 'CocBaseProApp-iOS'
            : null,
      )

      ..setBackgroundColor(
        const Color(0xFF1E88F0),
      )

    // 🔥 THÊM ĐOẠN NÀY Ở ĐÂY
      ..addJavaScriptChannel(
        'UnreadChannel',
        onMessageReceived: (message) {
          final count = int.tryParse(message.message) ?? 0;

          if (!mounted) return;

          setState(() {
            unreadNews = count;
          });
        },
      )

      ..setNavigationDelegate(
        _navigation(),
      )

      ..loadRequest(
        Uri.parse(currentUrl),
      );
  }

  // =========================
  // (7.3) NAVIGATION
  // =========================
  NavigationDelegate _navigation() {
    return NavigationDelegate(
      onNavigationRequest: (request) async {
        final uri = Uri.parse(request.url);

        if (uri.host.contains('firebaseio.com')) {
          return NavigationDecision.prevent;
        }

        if (isOffline) {
          return NavigationDecision.prevent;
        }

        if (uri.host.contains('cocbasepro.com')) {
          currentUrl = uri.toString();
          return NavigationDecision.navigate;
        }

        // BUY ME A COFFEE -> CONFIRM
        if (uri.host.toLowerCase().contains('buymeacoffee')) {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Open link'),
              content: const Text('Open in browser?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Open'),
                )
              ],
            ),
          ) ??
              false;

          if (ok) {
            await launchUrl(uri,
                mode: LaunchMode.externalApplication);
          }

          return NavigationDecision.prevent;
        }

        // OTHER LINKS -> OPEN DIRECT
        await launchUrl(uri,
            mode: LaunchMode.externalApplication);

        return NavigationDecision.prevent;
      },

      onPageFinished: (url) async {

        isReloading = false;

        setState(() {
          pageLoaded = true;
          isHomePage =
              url == homeUrl ||
                  url == '$homeUrl/';
        });

        await _syncNavTheme();

        _handleReview();
      },
    );
  }

  // =========================
  // (7.4) CONNECTIVITY
  // =========================
  void _setupConnectivity() {
    netSub =
        Connectivity().onConnectivityChanged.listen((results) {
          final offline = results.contains(ConnectivityResult.none);

          if (offline == isOffline || !mounted) return;

          setState(() {
            isOffline = offline;
          });
        });
  }

  // =========================
  // (7.5) LIFECYCLE FIX
  // =========================

  @override
  void didChangeAppLifecycleState(
      AppLifecycleState state) {

    if (state == AppLifecycleState.paused) {
      lastPaused = DateTime.now();
    }

    if (state == AppLifecycleState.resumed) {

      appJustResumed = true;

      final diff =
          DateTime.now()
              .difference(lastPaused)
              .inMinutes;

      // chỉ check nếu ngủ lâu
      if (diff >= 10) {
        _safeCheckAlive();
      }

      // resume xong reset cờ
      Future.delayed(
        const Duration(seconds: 5),
            () {
          appJustResumed = false;
        },
      );
    }
  }

  // =========================
  // (7.6) SAFE CHECK
  // =========================
  Future<void> _safeCheckAlive() async {
    if (isCheckingAlive) return;

    isCheckingAlive = true;
    await _checkAlive();
    isCheckingAlive = false;
  }

  // =========================
// (7.7) CHECK WEBVIEW DIE (FAST + STABLE)
// =========================
  Future<void> _checkAlive() async {
    await Future.delayed(
      const Duration(milliseconds: 700),
    );

    if (!mounted) return;

    bool isDead = false;

    try {

      final result =
      await controller
          .runJavaScriptReturningResult("""
document.readyState
""")
          .timeout(
        const Duration(seconds: 4),
      );

      final state =
      result.toString();

      if (!state.contains('complete') &&
          !state.contains('interactive')) {
        isDead = true;
      }

    } catch (_) {
      isDead = true;
    }

    if (isDead) {
      await _forceRecreateWebView();
    }
  }

  // =========================
  // (7.8) FORCE RECREATE
  // =========================
  Future<void> _forceRecreateWebView() async {

    if (!mounted) return;

    // tránh recreate giả sau resume
    if (appJustResumed) {

      await Future.delayed(
        const Duration(seconds: 2),
      );

      try {
        await controller
            .runJavaScriptReturningResult(
          'document.readyState',
        );

        return;
      } catch (_) {}
    }

    try {

      setState(() {
        pageLoaded = false;
      });

      _createWebView();

    } catch (_) {}
  }

  // =========================
  // (7.9) REVIEW
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
  // (7.10) FIREBASE
  // =========================
  Future<void> _setupFirebase() async {
    final messaging = FirebaseMessaging.instance;

    await messaging.requestPermission();

    final token = await messaging.getToken();
    log('FCM:$token');
  }

  // =========================
  // (7.11) BACK
  // =========================
  Future<void> _back() async {
    if (await controller.canGoBack()) {
      await controller.goBack();
    }
  }


  // =========================
  // (7.12) DISPOSE
  // =========================
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    netSub.cancel();
    interstitialAd?.dispose();
    themeTimer?.cancel();
    newsTimer?.cancel();
    super.dispose();
  }

// =========================
// SETTINGS SHEET
// =========================
  void _showSettings() {
    showModalBottomSheet(
      context: context,
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              ListTile(
                leading:
                const Icon(Icons.refresh),

                title:
                const Text('Reload'),

                onTap: () {
                  controller.reload();
                  Navigator.pop(context);
                },
              ),

              ListTile(
                leading:
                const Icon(Icons.star),

                title:
                const Text('Rate App'),

                onTap: () async {
                  final review =
                      InAppReview.instance;

                  if (await review
                      .isAvailable()) {
                    await review
                        .requestReview();
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _syncNavTheme() async {
    try {

      final result =
      await controller
          .runJavaScriptReturningResult("""
(() => {

  // kiểm tra mode thật của blog
  const mode =
      document.documentElement
          .getAttribute('data-mode') ||
      document.body
          .getAttribute('data-mode');

  // fallback theo system
  const prefersDark =
      window.matchMedia(
        '(prefers-color-scheme: dark)'
      ).matches;

  const isDark =
      mode === 'dark'
      || (!mode && prefersDark);

  return isDark ? 'dark' : 'light';
})();
""");

      final isDark =
      result
          .toString()
          .contains('dark');

      if (!mounted) return;

      setState(() {

        // giống website
        navBgColor =
        isDark
            ? const Color(0xFF0F172A)
            : Colors.white
            .withValues(alpha: 0.92);

        navIconColor =
        isDark
            ? Colors.white70
            : Colors.black87;
      });

    } catch (e) {
      debugPrint(
        'Theme sync error: $e',
      );
    }
  }

  Future<void> _watchThemeChange() async {
    try {

      final result =
      await controller
          .runJavaScriptReturningResult("""
(() => {

  const mode =
      document.documentElement
          .getAttribute('data-mode') ||
      document.body
          .getAttribute('data-mode');

  const prefersDark =
      window.matchMedia(
        '(prefers-color-scheme: dark)'
      ).matches;

  const isDark =
      mode === 'dark'
      || (!mode && prefersDark);

  return isDark;
})();
""");

      final isDark =
      result
          .toString()
          .contains('true');

      // chỉ update khi đổi mode
      if (isDark != lastDarkMode &&
          mounted) {

        lastDarkMode = isDark;

        setState(() {
          navBgColor =
          isDark
              ? const Color(0xFF0F172A)
              : Colors.white
              .withValues(
            alpha: 0.92,
          );

          navIconColor =
          isDark
              ? Colors.white70
              : Colors.black87;
        });
      }

    } catch (_) {}
  }



  Widget _homeNav() {
    return BottomNavigationBar(
      backgroundColor:
      navBgColor,

      selectedItemColor:
      navIconColor,

      unselectedItemColor:
      navIconColor
          .withValues(
        alpha: 0.7,
      ),

      type:
      BottomNavigationBarType.fixed,

      onTap: (index) async {

        switch(index){

        // HOME
          case 0:
            await controller
                .runJavaScript("""
window.scrollTo({
  top:0,
  behavior:'smooth'
});
""");
            break;

        // EVENT
          case 1:
            await controller
                .runJavaScript("""
openEventPopup();
""");
            break;

        // TH
          case 2:
            await controller
                .runJavaScript("""
document.querySelectorAll(
'.bottom-nav .nav-item'
)[2]?.click();
""");
            break;

        // BH
          case 3:
            await controller
                .runJavaScript("""
document.querySelectorAll(
'.bottom-nav .nav-item'
)[3]?.click();
""");
            break;

        // CH
          case 4:
            await controller
                .runJavaScript("""
document.querySelectorAll(
'.bottom-nav .nav-item'
)[4]?.click();
""");
            break;
        }
      },

      items: const [

        BottomNavigationBarItem(
          icon: Icon(Icons.home),
          label: 'Home',
        ),

        BottomNavigationBarItem(
          icon: Icon(Icons.event),
          label: 'Event',
        ),

        BottomNavigationBarItem(
          icon: Icon(Icons.castle),
          label: 'TH',
        ),

        BottomNavigationBarItem(
          icon: Icon(Icons.build),
          label: 'BH',
        ),

        BottomNavigationBarItem(
          icon: Icon(Icons.shield),
          label: 'CH',
        ),
      ],
    );
  }
  Widget _articleNav() {
    return BottomNavigationBar(
      backgroundColor:
      navBgColor,

      selectedItemColor:
      navIconColor,

      unselectedItemColor:
      navIconColor
          .withValues(
        alpha: 0.7,
      ),

      type:
      BottomNavigationBarType.fixed,

      onTap: (index) async {

        switch(index){

        // HOME
          case 0:
            await controller.loadRequest(
              Uri.parse(homeUrl),
            );
            break;

        // NEWS
          case 1:
            await controller.runJavaScript("""
document.getElementById(
'nav-news-btn'
)?.click();
""");
            break;

        // DONATE
          case 2:
            await controller.runJavaScript("""
document.querySelector(
'[data-popup="donate"]'
)?.click();
""");
            break;

        // SAVED
          case 3:
            await controller.runJavaScript("""
document.getElementById(
'bookmark-target'
)?.click();
""");
            break;

        // STATS
          case 4:
            await controller.runJavaScript("""
document.querySelector(
'[data-popup="top"]'
)?.click();
""");
            break;

        // SETTINGS
          case 5:
            _showSettings();
            break;
        }
      },

      items: [
        BottomNavigationBarItem(
          icon: Icon(Icons.home),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Badge(
            isLabelVisible: unreadNews > 0,

            label: Text(
              unreadNews > 9
                  ? '9+'
                  : unreadNews.toString(),
            ),

            child: Icon(
              Icons.article,
            ),
          ),
          label: 'News',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.favorite),
          label: 'Donate',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.bookmark),
          label: 'Saved',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.bar_chart),
          label: 'Stats',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings),
          label: 'Settings',
        ),
      ],
    );
  }
  // =========================
// (7.13) UI
// =========================
  @override
  Widget build(BuildContext context) {

    return PopScope(
      canPop: false,

      onPopInvokedWithResult:
          (didPop, _) async {
        if (!didPop) {
          await _back();
        }
      },

      child: Scaffold(
        backgroundColor:
        const Color(0xFF1E88F0),

        // ======================
        // NATIVE BOTTOM NAV
        // ======================
        bottomNavigationBar:
        Platform.isIOS &&
            pageLoaded
            ? (isHomePage
            ? _homeNav()
            : _articleNav())
            : null,
        // ======================
        // BODY
        // ======================
        body: Stack(
          children: [

            // WEBVIEW
            SafeArea(
              child: AnimatedOpacity(
                opacity:
                pageLoaded ? 1 : 0,

                duration:
                const Duration(
                  milliseconds: 250,
                ),

                child: WebViewWidget(
                  controller: controller,
                ),
              ),
            ),

            // SPLASH LOADING
            if (!pageLoaded)
              Container(
                color:
                const Color(
                  0xFF1E88F0,
                ),

                child: const Center(
                  child: Image(
                    image: AssetImage(
                      'assets/icon.png',
                    ),
                    width: 180,
                  ),
                ),
              ),

            // OFFLINE SCREEN
            if (isOffline)
              Container(
                color: Colors.black
                    .withValues(
                  alpha: 0.85,
                ),

                child: Center(
                  child: Column(
                    mainAxisSize:
                    MainAxisSize.min,

                    children: [

                      const Icon(
                        Icons.wifi_off,
                        size: 48,
                        color:
                        Colors.white70,
                      ),

                      const SizedBox(
                        height: 12,
                      ),

                      const Text(
                        'No Internet',
                        style: TextStyle(
                          color:
                          Colors.white,
                        ),
                      ),

                      const SizedBox(
                        height: 12,
                      ),

                      ElevatedButton(
                        onPressed: () {
                          controller.reload();
                        },

                        child:
                        const Text(
                          'Retry',
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