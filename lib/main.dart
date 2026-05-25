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


// LAUNCHING / RESTORING STATUS
              if (!pageLoaded || !minSplashFinished || showResumeOverlay)
                AppStatusOverlay(
                  isRestore: !isInitialLaunch || showResumeOverlay,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppStatusOverlay extends StatefulWidget {
  final bool isRestore;

  const AppStatusOverlay({
    super.key,
    required this.isRestore,
  });

  @override
  State<AppStatusOverlay> createState() => _AppStatusOverlayState();
}

class _AppStatusOverlayState extends State<AppStatusOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isRestore
        ? 'RESTORING SESSION'
        : 'LAUNCHING APP';

    final subtitle = widget.isRestore
        ? 'REBUILDING WEB SESSION'
        : 'PREPARING LATEST LAYOUTS';

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xFF030503),
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (_, __) {
                  return CustomPaint(
                    painter: StatusBackgroundPainter(
                      progress: _controller.value,
                    ),
                  );
                },
              ),
            ),

            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 270,
                      height: 270,
                      child: AnimatedBuilder(
                        animation: _controller,
                        builder: (_, __) {
                          return CustomPaint(
                            painter: StatusShieldPainter(
                              progress: _controller.value,
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 22),

                    _GamingTitle(text: title),

                    const SizedBox(height: 12),

                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.orbitron(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.8,
                      ),
                    ),

                    const SizedBox(height: 34),

                    SizedBox(
                      width: 94,
                      height: 94,
                      child: AnimatedBuilder(
                        animation: _controller,
                        builder: (_, __) {
                          return CustomPaint(
                            painter: CircularLoadingPainter(
                              progress: _controller.value,
                            ),
                            child: Center(
                              child: Text(
                                'LOADING',
                                style: GoogleFonts.orbitron(
                                  color: const Color(0xFFB7FF00),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 42),

                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxWidth: 420),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFFB7FF00)
                              .withValues(alpha: 0.62),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFB7FF00)
                                .withValues(alpha: 0.18),
                            blurRadius: 28,
                          ),
                        ],
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: 'BASE LAYOUT ',
                                style: GoogleFonts.orbitron(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.8,
                                ),
                              ),
                              TextSpan(
                                text: 'PRO',
                                style: GoogleFonts.orbitron(
                                  color: const Color(0xFFB7FF00),
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.8,
                                ),
                              ),
                            ],
                          ),
                        ),
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

class _GamingTitle extends StatelessWidget {
  final String text;

  const _GamingTitle({
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: GoogleFonts.orbitron(
            color: const Color(0xFFB7FF00).withValues(alpha: 0.42),
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.2,
            shadows: [
              Shadow(
                color: const Color(0xFFB7FF00).withValues(alpha: 0.85),
                blurRadius: 24,
              ),
            ],
          ),
        ),
        Text(
          text,
          textAlign: TextAlign.center,
          style: GoogleFonts.orbitron(
            color: Colors.white,
            fontSize: 27,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.1,
          ),
        ),
      ],
    );
  }
}

class StatusBackgroundPainter extends CustomPainter {
  final double progress;

  StatusBackgroundPainter({
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.36);

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFB7FF00).withValues(alpha: 0.26),
          const Color(0xFFB7FF00).withValues(alpha: 0.07),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(center: center, radius: 230),
      );

    canvas.drawCircle(center, 230, glowPaint);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = const Color(0xFFB7FF00).withValues(alpha: 0.28);

    for (int i = 0; i < 6; i++) {
      canvas.drawCircle(
        center,
        100 + i * 22,
        ringPaint,
      );
    }

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFB7FF00).withValues(alpha: 0.75);

    for (int i = 0; i < 5; i++) {
      final radius = 118.0 + i * 24;
      final start = progress * 6.28 + i * 0.7;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        0.55,
        false,
        arcPaint,
      );
    }

    final dotPaint = Paint()
      ..color = const Color(0xFFB7FF00).withValues(alpha: 0.82);

    for (int i = 0; i < 55; i++) {
      final angle = i * 0.72 + progress * 0.8;
      final radius = 85 + (i % 12) * 16;

      final p = Offset(
        center.dx + MathHelper.cos(angle) * radius,
        center.dy + MathHelper.sin(angle) * radius,
      );

      canvas.drawCircle(
        p,
        i % 5 == 0 ? 2.2 : 1.2,
        dotPaint,
      );
    }

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.square
      ..color = const Color(0xFFB7FF00).withValues(alpha: 0.42);

    final w = size.width;
    final h = size.height;
    const p = 18.0;
    const l = 72.0;

    canvas.drawLine(const Offset(p, p), const Offset(p + l, p), border);
    canvas.drawLine(const Offset(p, p), const Offset(p, p + l), border);

    canvas.drawLine(Offset(w - p, p), Offset(w - p - l, p), border);
    canvas.drawLine(Offset(w - p, p), Offset(w - p, p + l), border);

    canvas.drawLine(Offset(p, h - p), Offset(p + l, h - p), border);
    canvas.drawLine(Offset(p, h - p), Offset(p, h - p - l), border);

    canvas.drawLine(Offset(w - p, h - p), Offset(w - p - l, h - p), border);
    canvas.drawLine(Offset(w - p, h - p), Offset(w - p, h - p - l), border);
  }

  @override
  bool shouldRepaint(covariant StatusBackgroundPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class StatusShieldPainter extends CustomPainter {
  final double progress;

  StatusShieldPainter({
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFB7FF00).withValues(alpha: 0.5),
          const Color(0xFFB7FF00).withValues(alpha: 0.12),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(center: c, radius: 120),
      );

    canvas.drawCircle(c, 120, glowPaint);

    final shield = Path()
      ..moveTo(c.dx, c.dy - 78)
      ..cubicTo(c.dx - 24, c.dy - 62, c.dx - 58, c.dy - 55, c.dx - 76, c.dy - 48)
      ..lineTo(c.dx - 64, c.dy + 30)
      ..cubicTo(c.dx - 52, c.dy + 70, c.dx - 22, c.dy + 96, c.dx, c.dy + 116)
      ..cubicTo(c.dx + 22, c.dy + 96, c.dx + 52, c.dy + 70, c.dx + 64, c.dy + 30)
      ..lineTo(c.dx + 76, c.dy - 48)
      ..cubicTo(c.dx + 58, c.dy - 55, c.dx + 24, c.dy - 62, c.dx, c.dy - 78)
      ..close();

    canvas.drawShadow(
      shield,
      const Color(0xFFB7FF00),
      22,
      true,
    );

    canvas.drawPath(
      shield,
      Paint()
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
          Rect.fromCircle(center: c, radius: 120),
        ),
    );

    final inner = Path()
      ..moveTo(c.dx, c.dy - 55)
      ..cubicTo(c.dx - 16, c.dy - 44, c.dx - 42, c.dy - 39, c.dx - 54, c.dy - 34)
      ..lineTo(c.dx - 46, c.dy + 20)
      ..cubicTo(c.dx - 36, c.dy + 50, c.dx - 14, c.dy + 70, c.dx, c.dy + 84)
      ..cubicTo(c.dx + 14, c.dy + 70, c.dx + 36, c.dy + 50, c.dx + 46, c.dy + 20)
      ..lineTo(c.dx + 54, c.dy - 34)
      ..cubicTo(c.dx + 42, c.dy - 39, c.dx + 16, c.dy - 44, c.dx, c.dy - 55)
      ..close();

    canvas.drawPath(
      inner,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF123F17),
            Color(0xFF061509),
            Color(0xFF000000),
          ],
        ).createShader(
          Rect.fromCircle(center: c, radius: 95),
        ),
    );

    canvas.drawPath(
      shield,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white.withValues(alpha: 0.86),
    );

    canvas.drawPath(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFFB7FF00),
    );

    final logo = Path()
      ..moveTo(c.dx - 26, c.dy - 34)
      ..lineTo(c.dx - 26, c.dy + 44)
      ..lineTo(c.dx + 24, c.dy + 44)
      ..quadraticBezierTo(c.dx + 48, c.dy + 44, c.dx + 48, c.dy + 18)
      ..quadraticBezierTo(c.dx + 48, c.dy - 6, c.dx + 24, c.dy - 6)
      ..lineTo(c.dx - 26, c.dy - 6)
      ..moveTo(c.dx - 26, c.dy - 34)
      ..lineTo(c.dx + 20, c.dy - 34)
      ..quadraticBezierTo(c.dx + 42, c.dy - 34, c.dx + 42, c.dy - 8);

    canvas.drawPath(
      logo,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 17
        ..strokeJoin = StrokeJoin.miter
        ..strokeCap = StrokeCap.square
        ..color = const Color(0xFFB7FF00).withValues(alpha: 0.24)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    canvas.drawPath(
      logo,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 13
        ..strokeCap = StrokeCap.square
        ..strokeJoin = StrokeJoin.miter
        ..color = const Color(0xFFB7FF00),
    );
  }

  @override
  bool shouldRepaint(covariant StatusShieldPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class CircularLoadingPainter extends CustomPainter {
  final double progress;

  CircularLoadingPainter({
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;

    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = Colors.white.withValues(alpha: 0.12),
    );

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFB7FF00).withValues(alpha: 0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final active = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFB7FF00);

    canvas.drawArc(
      Rect.fromCircle(center: c, radius: radius),
      progress * 6.28,
      1.65,
      false,
      glow,
    );

    canvas.drawArc(
      Rect.fromCircle(center: c, radius: radius),
      progress * 6.28,
      1.65,
      false,
      active,
    );

    final dotPaint = Paint()
      ..color = const Color(0xFFB7FF00);

    for (int i = 0; i < 3; i++) {
      canvas.drawCircle(
        Offset(c.dx - 10 + i * 10, c.dy + 18),
        2,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CircularLoadingPainter oldDelegate) {
    return oldDelegate.progress != progress;
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
