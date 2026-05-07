import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/* =========================
   ADMOB BANNER WIDGET
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
      adUnitId: "ca-app-pub-3940256099942544/6300978111", // TEST ID
      listener: BannerAdListener(
        onAdLoaded: (_) {
          setState(() => loaded = true);
        },
        onAdFailedToLoad: (ad, err) {
          ad.dispose();
        },
      ),
      request: const AdRequest(),
    );

    _bannerAd!.load();
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded || _bannerAd == null) {
      return const SizedBox();
    }

    return SizedBox(
      height: _bannerAd!.size.height.toDouble(),
      width: _bannerAd!.size.width.toDouble(),
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
   GLOBAL NAVIGATOR
========================= */
class AppNavigator {
  static final GlobalKey<NavigatorState> key =
  GlobalKey<NavigatorState>();

  static NavigatorState get nav => key.currentState!;
  static BuildContext get context => key.currentContext!;

  static Future<T?> push<T>(Widget page) {
    return nav.push(MaterialPageRoute(builder: (_) => page));
  }

  static void pop<T>([T? result]) {
    nav.pop(result);
  }

  static Future<T?> pushReplacement<T>(Widget page) {
    return nav.pushReplacement(
      MaterialPageRoute(builder: (_) => page),
    );
  }
}

/* =========================
   DIALOG
========================= */
class AppDialog {
  static Future<bool> confirm({
    required String title,
    required String message,
  }) async {
    final result = await showDialog<bool>(
      context: AppNavigator.context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text("No"),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
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
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await MobileAds.instance.initialize(); // 🔥 ADMOB INIT

  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
  );

  runApp(const MyApp());
}

/* =========================
   APP ROOT
========================= */
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: AppNavigator.key,
      debugShowCheckedModeBanner: false,
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
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    Future.delayed(const Duration(seconds: 2), () {
      AppNavigator.pushReplacement(const AppGate());
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
   GATE (INTERNET CHECK)
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
    _check();
  }

  Future<void> _check() async {
    final result = await Connectivity().checkConnectivity();

    if (!mounted) return;

    setState(() {
      hasInternet = !result.contains(ConnectivityResult.none);
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return hasInternet ? const MainScreen() : const NoInternet();
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, color: Colors.white, size: 80),
            const SizedBox(height: 10),
            const Text("No Internet",
                style: TextStyle(color: Colors.white)),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                AppNavigator.pushReplacement(const AppGate());
              },
              child: const Text("Retry"),
            )
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
  State<MainScreen> createState() => _MainScreenState();
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
        onTap: (i) => setState(() => index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.info), label: "About"),
        ],
      ),
    );
  }
}

/* =========================
   ABOUT
========================= */
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("About")),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("COC Base Pro",
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 10),
            Text(
              "Find the best Clash of Clans bases updated daily.\n\nWar, Farming, Hybrid - all strategies in one place.",
            ),
            SizedBox(height: 20),
            Text("Version: 1.0.0"),
          ],
        ),
      ),
    );
  }
}

/* =========================
   WEBVIEW SCREEN + ADS
========================= */
class WebShell extends StatefulWidget {
  const WebShell({super.key});

  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell> {
  late final WebViewController controller;

  bool loading = true;
  double progress = 0;

  final String url = "https://www.cocbasepro.com";

  @override
  void initState() {
    super.initState();

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent("cocbasepro_app")
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) => setState(() => progress = p / 100),
          onPageStarted: (_) => setState(() => loading = true),
          onPageFinished: (_) => setState(() => loading = false),
          onNavigationRequest: (request) async {
            final uri = Uri.parse(request.url);

            if (uri.host.contains("cocbasepro.com")) {
              controller.loadRequest(uri);
              return NavigationDecision.prevent;
            }

            if (["tel", "mailto", "sms"].contains(uri.scheme)) {
              await launchUrl(uri);
              return NavigationDecision.prevent;
            }

            final open = await AppDialog.confirm(
              title: "Open link",
              message: "Open in browser?",
            );

            if (open) {
              await launchUrl(uri,
                  mode: LaunchMode.externalApplication);
            }

            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(url));
  }

  Future<bool> _handleBack() async {
    final canBack = await controller.canGoBack();

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
    controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
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
                LinearProgressIndicator(value: progress),

              Expanded(
                child: Stack(
                  children: [
                    RefreshIndicator(
                      onRefresh: _refresh,
                      child: WebViewWidget(controller: controller),
                    ),

                    if (loading)
                      const Center(child: CircularProgressIndicator()),
                  ],
                ),
              ),

              const AdBanner(), // 🔥 ADS HERE
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _refresh,
          child: const Icon(Icons.refresh),
        ),
      ),
    );
  }
}