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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ===== STATUS BAR STYLE =====
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(

      // TOP STATUS BAR
      statusBarColor:
      Color(0xFF101A08),

      // ANDROID ICONS
      statusBarIconBrightness: Brightness.light,

      // IOS ICONS
      statusBarBrightness: Brightness.light,

      // ANDROID NAVIGATION BAR
      systemNavigationBarColor:
      Color(0xFF050505),

      systemNavigationBarIconBrightness:
      Brightness.light,
    ),
  );

  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase error: $e');
  }

  FirebaseMessaging.onBackgroundMessage(
    firebaseBgHandler,
  );

  await MobileAds.instance.initialize();

  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
  );

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
      backgroundColor: Color(0xFF050505),
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
  Timer? _badgeDebounce;
  bool appJustResumed = false;
  bool showResumeOverlay = false;
  bool isInitialLaunch = true;

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
        Platform.isIOS ? 'CocBaseProApp-iOS' : null,
      )

      ..setBackgroundColor(
        const Color(0xFF050505),
      )

    // 🔥 JS CHANNEL (giữ nguyên)
      ..addJavaScriptChannel(
        'Flutter',
        onMessageReceived: (message) {
          final newCount = int.tryParse(message.message) ?? 0;

          _badgeDebounce?.cancel();

          _badgeDebounce = Timer(
            const Duration(milliseconds: 300),
                () {
              if (!mounted) return;

              if (newCount == unreadNews) return;

              setState(() {
                unreadNews = newCount;
              });

              debugPrint("🔥 badge updated = $unreadNews");
            },
          );
        },
      )

      ..setNavigationDelegate(_navigation())

      ..loadRequest(Uri.parse(currentUrl));

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
            showResumeOverlay = false;
            isInitialLaunch = false;
            isHomePage =
                url == homeUrl ||
                    url == '$homeUrl/';
          });

          await Future.delayed(
            const Duration(milliseconds: 500),
          );

          // ===== REFRESH BADGE =====
          await _refreshNewsBadge();


          // ===== THEME SYNC =====
          await _syncNavTheme();

          // ===== REVIEW =====
          _handleReview();
        }
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

        if(mounted){
          setState(() {
            showResumeOverlay = true;
          });
        }

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
      await controller.runJavaScriptReturningResult("""
document.readyState
""").timeout(
        const Duration(seconds: 4),
      );

      final state = result.toString();

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

    if (mounted) {
      setState(() {
        showResumeOverlay = false;
      });
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
        await controller.runJavaScriptReturningResult(
          'document.readyState',
        );

        if (mounted) {
          setState(() {
            showResumeOverlay = false;
          });
        }

        return;
      } catch (_) {}
    }

    try {

      if (mounted) {
        setState(() {
          pageLoaded = false;
          showResumeOverlay = true;
        });
      }

      _createWebView();

    } catch (_) {

      if (mounted) {
        setState(() {
          showResumeOverlay = false;
        });
      }

    }
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
  // =========================
  Future<void> _setupFirebase() async {
    final messaging =
        FirebaseMessaging.instance;

    final settings =
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    log(
      'Permission: ${settings.authorizationStatus}',
    );

    await messaging.subscribeToTopic(
      'all',
    );

    log(
      'Subscribed topic: all',
    );

    final token =
    await messaging.getToken();

    log(
      'FCM TOKEN: $token',
    );

    FirebaseMessaging.onMessage.listen(
          (RemoteMessage message) {

        log(
            'Foreground: '
                '${message.notification?.title}'
        );

      },
    );
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
// REFRESH NEWS BADGE
// =========================
  Future<void> _refreshNewsBadge() async {

    for (int i = 0; i < 10; i++) {

      try {

        final result =
        await controller
            .runJavaScriptReturningResult("""
(() => {

  const el =
      document.getElementById(
        'news-count'
      );

  if(!el) return -1;

  const txt =
      (el.textContent || '')
      .replace(/[^0-9]/g,'');

  return txt
      ? parseInt(txt,10)
      : 0;

})();
""");

        final count =
        int.tryParse(
          result
              .toString()
              .replaceAll(
            RegExp(r'[^0-9-]'),
            '',
          ),
        );

        if(count != null &&
            count >= 0){

          if(!mounted) return;

          if(count != unreadNews){

            setState(() {
              unreadNews = count;
            });

          }

          debugPrint(
              "🔥 badge refreshed = $unreadNews"
          );

          return;
        }

      } catch (_) {}

      await Future.delayed(
        const Duration(
          milliseconds: 500,
        ),
      );
    }
  }

  // =========================
  // (7.12) DISPOSE
  // =========================
  @override
  void dispose() {
    _badgeDebounce?.cancel();
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


        // SAVED
          case 2:
            await controller.runJavaScript("""
document.getElementById(
'bookmark-target'
)?.click();
""");
            break;

        // STATS
          case 3:
            await controller.runJavaScript("""
document.querySelector(
'[data-popup="top"]'
)?.click();
""");
            break;

        // SETTINGS
          case 4:
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
        const Color(0xFF050505),

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
        // ======================
// BODY
// ======================
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(

            // TOP SAFE AREA
            statusBarColor:
            Color(0xFF101A08),

            // ANDROID ICON
            statusBarIconBrightness:
            Brightness.light,

            // IOS ICON
            statusBarBrightness:
            Brightness.dark,

            // NAV BAR
            systemNavigationBarColor:
            Color(0xFF050505),

            systemNavigationBarIconBrightness:
            Brightness.light,
          ),

          child: Stack(
            children: [

              // ===== TOP SAFE AREA BG =====
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height:
                MediaQuery.of(context)
                    .padding
                    .top,

                child: Container(
                  color:
                  const Color(0xFF1E88F0),
                ),
              ),


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

            // SPLASH / RESTORE LOADING
            if (!pageLoaded)
        Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF020804),
              Color(0xFF061006),
              Color(0xFF000000),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 300,
                    height: 300,
                    child: CustomPaint(
                      painter: SplashHeroPainter(),
                    ),
                  ),

                  const SizedBox(height: 18),

                  Text(
                    isInitialLaunch
                        ? 'Launching app...'
                        : 'Restoring session...',
                    style: const TextStyle(
                      color: Color(0xFFB7FF00),
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    isInitialLaunch
                        ? 'Loading latest Clash layouts'
                        : 'Refreshing latest content',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 24),

                  Container(
                    width: 250,
                    height: 12,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: const Color(0xFFB7FF00).withValues(alpha: 0.42),
                      ),
                      color: Colors.black.withValues(alpha: 0.38),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 8,
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        color: const Color(0xFFB7FF00),
                      ),
                    ),
                  ),

                  const SizedBox(height: 36),

                  RichText(
                    textAlign: TextAlign.center,
                    text: const TextSpan(
                      children: [
                        TextSpan(
                          text: 'BASE LAYOUT ',
                          style: TextStyle(
                            color: Color(0xFFEFFFF5),
                            fontSize: 31,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.1,
                          ),
                        ),
                        TextSpan(
                          text: 'PRO',
                          style: TextStyle(
                            color: Color(0xFFB7FF00),
                            fontSize: 31,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.1,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  Container(
                    width: 210,
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          const Color(0xFFB7FF00).withValues(alpha: 0.9),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  Text(
                    'Smart layouts. Fast copy. Better defense.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: const Color(0xFFB7FF00).withValues(alpha: 0.95),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),

                  const SizedBox(height: 30),

                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _SplashFeature(
                        icon: Icons.verified_user_outlined,
                        label: 'PROTECT',
                      ),
                      SizedBox(width: 34),
                      _SplashFeature(
                        icon: Icons.grid_view_rounded,
                        label: 'ORGANIZE',
                      ),
                      SizedBox(width: 34),
                      _SplashFeature(
                        icon: Icons.flash_on_rounded,
                        label: 'PERFORM',
                      ),
                    ],
                  ),
                ],
              ),
            ),
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

class _SplashFeature extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SplashFeature({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          icon,
          color: const Color(0xFFB7FF00),
          size: 34,
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.78),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
      ],
    );
  }
}

class SplashHeroPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFB7FF00).withValues(alpha: 0.45),
          const Color(0xFFB7FF00).withValues(alpha: 0.16),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: c,
          radius: 145,
        ),
      );

    canvas.drawCircle(c, 145, glowPaint);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..color = const Color(0xFFB7FF00).withValues(alpha: 0.32);

    canvas.drawCircle(c, 126, ringPaint);
    canvas.drawCircle(c, 108, ringPaint);
    canvas.drawCircle(c, 88, ringPaint);
    canvas.drawCircle(c, 68, ringPaint);

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFB7FF00).withValues(alpha: 0.9);

    canvas.drawArc(
      Rect.fromCircle(center: c, radius: 128),
      -2.95,
      1.1,
      false,
      arcPaint,
    );

    canvas.drawArc(
      Rect.fromCircle(center: c, radius: 116),
      0.2,
      0.95,
      false,
      arcPaint,
    );

    // ===== OUTER SHIELD - giống ảnh hơn =====
    final outerShield = Path()
      ..moveTo(c.dx, c.dy - 88)
      ..cubicTo(
        c.dx - 24,
        c.dy - 68,
        c.dx - 56,
        c.dy - 58,
        c.dx - 78,
        c.dy - 52,
      )
      ..lineTo(c.dx - 68, c.dy + 34)
      ..cubicTo(
        c.dx - 54,
        c.dy + 72,
        c.dx - 24,
        c.dy + 96,
        c.dx,
        c.dy + 108,
      )
      ..cubicTo(
        c.dx + 24,
        c.dy + 96,
        c.dx + 54,
        c.dy + 72,
        c.dx + 68,
        c.dy + 34,
      )
      ..lineTo(c.dx + 78, c.dy - 52)
      ..cubicTo(
        c.dx + 56,
        c.dy - 58,
        c.dx + 24,
        c.dy - 68,
        c.dx,
        c.dy - 88,
      )
      ..close();

    canvas.drawShadow(
      outerShield,
      const Color(0xFFB7FF00),
      28,
      true,
    );

    final shieldPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFFFFFF),
          Color(0xFFB7FF00),
          Color(0xFF173F13),
          Color(0xFF020804),
        ],
      ).createShader(
        Rect.fromCircle(
          center: c,
          radius: 110,
        ),
      );

    canvas.drawPath(outerShield, shieldPaint);

    // ===== INNER DARK SHIELD =====
    final innerShield = Path()
      ..moveTo(c.dx, c.dy - 65)
      ..cubicTo(
        c.dx - 19,
        c.dy - 50,
        c.dx - 43,
        c.dy - 42,
        c.dx - 58,
        c.dy - 38,
      )
      ..lineTo(c.dx - 50, c.dy + 24)
      ..cubicTo(
        c.dx - 40,
        c.dy + 53,
        c.dx - 18,
        c.dy + 72,
        c.dx,
        c.dy + 82,
      )
      ..cubicTo(
        c.dx + 18,
        c.dy + 72,
        c.dx + 40,
        c.dy + 53,
        c.dx + 50,
        c.dy + 24,
      )
      ..lineTo(c.dx + 58, c.dy - 38)
      ..cubicTo(
        c.dx + 43,
        c.dy - 42,
        c.dx + 19,
        c.dy - 50,
        c.dx,
        c.dy - 65,
      )
      ..close();

    canvas.drawPath(
      innerShield,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF123F17).withValues(alpha: 0.95),
            const Color(0xFF061509).withValues(alpha: 0.98),
            const Color(0xFF000000).withValues(alpha: 0.95),
          ],
        ).createShader(
          Rect.fromCircle(center: c, radius: 80),
        ),
    );

    final whiteBorder = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withValues(alpha: 0.82);

    canvas.drawPath(outerShield, whiteBorder);

    final greenBorder = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFFB7FF00).withValues(alpha: 0.95);

    canvas.drawPath(innerShield, greenBorder);

    // ===== GRID 3x3 =====
    const box = 18.5;
    const gap = 8.0;

    final startX = c.dx - (box * 1.5 + gap);
    final startY = c.dy - 28;

    for (int y = 0; y < 3; y++) {
      for (int x = 0; x < 3; x++) {
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            startX + x * (box + gap),
            startY + y * (box + gap),
            box,
            box,
          ),
          const Radius.circular(4.5),
        );

        canvas.drawRRect(
          rect,
          Paint()
            ..color = const Color(0xFFB7FF00).withValues(alpha: 0.35)
            ..maskFilter = const MaskFilter.blur(
              BlurStyle.normal,
              6,
            ),
        );

        canvas.drawRRect(
          rect,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFE8FF4A),
                Color(0xFFB7FF00),
                Color(0xFF5CCB00),
              ],
            ).createShader(rect.outerRect),
        );
      }
    }

    final dotPaint = Paint()
      ..color = const Color(0xFFB7FF00).withValues(alpha: 0.85);

    for (int i = 0; i < 22; i++) {
      final angle = i * 0.58;
      final radius = 92 + (i % 5) * 9;
      final p = Offset(
        c.dx + radius * MathHelper.cos(angle),
        c.dy + radius * MathHelper.sin(angle),
      );

      canvas.drawCircle(p, 2.1, dotPaint);
    }

    final sparkle = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 2;

    void star(Offset p, double r) {
      canvas.drawLine(
        Offset(p.dx - r, p.dy),
        Offset(p.dx + r, p.dy),
        sparkle,
      );
      canvas.drawLine(
        Offset(p.dx, p.dy - r),
        Offset(p.dx, p.dy + r),
        sparkle,
      );
    }

    star(Offset(c.dx - 74, c.dy - 60), 9);
    star(Offset(c.dx + 68, c.dy + 34), 8);
    star(Offset(c.dx + 38, c.dy - 86), 6);
  }

  @override
  bool shouldRepaint(
      covariant CustomPainter oldDelegate,
      ) {
    return false;
  }
}

class MathHelper {
  static double sin(double x) => _sin(x);
  static double cos(double x) => _sin(x + 1.57079632679);

  static double _sin(double x) {
    const pi = 3.14159265359;
    x = x % (2 * pi);
    if (x > pi) x -= 2 * pi;
    if (x < -pi) x += 2 * pi;
    return x - (x * x * x) / 6 + (x * x * x * x * x) / 120;
  }
}