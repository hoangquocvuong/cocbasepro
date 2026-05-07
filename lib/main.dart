import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 🔥 Fullscreen app (Windows / Android style app store)
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(const MyApp());
}

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

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController animationController;
  late Animation<double> fadeAnimation;

  @override
  void initState() {
    super.initState();

    animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    fadeAnimation = Tween<double>(begin: 0, end: 1).animate(animationController);

    animationController.forward();

    _goToHome();
  }

  void _goToHome() async {
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
        const WebViewPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  @override
  void dispose() {
    animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: FadeTransition(
          opacity: fadeAnimation,
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.public, size: 90, color: Colors.white),
              SizedBox(height: 20),
              Text(
                "COC BASE PRO",
                style: TextStyle(color: Colors.white, fontSize: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewController webViewController;

  bool isLoading = true;
  bool hasError = false;
  double progressValue = 0;

  @override
  void initState() {
    super.initState();

    webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            setState(() {
              progressValue = value / 100;
            });
          },
          onPageStarted: (url) {
            setState(() {
              isLoading = true;
              hasError = false;
            });
          },
          onPageFinished: (url) {
            setState(() {
              isLoading = false;
            });
          },
          onWebResourceError: (error) {
            setState(() {
              isLoading = false;
              hasError = true;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse('https://www.cocbasepro.com'));
  }

  Future<bool> handleBack() async {
    if (await webViewController.canGoBack()) {
      webViewController.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        await handleBack();
      },
      child: Scaffold(
        body: Stack(
          children: [
            if (!hasError)
              WebViewWidget(controller: webViewController)
            else
              const Center(
                child: Text(
                  "Không có kết nối mạng",
                  style: TextStyle(fontSize: 16),
                ),
              ),

            // 🔥 TOP LOADING BAR (Chrome style)
            if (isLoading)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(value: progressValue),
              ),
          ],
        ),

        // 🔥 reload button
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            webViewController.reload();
          },
          child: const Icon(Icons.refresh),
        ),
      ),
    );
  }
}