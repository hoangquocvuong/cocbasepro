// =========================
// (0) IMPORTS
// =========================
import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

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
  bool minSplashFinished = false;
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

    Future.delayed(
      const Duration(milliseconds: 2000),
          () {
        if (!mounted) return;

        setState(() {
          minSplashFinished = true;
        });
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
          isInitialLaunch = false;

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
            pageLoaded &&
            minSplashFinished
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
                (pageLoaded && minSplashFinished)
                    ? 1
                    : 0,

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
            if (!pageLoaded || !minSplashFinished)
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
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 22,
              vertical: 10,
            ),

            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                  SizedBox(
                    width: 190,
                    height: 190,
                    child: CustomPaint(
                      painter: SplashHeroPainter(),
                    ),
                  ),

                  const SizedBox(height: 14),

                  Text(
                    isInitialLaunch ? 'Launching app...' : 'Restoring session...',
                    style: TextStyle(
                      color: Color(0xFFEFFFF5),
                      fontSize: 15,
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
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 22),

                  Container(
                    width: MediaQuery.of(context).size.width * 0.62,
                    height: 12,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: const Color(0xFFB7FF00).withValues(alpha: 0.48),
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

                  const SizedBox(height: 22),

                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: 'BASE LAYOUT ',
                            style: GoogleFonts.orbitron(
                              color: Color(0xFFEFFFF5),
                              fontSize: 27,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0,
                              height: 1,
                            ),
                          ),
                          TextSpan(
                            text: 'PRO',
                            style: GoogleFonts.orbitron(
                              color: Color(0xFFB7FF00),
                              fontSize: 29,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.0,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  Container(
                    width: MediaQuery.of(context).size.width * 0.78,
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          const Color(0xFFB7FF00).withValues(alpha: 0.95),
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
                      color: const Color(0xFFB7FF00).withValues(alpha: 0.96),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.35,
                    ),
                  ),

                  const SizedBox(height: 12),

                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _SplashFeature(icon: Icons.shield_outlined, label: 'DEFEND'),
                      _SplashFeature(icon: Icons.grid_view_rounded, label: 'LAYOUT'),
                      _SplashFeature(icon: Icons.content_copy_rounded, label: 'COPY'),
                    ],
                  ),

                  const SizedBox(height: 10),

                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _SplashFeature(icon: Icons.flash_on_rounded, label: 'FAST'),
                      _SplashFeature(icon: Icons.link_rounded, label: 'LINK'),
                      _SplashFeature(icon: Icons.star_border_rounded, label: 'PRO'),
                    ],
                  ),

                const SizedBox(height: 12),

                SizedBox(
                  width: MediaQuery.of(context).size.width * 0.92,
                  height: 24,
                  child: CustomPaint(
                    painter: BottomHudPainter(),
                  ),
                ),

                ],
              ),
            ),
          ),
        )
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
    return SizedBox(
      width: 102,
      child: Column(
        children: [
          Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFB7FF00).withValues(alpha: 0.9),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFB7FF00).withValues(alpha: 0.32),
                  blurRadius: 22,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Icon(
              icon,
              color: const Color(0xFFB7FF00),
              size: 38,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class SplashHeroPainter extends CustomPainter {

  @override
  void paint(Canvas canvas, Size size) {

    final c =
    Offset(size.width / 2, size.height / 2);

    // ===== GLOW =====
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFB7FF00)
              .withValues(alpha: 0.42),

          const Color(0xFFB7FF00)
              .withValues(alpha: 0.15),

          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: c,
          radius: 100,
        ),
      );

    canvas.drawCircle(c, 100, glowPaint);

    // ===== RINGS =====
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFFB7FF00)
          .withValues(alpha: 0.32);

    canvas.drawCircle(c, 92, ringPaint);
    canvas.drawCircle(c, 72, ringPaint);
    canvas.drawCircle(c, 58, ringPaint);
    canvas.drawCircle(c, 44, ringPaint);

    // ===== HUD ARCS =====
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFB7FF00)
          .withValues(alpha: 0.88);

    canvas.drawArc(
      Rect.fromCircle(center: c, radius: 80),
      -2.9,
      1.05,
      false,
      arcPaint,
    );

    canvas.drawArc(
      Rect.fromCircle(center: c, radius: 70),
      0.2,
      0.9,
      false,
      arcPaint,
    );

    // ===== OUTER SHIELD =====
    final outerShield = Path()

      ..moveTo(c.dx, c.dy - 56)

      ..cubicTo(
        c.dx - 18,
        c.dy - 44,

        c.dx - 40,
        c.dy - 38,

        c.dx - 54,
        c.dy - 34,
      )

      ..lineTo(
        c.dx - 46,
        c.dy + 22,
      )

      ..cubicTo(
        c.dx - 37,
        c.dy + 50,

        c.dx - 16,
        c.dy + 67,

        c.dx,
        c.dy + 82,
      )

      ..cubicTo(
        c.dx + 16,
        c.dy + 67,

        c.dx + 37,
        c.dy + 50,

        c.dx + 46,
        c.dy + 22,
      )

      ..lineTo(
        c.dx + 54,
        c.dy - 34,
      )

      ..cubicTo(
        c.dx + 40,
        c.dy - 38,

        c.dx + 18,
        c.dy - 44,

        c.dx,
        c.dy - 56,
      )

      ..close();

    canvas.drawShadow(
      outerShield,
      const Color(0xFFB7FF00),
      16,
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
          radius: 74,
        ),
      );

    canvas.drawPath(
      outerShield,
      shieldPaint,
    );

    // ===== INNER SHIELD =====
    final innerShield = Path()

      ..moveTo(c.dx, c.dy - 40)

      ..cubicTo(
        c.dx - 12,
        c.dy - 31,

        c.dx - 28,
        c.dy - 27,

        c.dx - 38,
        c.dy - 24,
      )

      ..lineTo(
        c.dx - 32,
        c.dy + 16,
      )

      ..cubicTo(
        c.dx - 26,
        c.dy + 36,

        c.dx - 12,
        c.dy + 49,

        c.dx,
        c.dy + 58,
      )

      ..cubicTo(
        c.dx + 12,
        c.dy + 49,

        c.dx + 26,
        c.dy + 36,

        c.dx + 32,
        c.dy + 16,
      )

      ..lineTo(
        c.dx + 38,
        c.dy - 24,
      )

      ..cubicTo(
        c.dx + 28,
        c.dy - 27,

        c.dx + 12,
        c.dy - 31,

        c.dx,
        c.dy - 40,
      )

      ..close();

    canvas.drawPath(
      innerShield,

      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [

            const Color(0xFF123F17)
                .withValues(alpha: 0.96),

            const Color(0xFF061509)
                .withValues(alpha: 0.98),

            const Color(0xFF000000)
                .withValues(alpha: 0.95),
          ],
        ).createShader(
          Rect.fromCircle(
            center: c,
            radius: 55,
          ),
        ),
    );

    // ===== BORDERS =====
    canvas.drawPath(
      outerShield,

      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..color =
        Colors.white.withValues(alpha: 0.82),
    );

    canvas.drawPath(
      innerShield,

      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFFB7FF00)
            .withValues(alpha: 0.95),
    );

    // ===== GRID =====
    const box = 12.0;
    const gap = 5.0;

    final startX =
        c.dx - (box * 1.5 + gap);

    final startY =
        c.dy - 17;

    for (int y = 0; y < 3; y++) {

      for (int x = 0; x < 3; x++) {

        final rect =
        RRect.fromRectAndRadius(

          Rect.fromLTWH(
            startX +
                x * (box + gap),

            startY +
                y * (box + gap),

            box,
            box,
          ),

          const Radius.circular(3),
        );

        canvas.drawRRect(
          rect,

          Paint()
            ..color =
            const Color(0xFFB7FF00)
                .withValues(alpha: 0.35)

            ..maskFilter =
            const MaskFilter.blur(
              BlurStyle.normal,
              4,
            ),
        );

        canvas.drawRRect(
          rect,

          Paint()
            ..shader =
            const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [

                Color(0xFFE8FF4A),

                Color(0xFFB7FF00),

                Color(0xFF5CCB00),
              ],
            ).createShader(
              rect.outerRect,
            ),
        );
      }
    }

    // ===== PARTICLES =====
    final dotPaint = Paint()
      ..color = const Color(0xFFB7FF00)
          .withValues(alpha: 0.85);

    for (int i = 0; i < 18; i++) {

      final angle = i * 0.58;

      final radius =
          68 + (i % 5) * 5;

      final p = Offset(
        c.dx +
            radius *
                MathHelper.cos(angle),

        c.dy +
            radius *
                MathHelper.sin(angle),
      );

      canvas.drawCircle(
        p,
        1.7,
        dotPaint,
      );
    }

    // ===== SPARKLES =====
    final sparkle = Paint()
      ..color =
      Colors.white.withValues(alpha: 0.9)

      ..strokeWidth = 1.6;

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

    star(
      Offset(c.dx - 54, c.dy - 44),
      7,
    );

    star(
      Offset(c.dx + 50, c.dy + 24),
      6,
    );

    star(
      Offset(c.dx + 28, c.dy - 62),
      5,
    );
  }

  @override
  bool shouldRepaint(
      covariant CustomPainter oldDelegate
      ) {
    return false;
  }
}
class MathHelper {

  static double sin(double x) {
    return _sin(x);
  }

  static double cos(double x) {
    return _sin(x + 1.57079632679);
  }

  static double _sin(double x) {

    const pi = 3.14159265359;

    x = x % (2 * pi);

    if (x > pi) {
      x -= 2 * pi;
    }

    if (x < -pi) {
      x += 2 * pi;
    }

    return x
        - (x * x * x) / 6
        + (x * x * x * x * x) / 120;
  }
}

class BottomHudPainter extends CustomPainter {

  @override
  void paint(Canvas canvas, Size size) {

    final glow = Paint()
      ..color =
      const Color(0xFFB7FF00)
          .withValues(alpha: 0.18)

      ..maskFilter =
      const MaskFilter.blur(
        BlurStyle.normal,
        10,
      );

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color =
      const Color(0xFFB7FF00)
          .withValues(alpha: 0.88);

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color =
      const Color(0xFFD6FF3F);

    final y =
        size.height / 2;

    final w =
        size.width;

    // ===== LEFT HUD =====
    final left = Path()

      ..moveTo(0, y)
      ..lineTo(w * 0.18, y)

      ..lineTo(w * 0.22, y - 7)

      ..lineTo(w * 0.34, y - 7)

      ..lineTo(w * 0.37, y)

      ..lineTo(w * 0.44, y);

    // ===== RIGHT HUD =====
    final right = Path()

      ..moveTo(w, y)
      ..lineTo(w * 0.82, y)

      ..lineTo(w * 0.78, y - 7)

      ..lineTo(w * 0.66, y - 7)

      ..lineTo(w * 0.63, y)

      ..lineTo(w * 0.56, y);

    canvas.drawPath(left, glow);
    canvas.drawPath(right, glow);

    canvas.drawPath(left, line);
    canvas.drawPath(right, line);

    // ===== CENTER CORE =====
    final core = RRect.fromRectAndRadius(

      Rect.fromCenter(
        center: Offset(w / 2, y),
        width: 110,
        height: 16,
      ),

      const Radius.circular(4),
    );

    canvas.drawRRect(
      core,

      Paint()
        ..style = PaintingStyle.fill

        ..shader =
        const LinearGradient(
          colors: [
            Color(0xFF8DFF00),
            Color(0xFFE5FF54),
            Color(0xFF8DFF00),
          ],
        ).createShader(
          Rect.fromCenter(
            center: Offset(w / 2, y),
            width: 110,
            height: 16,
          ),
        ),
    );

    // ===== DASHES =====
    for (int i = 0; i < 9; i++) {

      canvas.drawRRect(

        RRect.fromRectAndRadius(

          Rect.fromLTWH(
            w / 2 - 36 + i * 8,
            y - 5,
            4,
            10,
          ),

          const Radius.circular(1.5),
        ),

        fill,
      );
    }

    // ===== SIDE DOTS =====
    canvas.drawCircle(
      Offset(w * 0.22, y - 7),
      2.2,
      fill,
    );

    canvas.drawCircle(
      Offset(w * 0.78, y - 7),
      2.2,
      fill,
    );
  }

  @override
  bool shouldRepaint(
      covariant CustomPainter oldDelegate
      ) => false;
}