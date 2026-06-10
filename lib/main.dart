// =========================
// (0) IMPORTS
// =========================
import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
RewardedAd? rewardedAd;

void loadRewardedAd() {
  RewardedAd.load(
    adUnitId: 'ca-app-pub-9371341402256787/5585456052',
    request: const AdRequest(
      nonPersonalizedAds: true,
    ),
    rewardedAdLoadCallback:
    RewardedAdLoadCallback(

      onAdLoaded: (ad) {
        rewardedAd = ad;
      },

      onAdFailedToLoad: (error) {
        debugPrint(
          'Rewarded failed: $error',
        );
      },
    ),
  );
}

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
  Map<String, String> premiumMap = {};

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
  int unreadCommunity = 0;
  Timer? _communityBadgeDebounce;
  Timer? newsTimer;
  Timer? _badgeDebounce;
  bool appJustResumed = false;
  bool showResumeOverlay = false;
  bool isInitialLaunch = true;
  bool firstInternalLoad = true;
  final Set<String> unlockedPremiumLinks = {};
  bool isRewardShowing = false;
  DateTime lastRewardTime =
  DateTime.fromMillisecondsSinceEpoch(0);
  DateTime lastCommunityOpenAd =
  DateTime.fromMillisecondsSinceEpoch(0);
  DateTime lastAnyInterstitialAd =
  DateTime.fromMillisecondsSinceEpoch(0);

  DateTime lastCommunityCloseAd =
  DateTime.fromMillisecondsSinceEpoch(0);
  bool isSubscriber = false;
  bool rewardStartedForPremium = false;
  int rewardCancelCount = 0;
  int rewardSuccessCount = 0;
  int heroSkinClickCount = 0;

  DateTime lastHeroSkinAdTime =
  DateTime.fromMillisecondsSinceEpoch(0);

  final InAppPurchase iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? purchaseSub;

  ProductDetails? monthlyProduct;
  ProductDetails? yearlyProduct;
  String currentUrl = '';
  String? pendingPremiumBaseLink;

  int openCount = 0;
  bool hasRequestedReview = false;

  int internalOpenCount = 0;

  DateTime lastInterstitialTime =
  DateTime.fromMillisecondsSinceEpoch(0);
  bool canShowInterstitialNow() {
    final now = DateTime.now();

    if (isSubscriber) return false;
    if (isRewardShowing) return false;
    if (interstitialAd == null) return false;

    return now.difference(lastAnyInterstitialAd).inSeconds >= 90;
  }

  void showDebug(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void tryShowInterstitial() {
    if (!canShowInterstitialNow()) return;


    internalOpenCount++;
    final justWatchedReward =
        DateTime.now()
            .difference(lastRewardTime)
            .inSeconds < 120;

    if (justWatchedReward) return;

    final now = DateTime.now();

    final canShowByCount =
        internalOpenCount >= 4;

    final canShowByTime =
        now.difference(lastInterstitialTime).inSeconds >= 90;


    if (
    canShowByCount &&
        canShowByTime &&
        interstitialAd != null
    ) {
      internalOpenCount = 0;
      lastInterstitialTime = now;

      interstitialAd!.fullScreenContentCallback =
          FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              interstitialAd = null;
              loadInterstitial();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              interstitialAd = null;
              loadInterstitial();
            },
          );
      lastAnyInterstitialAd = now;
      interstitialAd!.show();
      interstitialAd = null;
    }
  }

  bool canShowHeroSkinAd() {
    final now = DateTime.now();

    if (isSubscriber) return false;
    if (isRewardShowing) return false;
    if (interstitialAd == null) return false;

    return now.difference(lastHeroSkinAdTime).inSeconds >= 45;
  }

  void showHeroSkinAd() {
    if (!canShowHeroSkinAd()) return;

    lastHeroSkinAdTime = DateTime.now();
    lastAnyInterstitialAd = DateTime.now();

    interstitialAd!.fullScreenContentCallback =
        FullScreenContentCallback(
          onAdDismissedFullScreenContent: (ad) {
            ad.dispose();
            interstitialAd = null;
            loadInterstitial();
          },
          onAdFailedToShowFullScreenContent: (ad, error) {
            ad.dispose();
            interstitialAd = null;
            loadInterstitial();
          },
        );

    interstitialAd!.show();
    interstitialAd = null;
  }

  void showCommunityOpenAd() {
    if (!canShowInterstitialNow()) return;

    lastCommunityOpenAd = DateTime.now();
    lastAnyInterstitialAd = DateTime.now();

    interstitialAd!.fullScreenContentCallback =
        FullScreenContentCallback(
          onAdDismissedFullScreenContent: (ad) {
            ad.dispose();
            interstitialAd = null;
            loadInterstitial();
          },
          onAdFailedToShowFullScreenContent: (ad, error) {
            ad.dispose();
            interstitialAd = null;
            loadInterstitial();
          },
        );

    interstitialAd!.show();
    interstitialAd = null;
  }


  String normalizeBuyMeCoffeeUrl(String url) {
    final uri = Uri.parse(url);

    var path = uri.path;

    path = path
        .replaceAll('/hoangquocvh/', '/cocbase/')
        .replaceAll('/hoangvuong/', '/cocbase/');

    if (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }

    return 'https://buymeacoffee.com$path';
  }

  String extractBuyMeCoffeeId(String url) {
    final uri = Uri.parse(url);

    final parts = uri.path
        .split('/')
        .where((e) => e.isNotEmpty)
        .toList();

    final index = parts.indexOf('e');

    if (index != -1 && index + 1 < parts.length) {
      return parts[index + 1];
    }

    return '';
  }



  Future<void> loadPremiumMap() async {
    try {
      final res = await http.get(
        Uri.parse(
          'https://raw.githubusercontent.com/hoangquocvuong/premium-map.json/refs/heads/main/premium-map.json?v=${DateTime.now().millisecondsSinceEpoch}',
        ),
      ).timeout(
        const Duration(seconds: 8),

      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;

        premiumMap = {};

        premiumMap = data.map(
              (key, value) => MapEntry(
            key.toString(),
            value.toString(),
          ),
        );

        debugPrint('Premium map loaded: ${premiumMap.length}');
      }
    } catch (e) {
      debugPrint('Premium map error: $e');
    }
  }

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
    loadInterstitial();
    loadRewardedAd();
    loadPremiumMap();
    initPurchases();




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
      const Duration(milliseconds: 800),
          () {
        if (!mounted) return;

        setState(() {
          minSplashFinished = true;
        });
      },
    );

  }
  Future<void> initPurchases() async {

    final available = await iap.isAvailable();

    if (!available) return;

    purchaseSub = iap.purchaseStream.listen((purchases) async {

      for (final purchase in purchases) {

        if (purchase.status == PurchaseStatus.purchased ||
            purchase.status == PurchaseStatus.restored) {

          isSubscriber = true;

          await syncPremiumToWebView();

          if (purchase.pendingCompletePurchase) {
            await iap.completePurchase(purchase);
          }

          if (mounted) {
            setState(() {});
            await showPremiumActivatedDialog();
          }

          // Mở link premium đang chờ sau khi thanh toán xong
          if (pendingPremiumBaseLink != null &&
              pendingPremiumBaseLink!.isNotEmpty) {
            final link = pendingPremiumBaseLink!;
            pendingPremiumBaseLink = null;

            await launchUrl(
              Uri.parse(link),
              mode: LaunchMode.platformDefault,
            );
          }
        }
      }
    });

    const ids = {
      'premium_monthly',
      'premium_yearly',
    };

    final response =
    await iap.queryProductDetails(ids);

    for (final p in response.productDetails) {

      if (p.id == 'premium_monthly') {
        monthlyProduct = p;
      }

      if (p.id == 'premium_yearly') {
        yearlyProduct = p;
      }
    }

    await iap.restorePurchases();
  }

  Future<void> syncPremiumToWebView() async {
    final value = isSubscriber ? '1' : '0';

    await controller.runJavaScript('''
    localStorage.setItem("APP_SUBSCRIBER", "$value");
    window.APP_SUBSCRIBER = "$value";
    document.documentElement.classList.toggle("app-subscriber", "$value" === "1");
  ''');
  }
  void buyMonthly() {
    if (monthlyProduct == null) {

      return;
    }


    final purchaseParam =
    PurchaseParam(productDetails: monthlyProduct!);

    iap.buyNonConsumable(
      purchaseParam: purchaseParam,
    );
  }
  void buyYearly() {
    if (yearlyProduct == null) {

      return;
    }


    final purchaseParam =
    PurchaseParam(productDetails: yearlyProduct!);

    iap.buyNonConsumable(
      purchaseParam: purchaseParam,
    );
  }
  Future<void> showPremiumSubscribePopup(String baseLink) async {
    if (!mounted) return;

    Widget benefit(String text) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      );
    }

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 8, 0),
        contentPadding: const EdgeInsets.fromLTRB(22, 10, 22, 6),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 18),

        title: Row(
          children: [
            const Expanded(
              child: Text(
                '🚀 Go Premium',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 23,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),

        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Unlock 2000+ Premium Bases Instantly',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),

            const SizedBox(height: 12),

            benefit('Remove All Ads'),
            benefit('Unlimited Premium Base Access'),
            benefit('Faster Access, No Waiting'),
            benefit('Daily Updated Premium Bases'),
            benefit('Browse Hero Skins Without Ads'),

            const SizedBox(height: 6),

            const Text(
              'Get unlimited access to premium layouts and exclusive app features.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),

            const SizedBox(height: 4),

            const Text(
              'Subscriptions renew automatically unless cancelled.',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey,
              ),
            ),

            const SizedBox(height: 4),

            Row(
              children: [
                TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () async {
                    await launchUrl(
                      Uri.parse(
                        'https://www.cocbasepro.com/p/privacy-policy.html',
                      ),
                    );
                  },
                  child: const Text(
                    'Privacy Policy',
                    style: TextStyle(fontSize: 12),
                  ),
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '|',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ),

                TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () async {
                    await launchUrl(
                      Uri.parse(
                        'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/',
                      ),
                    );
                  },
                  child: const Text(
                    'Terms of Use',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),

        actions: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    pendingPremiumBaseLink = baseLink;
                    Navigator.pop(context);
                    buyMonthly();
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Monthly Plan',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '\$6.99 / Month',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    pendingPremiumBaseLink = baseLink;
                    Navigator.pop(context);
                    buyYearly();
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Yearly Plan',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '\$49.99 / Year',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Save 40%',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  Future<void> showPremiumActivatedDialog() async {
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          '🎉 Premium Activated',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your subscription is now active.',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),

            SizedBox(height: 12),

            Text('✓ Remove All Ads'),
            Text('✓ Unlimited Premium Base Access'),
            Text('✓ Faster Access, No Waiting'),
            Text('✓ Daily Updated Premium Bases'),
            Text('✓ Browse Hero Skins Without Ads'),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Continue'),
            ),
          ),
        ],
      ),
    );

    if (!mounted) return;

    controller.reload();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Premium features unlocked successfully 🚀',
        ),
      ),
    );
  }

  Future<void> showPremiumPopupAfterAdCancel(String baseLink) async {
    if (isSubscriber) return;
    if (!mounted) return;


    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    const countKey = 'premium_cancel_popup_count';
    const lastKey = 'premium_cancel_popup_last_time';

    final count = prefs.getInt(countKey) ?? 0;
    final lastTime = prefs.getInt(lastKey) ?? 0;
    final now = DateTime
        .now()
        .millisecondsSinceEpoch;

// Đã hiện đủ 3 lần -> không hiện nữa
    if (count >= 3) {
      return;
    }

// 2 ngày
    final twoDaysMs =
        const Duration(days: 2).inMilliseconds;

// Chưa đủ 2 ngày từ lần popup trước
    if (
    lastTime > 0 &&
        now - lastTime < twoDaysMs
    ) {
      return;
    }

    await prefs.setInt(
      countKey,
      count + 1,
    );

    await prefs.setInt(
      lastKey,
      now,
    );

    if (!mounted) return;

    await showPremiumSubscribePopup(baseLink);
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
            : 'CocBaseProApp-Android',
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
          _communityBadgeDebounce?.cancel();
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

      ..addJavaScriptChannel(
        'CommunityBadge',
        onMessageReceived: (message) {
          final count =
              int.tryParse(message.message.trim()) ?? 0;

          if (!mounted) return;

          setState(() {
            unreadCommunity = count;
          });

          debugPrint(
              "🔥 community badge updated = $unreadCommunity"
          );
        },
      )
      ..addJavaScriptChannel(
        'HeroSkinAd',
        onMessageReceived: (message) {

          if(message.message != "skin_detail_click"){
            return;
          }

          heroSkinClickCount++;

          if (heroSkinClickCount >= 5) {
            heroSkinClickCount = 0;
            showHeroSkinAd();
          }
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

          // ===== INTERNAL WEBSITE =====
          if (uri.host.contains('cocbasepro.com')) {

            final newUrl = uri.toString();

            if (newUrl != currentUrl) {

              currentUrl = newUrl;

              if (firstInternalLoad) {

                firstInternalLoad = false;

              } else {

                tryShowInterstitial();
              }
            }

            return NavigationDecision.navigate;
          }

// ===== BUY ME A COFFEE =====
          final host = uri.host.toLowerCase();

          if (
          host.contains('buymeacoffee') ||
              host.contains('bmc.link')
          ) {

            final cleanUrl =
            Uri.decodeFull(request.url);
            final pathParts = uri.path
                .split('/')
                .where((e) => e.isNotEmpty)
                .toList();

            final isPremiumProductLink =
            pathParts.contains('e');

            if (!isPremiumProductLink) {
              await launchUrl(
                uri,
                mode: LaunchMode.externalApplication,
              );

              return NavigationDecision.prevent;
            }

            final productId =
            extractBuyMeCoffeeId(cleanUrl);

            debugPrint(
              'PREMIUM ID = $productId',
            );

            debugPrint(
              'MAP HAS = ${premiumMap.containsKey(productId)}',
            );

            final baseLink = premiumMap[productId];


            if (baseLink == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Premium link not found'),
                ),
              );

              return NavigationDecision.prevent;
            }

            Future<void> openBaseLink() async {
              final ok = await launchUrl(
                Uri.parse(baseLink),
                mode: LaunchMode.platformDefault,
              );

              if (!mounted) return;

              if (!ok) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Cannot open base link'),
                  ),
                );
              }
            }

            if (isSubscriber) {
              await openBaseLink();
              return NavigationDecision.prevent;
            }

            // Đã unlock trong session -> mở luôn
            if (unlockedPremiumLinks.contains(productId)) {
              await openBaseLink();
              return NavigationDecision.prevent;
            }

            if (isRewardShowing) {
              return NavigationDecision.prevent;
            }

            isRewardShowing = true;

            // Thông báo trước khi xem video
            final agree = await showDialog<bool>(
              context: context,
              builder: (_) {
                return AlertDialog(
                  backgroundColor: const Color(0xFF0B1207),
                  title: const Text(
                    'Unlock Premium Base',
                    style: TextStyle(
                      color: Color(0xFFB7FF00),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  content: const Text(
                    'Watch a short video to unlock this premium base link.',
                    style: TextStyle(
                      color: Colors.white,
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context, false);
                      },
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context, true);
                      },
                      child: const Text(
                        'Watch Video',
                        style: TextStyle(
                          color: Color(0xFFB7FF00),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
            if (!mounted) {
              return NavigationDecision.prevent;
            }
            if (agree != true) {
              isRewardShowing = false;
              await showPremiumSubscribePopup(baseLink);
              return NavigationDecision.prevent;
            }

            if (rewardedAd == null) {
              isRewardShowing = false;
              loadRewardedAd();
              if (!mounted) {
                return NavigationDecision.prevent;
              }

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Ad is loading... Please try again.'),
                ),
              );

              return NavigationDecision.prevent;
            }


            bool earnedReward = false;

            rewardedAd!.fullScreenContentCallback =
                FullScreenContentCallback(
                  onAdDismissedFullScreenContent: (ad) async {
                    ad.dispose();

                    rewardedAd = null;
                    isRewardShowing = false;

                    loadRewardedAd();

                    if (earnedReward) {
                      unlockedPremiumLinks.add(productId);
                      lastRewardTime = DateTime.now();

                      await openBaseLink();
                    } else {
                      await showPremiumPopupAfterAdCancel(baseLink);
                    }
                  },
                  onAdFailedToShowFullScreenContent: (ad, error) {
                    ad.dispose();

                    rewardedAd = null;
                    isRewardShowing = false;

                    loadRewardedAd();
                  },
                );

            rewardedAd!.show(
              onUserEarnedReward: (ad, reward) {
                earnedReward = true;
              },
            );

            return NavigationDecision.prevent;
          }

          // ===== BLOCK ADS / HIDDEN TRACKING ONLY =====
          final url = request.url.toLowerCase();

          final isGoogleAdInternal =
              url.contains('googlesyndication.com') ||
                  url.contains('doubleclick.net') ||
                  url.contains('googleadservices.com') ||
                  url.contains('pagead2.googlesyndication.com') ||
                  url.contains('adtrafficquality.google') ||
                  url.contains('google.com/recaptcha') ||
                  url.contains('/recaptcha/api2/aframe') ||
                  url.contains('/pagead/') ||
                  url.contains('/sodar/');

          if (isGoogleAdInternal) {
            return NavigationDecision.prevent;
          }


          // OTHER LINKS -> OPEN DIRECT
          await launchUrl(uri,
              mode: LaunchMode.externalApplication);

          return NavigationDecision.prevent;
        },

        onPageFinished: (url) async {
          await syncPremiumToWebView();

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
          await _refreshCommunityBadge();


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

    if (openCount >= 6) {
      hasRequestedReview = true;
      _requestReview();
    }
  }

  Future<void> _requestReview() async {

    try {

      final review = InAppReview.instance;

      if (await review.isAvailable()) {
        await review.requestReview();
      }

    } catch (_) {}

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

  Future<void> _refreshCommunityBadge() async {
    try {
      final result =
      await controller.runJavaScriptReturningResult("""
(() => {
  return String(
    Number(window.COMMUNITY_UNREAD_COUNT || 0)
  );
})();
""");

      final raw =
      result
          .toString()
          .replaceAll('"', '')
          .trim();

      final count =
          int.tryParse(raw) ?? 0;

      if (!mounted) return;

      setState(() {
        unreadCommunity = count;
      });

      debugPrint(
          "🔥 community badge refreshed = $unreadCommunity"
      );

    } catch (e) {
      debugPrint(
          "Community badge refresh error: $e"
      );
    }
  }
  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              ListTile(
                leading: const Icon(Icons.forum),
                title: const Text('Forum'),
                trailing: unreadCommunity > 0
                    ? Badge(
                  label: Text(
                    unreadCommunity > 99
                        ? '99+'
                        : unreadCommunity.toString(),
                  ),
                )
                    : null,
                onTap: () async {
                  Navigator.pop(context);

                  showCommunityOpenAd();

                  await controller.runJavaScript("""
document.querySelector('[data-popup="community"]')?.click();
""");

                  await Future.delayed(
                    const Duration(milliseconds: 500),
                  );

                  await _refreshCommunityBadge();
                },
              ),

              ListTile(
                leading: const Icon(Icons.emoji_events),
                title: const Text('Top Rankings'),
                onTap: () async {
                  Navigator.pop(context);
                  await controller.runJavaScript("""
document.querySelector('[data-popup="topclans"]')?.click();
""");
                },
              ),

              ListTile(
                leading: const Icon(Icons.bar_chart),
                title: const Text('Stats'),
                onTap: () async {
                  Navigator.pop(context);
                  await controller.runJavaScript("""
document.querySelector('[data-popup="top"]')?.click();
""");
                },
              ),
            ],
          ),
        );
      },
    );
  }
  // =========================
  // (7.12) DISPOSE
  // =========================
  @override
  void dispose() {
    purchaseSub?.cancel();
    _badgeDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);

    netSub.cancel();
    interstitialAd?.dispose();
    rewardedAd?.dispose();
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

          case 0:
            await controller.loadRequest(
              Uri.parse(homeUrl),
            );
            break;

          case 1:
            await showPremiumSubscribePopup('');
            break;

          case 2:
            showHeroSkinAd();

            await controller.runJavaScript("""
document.querySelector('[data-popup="heroskins"]')?.click();
""");

            break;

          case 3:
            await controller.runJavaScript("""
document.getElementById('nav-news-btn')?.click();
""");
            break;

          case 4:
            await controller.runJavaScript("""
document.getElementById('bookmark-target')?.click();
""");
            break;

          case 5:
            _showMoreMenu();
            break;
        }
      },

      items: [
        const BottomNavigationBarItem(
          icon: Icon(Icons.home),
          label: 'Home',
        ),

        const BottomNavigationBarItem(
          icon: Icon(Icons.workspace_premium),
          label: 'No Ads',
        ),

        const BottomNavigationBarItem(
          icon: Icon(Icons.auto_awesome),
          label: 'Skins',
        ),

        BottomNavigationBarItem(
          icon: Badge(
            isLabelVisible: unreadNews > 0,
            label: Text(
              unreadNews > 9 ? '9+' : unreadNews.toString(),
            ),
            child: const Icon(Icons.article),
          ),
          label: 'News',
        ),

        const BottomNavigationBarItem(
          icon: Icon(Icons.bookmark),
          label: 'Saved',
        ),

        const BottomNavigationBarItem(
          icon: Icon(Icons.menu),
          label: 'More',
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
              if (isOffline)
                Container(
                  width: double.infinity,
                  height: double.infinity,
                  color: const Color(0xFF030503),
                  child: SafeArea(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: StatusBackgroundPainter(progress: 0.35),
                          ),
                        ),

                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 22),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.wifi_off_rounded,
                                  size: 82,
                                  color: const Color(0xFFB7FF00),
                                  shadows: [
                                    Shadow(
                                      color: const Color(0xFFB7FF00)
                                          .withValues(alpha: 0.75),
                                      blurRadius: 24,
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 28),

                                _GamingTitle(
                                  text: 'NO INTERNET',
                                ),

                                const SizedBox(height: 14),

                                Text(
                                  'CHECK YOUR CONNECTION',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.orbitron(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 2.1,
                                  ),
                                ),

                                const SizedBox(height: 42),

                                GestureDetector(
                                  onTap: () async {
                                    final result =
                                    await Connectivity().checkConnectivity();

                                    final offline = result.contains(
                                      ConnectivityResult.none,
                                    );

                                    if (!offline) {
                                      setState(() {
                                        isOffline = false;
                                        pageLoaded = false;
                                        showResumeOverlay = true;
                                        isInitialLaunch = false;
                                      });

                                      controller.reload();
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 34,
                                      vertical: 15,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(999),
                                      color: const Color(0xFFB7FF00),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFFB7FF00)
                                              .withValues(alpha: 0.45),
                                          blurRadius: 22,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      'RETRY',
                                      style: GoogleFonts.orbitron(
                                        color: Colors.black,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 26),

                                Text(
                                  'BASE LAYOUT PRO',
                                  style: GoogleFonts.orbitron(
                                    color: Colors.white.withValues(alpha: 0.38),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 2.2,
                                  ),
                                ),
                              ],
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
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isRestore ? 'RESTORING SESSION' : 'LAUNCHING APP';

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
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 250,
                      height: 250,
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

                    const SizedBox(height: 26),

                    _GamingTitle(text: title),

                    const SizedBox(height: 12),

                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.orbitron(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.2,
                      ),
                    ),

                    const SizedBox(height: 56),

                    Text(
                      'LOADING',
                      style: GoogleFonts.orbitron(
                        color: const Color(0xFFB7FF00),
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        shadows: [
                          Shadow(
                            color: const Color(0xFFB7FF00)
                                .withValues(alpha: 0.75),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    SizedBox(
                      width: 118,
                      height: 18,
                      child: AnimatedBuilder(
                        animation: _controller,
                        builder: (_, __) {
                          return CustomPaint(
                            painter: ShortLoadingBarPainter(
                              progress: _controller.value,
                            ),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 74),

                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: 'BASE LAYOUT ',
                              style: GoogleFonts.orbitron(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.4,
                                shadows: [
                                  Shadow(
                                    color: Colors.white.withValues(alpha: 0.42),
                                    blurRadius: 12,
                                  ),
                                ],
                              ),
                            ),
                            TextSpan(
                              text: 'PRO',
                              style: GoogleFonts.orbitron(
                                color: const Color(0xFFB7FF00),
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.4,
                                shadows: [
                                  Shadow(
                                    color: const Color(0xFFB7FF00)
                                        .withValues(alpha: 0.8),
                                    blurRadius: 16,
                                  ),
                                ],
                              ),
                            ),
                          ],
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
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: GoogleFonts.orbitron(
              color: const Color(0xFFB7FF00).withValues(alpha: 0.42),
              fontSize: 32,
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
              fontSize: 31,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.1,
            ),
          ),
        ],
      ),
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
    final center = Offset(size.width / 2, size.height * 0.31);

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFB7FF00).withValues(alpha: 0.22),
          const Color(0xFFB7FF00).withValues(alpha: 0.06),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(center: center, radius: 180),
      );

    canvas.drawCircle(center, 180, glowPaint);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFFB7FF00).withValues(alpha: 0.24);

    for (int i = 0; i < 5; i++) {
      canvas.drawCircle(
        center,
        82 + i * 18,
        ringPaint,
      );
    }

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFB7FF00).withValues(alpha: 0.72);

    for (int i = 0; i < 4; i++) {
      final radius = 94.0 + i * 22;
      final start = progress * 6.28318530718 + i * 0.75;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        0.42,
        false,
        arcPaint,
      );
    }

    final dotPaint = Paint()
      ..color = const Color(0xFFB7FF00).withValues(alpha: 0.78);

    for (int i = 0; i < 42; i++) {
      final angle = i * 0.82 + progress * 0.45;
      final radius = 78 + (i % 9) * 14;

      final p = Offset(
        center.dx + MathHelper.cos(angle) * radius,
        center.dy + MathHelper.sin(angle) * radius,
      );

      canvas.drawCircle(
        p,
        i % 6 == 0 ? 2.2 : 1.2,
        dotPaint,
      );
    }
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
          const Color(0xFFB7FF00).withValues(alpha: 0.45),
          const Color(0xFFB7FF00).withValues(alpha: 0.12),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(center: c, radius: 105),
      );

    canvas.drawCircle(c, 105, glowPaint);

    final shield = Path()
      ..moveTo(c.dx, c.dy - 72)
      ..cubicTo(c.dx - 22, c.dy - 58, c.dx - 54, c.dy - 52, c.dx - 70, c.dy - 45)
      ..lineTo(c.dx - 58, c.dy + 25)
      ..cubicTo(c.dx - 47, c.dy + 64, c.dx - 20, c.dy + 88, c.dx, c.dy + 106)
      ..cubicTo(c.dx + 20, c.dy + 88, c.dx + 47, c.dy + 64, c.dx + 58, c.dy + 25)
      ..lineTo(c.dx + 70, c.dy - 45)
      ..cubicTo(c.dx + 54, c.dy - 52, c.dx + 22, c.dy - 58, c.dx, c.dy - 72)
      ..close();

    canvas.drawShadow(
      shield,
      const Color(0xFFB7FF00),
      18,
      true,
    );

    canvas.drawPath(
      shield,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFEFFFF5),
            Color(0xFFB7FF00),
            Color(0xFF174112),
            Color(0xFF020804),
          ],
        ).createShader(
          Rect.fromCircle(center: c, radius: 105),
        ),
    );

    final inner = Path()
      ..moveTo(c.dx, c.dy - 47)
      ..cubicTo(c.dx - 14, c.dy - 38, c.dx - 36, c.dy - 33, c.dx - 47, c.dy - 28)
      ..lineTo(c.dx - 39, c.dy + 16)
      ..cubicTo(c.dx - 30, c.dy + 43, c.dx - 12, c.dy + 61, c.dx, c.dy + 74)
      ..cubicTo(c.dx + 12, c.dy + 61, c.dx + 30, c.dy + 43, c.dx + 39, c.dy + 16)
      ..lineTo(c.dx + 47, c.dy - 28)
      ..cubicTo(c.dx + 36, c.dy - 33, c.dx + 14, c.dy - 38, c.dx, c.dy - 47)
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
          Rect.fromCircle(center: c, radius: 80),
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

    const dotSize = 8.0;
    const gap = 10.0;

    final startX = c.dx - dotSize - gap;
    final startY = c.dy - dotSize - gap;

    final dotGlow = Paint()
      ..color = const Color(0xFFB7FF00).withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final dotPaint = Paint()
      ..color = const Color(0xFFB7FF00);

    for (int y = 0; y < 3; y++) {
      for (int x = 0; x < 3; x++) {
        final p = Offset(
          startX + x * (dotSize + gap),
          startY + y * (dotSize + gap),
        );

        canvas.drawCircle(p, 6, dotGlow);
        canvas.drawCircle(p, 4.2, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant StatusShieldPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class ShortLoadingBarPainter extends CustomPainter {
  final double progress;

  ShortLoadingBarPainter({
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {

    // ===== TRACK / KHUNG CŨ =====
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        0,
        5,
        size.width,
        8,
      ),
      const Radius.circular(999),
    );

    // BG
    canvas.drawRRect(
      trackRect,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.42),
    );

    // BORDER
    canvas.drawRRect(
      trackRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFB7FF00)
            .withValues(alpha: 0.55),
    );

    // ===== FILL =====
    final fillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        4,
        7,
        (size.width - 8) *
            (0.18 + (progress * 0.82)),
        4,
      ),
      const Radius.circular(999),
    );

    // GLOW
    canvas.drawRRect(
      fillRect,
      Paint()
        ..color = const Color(0xFFB7FF00)
            .withValues(alpha: 0.38)
        ..maskFilter =
        const MaskFilter.blur(
          BlurStyle.normal,
          8,
        ),
    );

    // FILL
    canvas.drawRRect(
      fillRect,
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0xFF7CC800),
            Color(0xFFB7FF00),
            Color(0xFFDFFF4A),
          ],
        ).createShader(fillRect.outerRect),
    );
  }

  @override
  bool shouldRepaint(covariant ShortLoadingBarPainter oldDelegate) {
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
