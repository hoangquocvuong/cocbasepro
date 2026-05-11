import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:google_mobile_ads/google_mobile_ads.dart';

/* ======================================================
   MAIN
====================================================== */

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // IOS WEBVIEW FIX
  if (Platform.isIOS) {
    WebViewPlatform.instance =
        WebKitWebViewPlatform();
  }

  // INIT ADS
  await MobileAds.instance.initialize();

  runApp(const MyApp());
}

/* ======================================================
   ROOT APP
====================================================== */

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      theme: ThemeData(
        brightness: Brightness.dark,
      ),

      home: const SplashScreen(),
    );
  }
}

/* ======================================================
   SPLASH
====================================================== */

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

    Timer(
      const Duration(seconds: 2),
          () {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => const AppGate(),
            ),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Image(
          image: AssetImage(
            "assets/logo.png",
          ),
          width: 140,
        ),
      ),
    );
  }
}

/* ======================================================
   INTERNET CHECK
====================================================== */

class AppGate extends StatefulWidget {
  const AppGate({super.key});

  @override
  State<AppGate> createState() =>
      _AppGateState();
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
          child:
          CircularProgressIndicator(),
        ),
      );
    }

    return hasInternet
        ? const MainScreen()
        : const NoInternetScreen();
  }
}

/* ======================================================
   NO INTERNET
====================================================== */

class NoInternetScreen
    extends StatelessWidget {
  const NoInternetScreen({super.key});

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
              size: 90,
            ),

            const SizedBox(height: 15),

            const Text(
              "No Internet Connection",
              style: TextStyle(
                fontSize: 18,
                color: Colors.white,
              ),
            ),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                    const AppGate(),
                  ),
                );
              },
              child: const Text(
                "Retry",
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ======================================================
   MAIN SCREEN
====================================================== */

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() =>
      _MainScreenState();
}

class _MainScreenState
    extends State<MainScreen> {
  int index = 0;

  final pages = const [
    WebShell(),
    AboutPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: pages[index],

      bottomNavigationBar:
      BottomNavigationBar(
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

/* ======================================================
   ABOUT
====================================================== */

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

/* ======================================================
   ADMOB BANNER
====================================================== */

class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  @override
  State<AdBanner> createState() =>
      _AdBannerState();
}

class _AdBannerState
    extends State<AdBanner> {
  BannerAd? bannerAd;

  bool loaded = false;

  @override
  void initState() {
    super.initState();

    bannerAd = BannerAd(
      size: AdSize.banner,

      adUnitId: Platform.isAndroid
          ? "ca-app-pub-3940256099942544/6300978111"
          : "ca-app-pub-3940256099942544/2934735716",

      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) {
            setState(() {
              loaded = true;
            });
          }
        },

        onAdFailedToLoad: (
            ad,
            error,
            ) {
          ad.dispose();
        },
      ),

      request: const AdRequest(),
    );

    bannerAd!.load();
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded || bannerAd == null) {
      return const SizedBox();
    }

    return SizedBox(
      width:
      bannerAd!.size.width.toDouble(),

      height:
      bannerAd!.size.height.toDouble(),

      child: AdWidget(
        ad: bannerAd!,
      ),
    );
  }

  @override
  void dispose() {
    bannerAd?.dispose();
    super.dispose();
  }
}

/* ======================================================
   WEBVIEW
====================================================== */

class WebShell extends StatefulWidget {
  const WebShell({super.key});

  @override
  State<WebShell> createState() =>
      _WebShellState();
}

class _WebShellState
    extends State<WebShell> {
  late final WebViewController controller;

  bool isLoading = true;

  final String websiteUrl =
      "https://www.cocbasepro.com";

  @override
  void initState() {
    super.initState();

    late final PlatformWebViewControllerCreationParams
    params;

    if (WebViewPlatform.instance
    is WebKitWebViewPlatform) {
      params =
          WebKitWebViewControllerCreationParams(
            allowsInlineMediaPlayback:
            true,

            mediaTypesRequiringUserAction:
            const {},
          );
    } else {
      params =
      const PlatformWebViewControllerCreationParams();
    }

    controller =
        WebViewController.fromPlatformCreationParams(
          params,
        );

    controller
      ..setJavaScriptMode(
        JavaScriptMode.unrestricted,
      )

      ..setBackgroundColor(
        Colors.white,
      )

      ..setUserAgent(
        "cocbasepro_ios_app",
      )

      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (mounted) {
              setState(() {
                isLoading = true;
              });
            }
          },

          onPageFinished: (url) {
            if (mounted) {
              setState(() {
                isLoading = false;
              });
            }
          },

          onNavigationRequest:
              (request) async {
            final uri =
            Uri.parse(request.url);

            // INTERNAL DOMAIN
            if (uri.host.contains(
              "cocbasepro.com",
            )) {
              return NavigationDecision
                  .navigate;
            }

            // PHONE / EMAIL
            if ([
              "tel",
              "mailto",
              "sms",
            ].contains(uri.scheme)) {
              await launchUrl(uri);

              return NavigationDecision
                  .prevent;
            }

            // OPEN EXTERNAL
            await launchUrl(
              uri,
              mode: LaunchMode
                  .externalApplication,
            );

            return NavigationDecision
                .prevent;
          },
        ),
      )

      ..loadRequest(
        Uri.parse(
          websiteUrl,
        ),
      );
  }

  Future<bool> _handleBack() async {
    final canBack =
    await controller.canGoBack();

    if (canBack) {
      controller.goBack();

      return false;
    }

    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,

      onPopInvokedWithResult:
          (didPop, result) async {
        if (didPop) return;

        final exit =
        await _handleBack();

        if (exit) {
          SystemNavigator.pop();
        }
      },

      child: Scaffold(
        backgroundColor: Colors.white,

        body: Stack(
          children: [
            Positioned.fill(
              child: WebViewWidget(
                controller: controller,
              ),
            ),

            if (isLoading)
              const Center(
                child:
                CircularProgressIndicator(),
              ),
          ],
        ),

        bottomNavigationBar:
        const AdBanner(),
      ),
    );
  }
}