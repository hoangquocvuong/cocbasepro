import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/* =========================
   ADMOB BANNER
========================= */
class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _bannerAd;
  bool loaded = false;

  @override
  void initState() {
    super.initState();

    _bannerAd = BannerAd(
      size: AdSize.banner,

      // TEST ADS
      adUnitId: Platform.isAndroid
          ? "ca-app-pub-3940256099942544/6300978111"
          : "ca-app-pub-3940256099942544/2934735716",

      request: const AdRequest(),

      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) {
            setState(() {
              loaded = true;
            });
          }
        },

        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    );

    _bannerAd!.load();
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded || _bannerAd == null) {
      return const SizedBox();
    }

    return SizedBox(
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }
}

/* =========================
   NAVIGATOR
========================= */
class AppNavigator {
  static final GlobalKey<NavigatorState> key =
  GlobalKey<NavigatorState>();

  static NavigatorState get nav => key.currentState!;
}

/* =========================
   DIALOG
========================= */
class AppDialog {
  static Future<bool> confirm({
    required String title,
    required String message,
  }) async {
    final context = AppNavigator.key.currentContext;

    if (context == null) return false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx, false);
              },
              child: const Text("No"),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx, true);
              },
              child: const Text("Yes"),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }
}

/* =========================
   MAIN
========================= */
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // FIX IOS BLACK SCREEN
  if (Platform.isIOS) {
    WebViewPlatform.instance = WebKitWebViewPlatform();
  }

  // INIT ADS
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
    return MaterialApp(
      navigatorKey: AppNavigator.key,
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const SplashScreen(),
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

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    Timer(const Duration(seconds: 2), () {
      if (mounted) {
        AppNavigator.nav.pushReplacement(
          MaterialPageRoute(
            builder: (_) => const AppGate(),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Image(
          image: AssetImage("assets/logo.png"),
          width: 140,
        ),
      ),
    );
  }
}

/* =========================
   INTERNET CHECK
========================= */
class AppGate extends StatefulWidget {
  const AppGate({super.key});

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  bool loading = true;
  bool hasInternet = true;

  @override
  void initState() {
    super.initState();
    _checkInternet();
  }

  Future<void> _checkInternet() async {
    final result =
    await Connectivity().checkConnectivity();

    bool connected = false;

    if (result is List<ConnectivityResult>) {
      connected =
      !result.contains(ConnectivityResult.none);
    } else {
      connected = result != ConnectivityResult.none;
    }

    if (!mounted) return;

    setState(() {
      hasInternet = connected;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return hasInternet
        ? const MainScreen()
        : const NoInternet();
  }
}

/* =========================
   NO INTERNET
========================= */
class NoInternet extends StatelessWidget {
  const NoInternet({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment:
          MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.wifi_off,
              color: Colors.white,
              size: 80,
            ),

            const SizedBox(height: 10),

            const Text(
              "No Internet Connection",
              style: TextStyle(
                color: Colors.white,
              ),
            ),

            const SizedBox(height: 15),

            ElevatedButton(
              onPressed: () {
                AppNavigator.nav.pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => const AppGate(),
                  ),
                );
              },
              child: const Text("Retry"),
            ),
          ],
        ),
      ),
    );
  }
}

/* =========================
   MAIN SCREEN
========================= */
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() =>
      _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int index = 0;

  final pages = const [
    WebShell(),
    AboutPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: pages[index],

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,

        onTap: (i) {
          setState(() {
            index = i;
          });
        },

        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: "Home",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.info),
            label: "About",
          ),
        ],
      ),
    );
  }
}

/* =========================
   ABOUT PAGE
========================= */
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          "COC Base Pro\nVersion 1.0.0",
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/* =========================
   WEBVIEW
========================= */
class WebShell extends StatefulWidget {
  const WebShell({super.key});

  @override
  State<WebShell> createState() =>
      _WebShellState();
}

class _WebShellState extends State<WebShell> {
  late final WebViewController controller;

  bool loading = true;
  double progress = 0;

  final String url =
      "https://www.cocbasepro.com";

  @override
  void initState() {
    super.initState();

    controller = WebViewController();

    controller.setJavaScriptMode(
      JavaScriptMode.unrestricted,
    );

    controller.setBackgroundColor(
      const Color(0x00000000),
    );

    controller.setUserAgent(
      "cocbasepro_app",
    );

    controller.setNavigationDelegate(
      NavigationDelegate(
        onProgress: (p) {
          if (mounted) {
            setState(() {
              progress = p / 100;
            });
          }
        },

        onPageStarted: (_) {
          if (mounted) {
            setState(() {
              loading = true;
            });
          }
        },

        onPageFinished: (_) {
          if (mounted) {
            setState(() {
              loading = false;
            });
          }
        },

        onNavigationRequest:
            (NavigationRequest request) async {
          final uri = Uri.parse(request.url);

          // INTERNAL DOMAIN
          if (uri.host.contains(
            "cocbasepro.com",
          )) {
            return NavigationDecision.navigate;
          }

          // PHONE / EMAIL
          if ([
            "tel",
            "mailto",
            "sms",
          ].contains(uri.scheme)) {
            await launchUrl(uri);

            return NavigationDecision.prevent;
          }

          // EXTERNAL LINKS
          final open =
          await AppDialog.confirm(
            title: "Open Link",
            message:
            "Open this link in browser?",
          );

          if (open) {
            await launchUrl(
              uri,
              mode:
              LaunchMode.externalApplication,
            );
          }

          return NavigationDecision.prevent;
        },
      ),
    );

    controller.loadRequest(
      Uri.parse(url),
    );
  }

  Future<bool> _handleBack() async {
    final canBack =
    await controller.canGoBack();

    if (canBack) {
      controller.goBack();
      return false;
    }

    return await AppDialog.confirm(
      title: "Exit App",
      message: "Do you want to exit?",
    );
  }

  Future<void> _refresh() async {
    await controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,

      onPopInvokedWithResult:
          (didPop, result) async {
        if (didPop) return;

        final exit = await _handleBack();

        if (exit && mounted) {
          SystemNavigator.pop();
        }
      },

      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              if (loading)
                LinearProgressIndicator(
                  value: progress,
                ),

              Expanded(
                child: Stack(
                  children: [
                    WebViewWidget(
                      controller: controller,
                    ),

                    if (loading)
                      const Center(
                        child:
                        CircularProgressIndicator(),
                      ),
                  ],
                ),
              ),

              const AdBanner(),
            ],
          ),
        ),

        floatingActionButton:
        FloatingActionButton(
          onPressed: _refresh,
          child: const Icon(Icons.refresh),
        ),
      ),
    );
  }
}