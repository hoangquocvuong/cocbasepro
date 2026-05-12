import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:webview_flutter/webview_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/* =========================
   BACKGROUND NOTI HANDLER
========================= */
Future<void> firebaseBgHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

/* =========================
   MAIN
========================= */
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }

  FirebaseMessaging.onBackgroundMessage(firebaseBgHandler);

  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
  );

  runApp(const MyApp());
}

/* =========================
   ROOT APP
========================= */
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,

      // 🔥 FIX: vào thẳng WebView (KHÔNG splash Flutter)
      home: WebScreen(),
    );
  }
}

/* =========================
   WEBVIEW SCREEN
========================= */
class WebScreen extends StatefulWidget {
  const WebScreen({super.key});

  @override
  State<WebScreen> createState() => _WebScreenState();
}

class _WebScreenState extends State<WebScreen> {

  late final WebViewController controller;
  late StreamSubscription netSub;

  bool isOffline = false;

  final String url = "https://www.cocbasepro.com";

  @override
  void initState() {
    super.initState();

    /* =========================
       WEBVIEW INIT
    ========================= */
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) async {
            final uri = Uri.parse(request.url);

            if (uri.scheme == 'http' || uri.scheme == 'https') {
              return NavigationDecision.navigate;
            }

            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }

            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(url));

    /* =========================
       NETWORK LISTENER
    ========================= */
    netSub = Connectivity()
        .onConnectivityChanged
        .listen((result) {

      final offline = result.contains(ConnectivityResult.none);

      if (offline != isOffline) {
        setState(() => isOffline = offline);

        if (!offline) {
          controller.reload();
        }
      }
    });

    /* =========================
       FIREBASE NOTI
    ========================= */
    setupFirebase();
  }

  Future<void> setupFirebase() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    await messaging.requestPermission();

    String? token = await messaging.getToken();
    log("FCM TOKEN: $token");

    FirebaseMessaging.onMessage.listen((message) {
      debugPrint("NOTIFICATION RECEIVED");
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      log("OPEN FROM NOTI");
    });
  }

  @override
  void dispose() {
    netSub.cancel();
    super.dispose();
  }

  /* =========================
     BACK HANDLER
  ========================= */
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

      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await handleBack();
      },

      child: Scaffold(
        backgroundColor: Colors.black,

        body: Stack(
          children: [

            WebViewWidget(controller: controller),

            /* OFFLINE OVERLAY */
            if (isOffline)
              Container(
                color: Colors.black,
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [

                      Icon(
                        Icons.wifi_off,
                        color: Colors.white,
                        size: 70,
                      ),

                      SizedBox(height: 10),

                      Text(
                        "No Internet Connection",
                        style: TextStyle(color: Colors.white),
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