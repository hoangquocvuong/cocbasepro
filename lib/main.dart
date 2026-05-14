// main.dart
// Full fixed version:
// - No reload when returning to app
// - WebView state preserved
// - Recover only if WebView actually dies
// - Connectivity handling
// - Firebase + AdMob + Review kept

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
import 'package:in_app_review/in_app_review.dart';

Future<void> firebaseBgHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

InterstitialAd? interstitialAd;

void loadInterstitial() {
  InterstitialAd.load(
    adUnitId: 'ca-app-pub-9371341402256787/5085734937',
    request: const AdRequest(),
    adLoadCallback: InterstitialAdLoadCallback(
      onAdLoaded: (ad) => interstitialAd = ad,
      onAdFailedToLoad: (error) {
        debugPrint(error.toString());
      },
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase error: $e');
  }

  FirebaseMessaging.onBackgroundMessage(firebaseBgHandler);

  await MobileAds.instance.initialize();

  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
  );

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

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    loadInterstitial();

    Future.delayed(const Duration(milliseconds: 2200), () {
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const WebScreen(),
        ),
      );

      Future.delayed(
        const Duration(milliseconds: 800),
            () {
          interstitialAd?.show();
        },
      );
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

class WebScreen extends StatefulWidget {
  const WebScreen({super.key});

  @override
  State<WebScreen> createState() => _WebScreenState();
}

class _WebScreenState extends State<WebScreen>
    with WidgetsBindingObserver {

  late final WebViewController controller;
  late final StreamSubscription<List<ConnectivityResult>> netSub;

  final homeUrl='https://www.cocbasepro.com';

  bool isOffline=false;
  bool isReloading=false;

  String currentUrl='';

  int openCount=0;
  bool hasRequestedReview=false;

  DateTime lastReloadTime=DateTime.now();

  @override
  void initState(){
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    currentUrl=homeUrl;

    controller=WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF1E88F0))
      ..setNavigationDelegate(_navigation())
      ..loadRequest(Uri.parse(homeUrl));

    _setupConnectivity();
    _setupFirebase();
  }

  NavigationDelegate _navigation(){
    return NavigationDelegate(
      onNavigationRequest:(request) async {

        final uri=Uri.parse(request.url);

        if(uri.host.contains('firebaseio.com')){
          return NavigationDecision.prevent;
        }

        if(isOffline){
          return NavigationDecision.prevent;
        }

        if(uri.host.contains('cocbasepro.com')){
          currentUrl=uri.toString();
          return NavigationDecision.navigate;
        }

        if(uri.host.toLowerCase().contains('buymeacoffee')){

          final ok=await showDialog<bool>(
            context:context,
            builder:(ctx)=>AlertDialog(
              title:const Text('Open link'),
              content:const Text('Open in browser?'),
              actions:[
                TextButton(
                  onPressed:()=>Navigator.pop(ctx,false),
                  child:const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed:()=>Navigator.pop(ctx,true),
                  child:const Text('Open'),
                )
              ],
            ),
          )??false;

          if(ok){
            await launchUrl(
              uri,
              mode:LaunchMode.externalApplication,
            );
          }

          return NavigationDecision.prevent;
        }

        await launchUrl(
          uri,
          mode:LaunchMode.externalApplication,
        );

        return NavigationDecision.prevent;
      },

      onPageFinished:(_){
        isReloading=false;
        _handleReview();
      },
    );
  }

  void _setupConnectivity(){
    netSub=Connectivity().onConnectivityChanged.listen((results){
      final offline=results.contains(ConnectivityResult.none);

      if(offline==isOffline||!mounted)return;

      setState(() {
        isOffline=offline;
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state){
    if(state==AppLifecycleState.resumed){
      _checkAlive();
    }
  }

  Future<void> _checkAlive() async{
    await Future.delayed(const Duration(milliseconds:500));

    if(!mounted)return;

    try{
      await controller.runJavaScript('document.title');
    }catch(_){
      await _reload();
    }
  }

  Future<void> _reload() async{

    if(isReloading)return;

    final diff=DateTime.now()
        .difference(lastReloadTime)
        .inSeconds;

    if(diff<10)return;

    isReloading=true;
    lastReloadTime=DateTime.now();

    try{
      await controller.loadRequest(
        Uri.parse(currentUrl),
      );
    }catch(_){}

    await Future.delayed(
      const Duration(seconds:2),
    );

    isReloading=false;
  }

  void _handleReview(){

    if(hasRequestedReview)return;

    openCount++;

    if(openCount>=3){
      hasRequestedReview=true;
      _requestReview();
    }
  }

  Future<void> _requestReview() async{
    final review=InAppReview.instance;

    if(await review.isAvailable()){
      await review.requestReview();
    }
  }

  Future<void> _setupFirebase() async{
    final messaging=FirebaseMessaging.instance;

    await messaging.requestPermission();

    final token=await messaging.getToken();
    log('FCM:$token');
  }

  Future<void> _back() async{
    if(await controller.canGoBack()){
      await controller.goBack();
    }
  }

  @override
  void dispose(){
    WidgetsBinding.instance.removeObserver(this);
    netSub.cancel();
    interstitialAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context){
    return PopScope(
      canPop:false,
      onPopInvokedWithResult:(didPop,_) async {
        if(!didPop){
          await _back();
        }
      },
      child:Scaffold(
        backgroundColor:const Color(0xFF1E88F0),
        body:Stack(
          children:[
            SafeArea(
              child:WebViewWidget(
                controller:controller,
              ),
            ),
            if(isOffline)
              Container(
                color:Colors.black.withValues(alpha:0.85),
                child:Center(
                  child:Column(
                    mainAxisSize:MainAxisSize.min,
                    children:[
                      const Icon(
                        Icons.wifi_off,
                        size:48,
                        color:Colors.white70,
                      ),
                      const SizedBox(height:12),
                      const Text(
                        'No Internet',
                        style:TextStyle(
                          color:Colors.white,
                        ),
                      ),
                      const SizedBox(height:12),
                      ElevatedButton(
                        onPressed:(){
                          controller.reload();
                        },
                        child:const Text('Retry'),
                      )
                    ],
                  ),
                ),
              )
          ],
        ),
      ),
    );
  }
}
