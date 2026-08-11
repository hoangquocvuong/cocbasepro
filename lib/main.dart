import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Color(0xFF050505),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const CocBaseProApp());
}

class CocBaseProApp extends StatelessWidget {
  const CocBaseProApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Base Layout Pro',
      theme: ThemeData(useMaterial3: true, brightness: Brightness.light),
      darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: const WebScreen(),
    );
  }
}

class WebScreen extends StatefulWidget {
  const WebScreen({super.key});
  @override
  State<WebScreen> createState() => _WebScreenState();
}

class _WebScreenState extends State<WebScreen> with WidgetsBindingObserver {
  static const String homeUrl = 'https://www.cocbasepro.com';
  static const String interstitialAdUnitId =
      'ca-app-pub-9371341402256787/5085734937';

  static const String rewardedAdUnitId =
      'ca-app-pub-9371341402256787/5585456052';

  static const int supportAdFreeMinutes = 15;
  static const int supportAdFreeMs = supportAdFreeMinutes * 60 * 1000;

  static const int pagesPerInterstitial = 5;
  static const int firstAdDelaySeconds = 60;
  static const int interstitialCooldownSeconds = 120;

  late final WebViewController controller;
  StreamSubscription<List<ConnectivityResult>>? _netSub;
  final DateTime sessionStartedAt = DateTime.now();

  InterstitialAd? _interstitialAd;
  RewardedAd? _rewardedAd;
  bool _adsReady = false;
  bool _interstitialShowing = false;
  bool _rewardedReady = false;
  int _supportAdFreeUntil = 0;
  bool isOffline = false;
  bool pageLoaded = false;
  bool isDarkMode = true;
  bool moreMenuOpen = false;
  int webProgress = 0;
  int internalPagesSinceAd = 0;
  int unreadNews = 0;
  bool _newsBadgeKnown = false;
  Timer? _loadingFinishTimer;
  String currentUrl = homeUrl;
  String lastFinishedInternalUrl = '';
  DateTime lastInterstitialAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _createWebView();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupConnectivity();
      _initDeferredServices();
    });
  }

  void _createWebView() {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(Platform.isIOS ? 'CocBaseProApp-iOS' : 'CocBaseProApp-Android')
      ..setBackgroundColor(const Color(0xFF050505))
      ..addJavaScriptChannel('Flutter', onMessageReceived: (message) {
        final count = int.tryParse(message.message.trim());
        if (count == null || count < 0) return;
        _setNewsBadge(count, explicit: true);
      })
      ..addJavaScriptChannel('AppTheme', onMessageReceived: (message) {
        final dark = message.message.trim().toLowerCase() == 'dark';
        _setTheme(dark, persist: true);
      })
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (progress) {
          if (!mounted) return;

          if (progress >= 100) {
            _loadingFinishTimer?.cancel();
            setState(() => webProgress = 100);
            return;
          }

          if ((progress - webProgress).abs() >= 10) {
            setState(() => webProgress = progress);
          }

          // WKWebView can occasionally stop reporting around 90-99 even when
          // the visible page is ready. Never leave the yellow bar stranded.
          if (progress >= 88) {
            _loadingFinishTimer?.cancel();
            _loadingFinishTimer = Timer(
              const Duration(milliseconds: 700),
              () {
                if (mounted && webProgress >= 88 && webProgress < 100) {
                  setState(() => webProgress = 100);
                }
              },
            );
          }
        },
        onPageStarted: (url) {
          _loadingFinishTimer?.cancel();
          currentUrl = url;
          if (mounted) {
            setState(() {
              pageLoaded = false;
              webProgress = 5;
            });
          }
        },
        onPageFinished: (url) {
          _loadingFinishTimer?.cancel();
          currentUrl = url;
          if (mounted) {
            setState(() {
              pageLoaded = true;
              webProgress = 100;
            });
          }

          unawaited(_applyIOSAppWebMode());
          _countFinishedInternalPage(url);

          Future<void>.delayed(
            const Duration(milliseconds: 350),
            () => _refreshNewsBadge(),
          );
        },
        onWebResourceError: (error) => debugPrint('WebView error: ${error.description}'),
        onNavigationRequest: _handleNavigationRequest,
      ))
      ..loadRequest(Uri.parse(homeUrl));
  }

  Future<void> _initDeferredServices() async {
    unawaited(_loadNativeTheme());
    unawaited(_loadNativeNewsBadge());
    unawaited(_loadSupportRewardState());

    // Let WebKit paint before starting the AdMob SDK.
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    if (!mounted) return;

    try {
      await MobileAds.instance.initialize();
      _adsReady = true;
      _loadInterstitial();
      _loadRewarded();
    } catch (e) {
      debugPrint('AdMob init error: $e');
    }
  }

  void _setupConnectivity() {
    _netSub = Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.isEmpty || results.every((r) => r == ConnectivityResult.none);
      if (!mounted || offline == isOffline) return;
      setState(() => isOffline = offline);
      if (!offline && pageLoaded) _applyIOSAppWebMode();
    });
  }

  bool get _supportAdFreeActive =>
      DateTime.now().millisecondsSinceEpoch < _supportAdFreeUntil;

  Future<void> _loadSupportRewardState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _supportAdFreeUntil =
          prefs.getInt('cbp_support_ad_free_until') ?? 0;
    } catch (_) {
      _supportAdFreeUntil = 0;
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveSupportRewardState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'cbp_support_ad_free_until',
        _supportAdFreeUntil,
      );
    } catch (_) {}
  }

  void _loadRewarded() {
    if (!_adsReady || _rewardedAd != null) return;

    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(nonPersonalizedAds: true),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd?.dispose();
          _rewardedAd = ad;
          if (mounted) setState(() => _rewardedReady = true);
        },
        onAdFailedToLoad: (error) {
          _rewardedAd = null;
          if (mounted) setState(() => _rewardedReady = false);
          debugPrint('Rewarded load failed: $error');
        },
      ),
    );
  }

  Future<void> _watchSupportAd() async {
    if (_supportAdFreeActive) {
      final leftMs = _supportAdFreeUntil -
          DateTime.now().millisecondsSinceEpoch;
      final leftMin =
          ((leftMs + 59999) ~/ 60000).clamp(1, supportAdFreeMinutes);

      _toast(
        'Thanks for supporting CocBasePro. '
        'Ad-free browsing is active for $leftMin more min.',
      );
      return;
    }

    final ad = _rewardedAd;
    if (ad == null || !_rewardedReady) {
      _toast('Support ad is not ready yet. Please try again shortly.');
      _loadRewarded();
      return;
    }

    _rewardedAd = null;
    _rewardedReady = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadRewarded();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _loadRewarded();
        _toast('Ad could not be shown. Please try again later.');
      },
    );

    ad.show(
      onUserEarnedReward: (_, __) async {
        _supportAdFreeUntil =
            DateTime.now().millisecondsSinceEpoch + supportAdFreeMs;
        internalPagesSinceAd = 0;
        await _saveSupportRewardState();

        if (!mounted) return;
        setState(() {});
        _toast(
          'Thanks for supporting CocBasePro! '
          'Enjoy $supportAdFreeMinutes minutes without interstitial ads.',
        );
      },
    );
  }

  void _loadInterstitial() {
    if (!_adsReady || _interstitialAd != null || _interstitialShowing) return;
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(nonPersonalizedAds: true),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) { _interstitialAd?.dispose(); _interstitialAd = ad; },
        onAdFailedToLoad: (error) {
          _interstitialAd = null;
          debugPrint('Interstitial load failed: $error');
        },
      ),
    );
  }

  void _countFinishedInternalPage(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.host.contains('cocbasepro.com')) return;
    if (url == lastFinishedInternalUrl) return;
    lastFinishedInternalUrl = url;
    if ((url == homeUrl || url == '$homeUrl/') && internalPagesSinceAd == 0) return;
    internalPagesSinceAd++;
    _maybeShowInterstitial();
  }

  void _maybeShowInterstitial() {
    if (_supportAdFreeActive) return;
    if (_interstitialShowing || internalPagesSinceAd < pagesPerInterstitial) return;
    final now = DateTime.now();
    if (now.difference(sessionStartedAt).inSeconds < firstAdDelaySeconds) return;
    if (now.difference(lastInterstitialAt).inSeconds < interstitialCooldownSeconds) return;
    final ad = _interstitialAd;
    if (ad == null) { _loadInterstitial(); return; }

    _interstitialAd = null;
    _interstitialShowing = true;
    internalPagesSinceAd = 0;
    lastInterstitialAt = now;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        _interstitialShowing = false;
        ad.dispose();
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        _interstitialShowing = false;
        ad.dispose();
        _loadInterstitial();
      },
    );
    ad.show();
  }

  Future<NavigationDecision> _handleNavigationRequest(NavigationRequest request) async {
    final uri = Uri.tryParse(request.url);
    if (uri == null || isOffline) return NavigationDecision.prevent;
    final host = uri.host.toLowerCase();

    if (host.contains('cocbasepro.com')) {
      currentUrl = request.url;
      return NavigationDecision.navigate;
    }
    if (host.contains('firebaseio.com')) return NavigationDecision.prevent;


    await _openExternal(request.url);
    return NavigationDecision.prevent;
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) _toast('Cannot open this link.');
  }

  Future<void> _loadNativeTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('cbp_ios_theme');
      if (saved == 'dark' || saved == 'light') {
        _setTheme(saved == 'dark');
      }
    } catch (_) {}
  }

  Future<void> _saveNativeTheme(bool dark) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cbp_ios_theme', dark ? 'dark' : 'light');
    } catch (_) {}
  }

  Future<void> _loadNativeNewsBadge() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt('cbp_ios_unread_news');
      if (saved != null && saved > 0 && mounted) {
        setState(() {
          unreadNews = saved;
          _newsBadgeKnown = true;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveNativeNewsBadge(int count) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('cbp_ios_unread_news', count);
    } catch (_) {}
  }

  void _setNewsBadge(int count, {bool explicit = false}) {
    if (count < 0) return;

    // A missing/temporarily empty web badge must not erase a native unread
    // badge. Zero is accepted only from an explicit bridge/read action.
    if (count == 0 && !explicit && _newsBadgeKnown && unreadNews > 0) {
      return;
    }

    _newsBadgeKnown = true;
    if (mounted && count != unreadNews) {
      setState(() => unreadNews = count);
    }
    unawaited(_saveNativeNewsBadge(count));
  }

  Future<void> _applyIOSAppWebMode() async {
    try {
      await controller.runJavaScript(r'''
(function () {
  const html = document.documentElement;
  const body = document.body;

  html.classList.add(
    'ios-app-mode',
    'cocbase-native-ios',
    'cocbase-app-webview',
    'cocbase-no-ads'
  );

  if (body) {
    body.classList.add(
      'ios-app-mode',
      'cocbase-native-ios',
      'cocbase-app-webview',
      'cocbase-no-ads'
    );
  }

  let style = document.getElementById('cbp-ios-single-menu-v55');
  if (!style) {
    style = document.createElement('style');
    style.id = 'cbp-ios-single-menu-v55';
    document.head.appendChild(style);
  }

  style.textContent = `
    #mobile-nav,
    .bottom-nav,
    #nav-donate-btn,
    #cbp-support-popup,
    [href="#donate-center"],
    .cbp-support-progress {
      display:none !important;
      visibility:hidden !important;
      opacity:0 !important;
      pointer-events:none !important;
      width:0 !important;
      height:0 !important;
      min-height:0 !important;
      max-height:0 !important;
      padding:0 !important;
      margin:0 !important;
      overflow:hidden !important;
    }
  `;

  const normalizeMode = function(value) {
    value = String(value || '').toLowerCase();
    if (value.includes('dark')) return 'dark';
    if (value.includes('light')) return 'light';
    return '';
  };

  const readWebMode = function() {
    // Follow the WEBSITE as source of truth, not the old native cache.
    let mode =
      normalizeMode(html.getAttribute('data-mode')) ||
      normalizeMode(html.getAttribute('data-theme')) ||
      normalizeMode(body && body.getAttribute('data-mode')) ||
      normalizeMode(body && body.getAttribute('data-theme'));

    if (!mode) {
      const hc = String(html.className || '').toLowerCase();
      const bc = String((body && body.className) || '').toLowerCase();
      if (hc.includes('dark') || bc.includes('dark')) mode = 'dark';
      else if (hc.includes('light') || bc.includes('light')) mode = 'light';
    }

    if (!mode) {
      try {
        const keys = ['theme','mode','color-mode','data-mode','cbp-theme','cocbase-theme'];
        for (const key of keys) {
          mode = normalizeMode(localStorage.getItem(key));
          if (mode) break;
        }
      } catch (_) {}
    }

    if (!mode && body) {
      const c = getComputedStyle(body).backgroundColor || '';
      const m = c.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)/i);
      if (m) {
        const r = Number(m[1]), g = Number(m[2]), b = Number(m[3]);
        const luminance = (0.2126*r + 0.7152*g + 0.0722*b) / 255;
        mode = luminance < 0.45 ? 'dark' : 'light';
      }
    }

    if (!mode) {
      mode = window.matchMedia('(prefers-color-scheme: dark)').matches
        ? 'dark'
        : 'light';
    }

    return mode;
  };

  let lastMode = '';
  const sendTheme = function() {
    const mode = readWebMode();
    if (mode && mode !== lastMode) {
      lastMode = mode;
      try { AppTheme.postMessage(mode); } catch (_) {}
    }
  };

  if (!window.__CBP_IOS_THEME_OBSERVER_V55__) {
    window.__CBP_IOS_THEME_OBSERVER_V55__ = true;

    const observer = new MutationObserver(function() {
      requestAnimationFrame(sendTheme);
    });

    observer.observe(html, {
      attributes: true,
      attributeFilter: ['data-mode','data-theme','class','style']
    });

    if (body) {
      observer.observe(body, {
        attributes: true,
        attributeFilter: ['data-mode','data-theme','class','style']
      });
    }

    window.addEventListener('storage', sendTheme);
  }

  // Initial native menu background follows the website immediately.
  sendTheme();
})();
''');
    } catch (_) {}
  }

  void _setTheme(bool dark, {bool persist = false}) {
    if (mounted && dark != isDarkMode) {
      setState(() => isDarkMode = dark);
    }
    if (persist) {
      unawaited(_saveNativeTheme(dark));
    }
  }

  Future<void> _refreshNewsBadge({bool explicitZero = false}) async {
    try {
      final result = await controller.runJavaScriptReturningResult(r'''
(function(){
  const selectors = [
    '#news-badge',
    '#nav-news-badge',
    '.news-badge',
    '[data-news-badge]',
    '[data-unread-news]'
  ];

  for (const selector of selectors) {
    const b = document.querySelector(selector);
    if (!b) continue;

    const raw =
      b.getAttribute('data-unread-news') ||
      b.getAttribute('data-count') ||
      b.textContent ||
      '';

    const m = String(raw).match(/\d+/);
    if (m) return Number(m[0]);
  }

  // -1 means "badge not present/ready"; never treat that as zero.
  return -1;
})();
''');

      final raw = result.toString().replaceAll('"', '').trim();
      final value = int.tryParse(raw);
      if (value == null || value < 0) return;
      _setNewsBadge(value, explicit: explicitZero);
    } catch (_) {}
  }

  Future<void> _openHome() async {
    if (currentUrl == homeUrl || currentUrl == '$homeUrl/') {
      await controller.runJavaScript("window.scrollTo({top:0,behavior:'smooth'});");
    } else {
      currentUrl = homeUrl;
      await controller.loadRequest(Uri.parse(homeUrl));
    }
  }

  Future<bool> _runMenuScript(String script) async {
    try {
      final result = await controller.runJavaScriptReturningResult(script);
      return result.toString().toLowerCase().contains('true');
    } catch (_) { return false; }
  }

  Future<void> _openNews() async {
    await _runMenuScript(r'''(function(){if(typeof window.openNewsPopup==='function'){window.openNewsPopup();return true;}const b=document.getElementById('nav-news-btn');if(b){b.click();return true;}return false;})();''');
    await Future<void>.delayed(const Duration(milliseconds: 450));
    await _refreshNewsBadge(explicitZero: true);
  }

  Future<void> _openFindSource() async {
    final opened = await _runMenuScript(r'''(function(){if(typeof window.closeMobileMore==='function')window.closeMobileMore();if(typeof window.openAIFinder==='function'){window.openAIFinder();return true;}if(typeof window.openAIFinderPopup==='function'){window.openAIFinderPopup();return true;}if(typeof window.CBPMenuOpenAIFinder==='function'){window.CBPMenuOpenAIFinder();return true;}const b=document.getElementById('nav-ai-btn');if(b){b.click();return true;}return false;})();''');
    if (!opened) _toast('Find Source is not available on this page.');
  }

  Future<void> _openSaved() async {
    final opened = await _runMenuScript(r'''(function(){if(typeof window.openSimple==='function'){window.openSimple('saved');return true;}const b=document.getElementById('nav-saved-btn');if(b){b.click();return true;}return false;})();''');
    if (!opened) _toast('Saved Bases is not available on this page.');
  }

  Future<void> _navigateInternal(String path) async {
    Navigator.of(context).pop();
    final uri = Uri.parse('$homeUrl$path');
    currentUrl = uri.toString();
    await controller.loadRequest(uri);
  }

  Future<void> _openWebPopup(String script) async {
    Navigator.of(context).pop();
    await _runMenuScript(script);
  }

  Future<void> _showMoreMenu() async {
    if (moreMenuOpen) return;
    setState(() => moreMenuOpen = true);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final fg = isDarkMode ? const Color(0xFFF8FAFC) : const Color(0xFF111827);
        final bg = isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
        return SafeArea(top: false, child: Container(
          padding: const EdgeInsets.fromLTRB(14,8,14,14),
          decoration: BoxDecoration(color:bg,borderRadius:const BorderRadius.vertical(top:Radius.circular(22))),
          child: Column(mainAxisSize:MainAxisSize.min,children:[
            Container(width:38,height:4,margin:const EdgeInsets.only(bottom:10),decoration:BoxDecoration(color:fg.withValues(alpha:.20),borderRadius:BorderRadius.circular(999))),
            Row(children:[Expanded(child:Text('Explore CocBasePro',style:TextStyle(color:fg,fontSize:16,fontWeight:FontWeight.w900))),IconButton(visualDensity:VisualDensity.compact,onPressed:()=>Navigator.pop(sheetContext),icon:Icon(Icons.close_rounded,color:fg))]),
            const SizedBox(height:4),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 7,
              crossAxisSpacing: 7,
              childAspectRatio: 1.28,
              children: [
                _moreTile(
                  Icons.home_work_rounded,
                  'Town Hall',
                  fg,
                  () => _navigateInternal('/p/free-coc-bases.html?th=all'),
                ),
                _moreTile(
                  Icons.cottage_rounded,
                  'Builder Hall',
                  fg,
                  () => _navigateInternal('/p/free-coc-bases.html?bh=all'),
                ),
                _moreTile(
                  Icons.account_balance_rounded,
                  'Capital Hall',
                  fg,
                  () => _navigateInternal('/p/free-coc-bases.html?ch=all'),
                ),
                _moreTile(
                  Icons.calendar_month_rounded,
                  'Events',
                  fg,
                  () => _openWebPopup(
                    r'''(function(){if(typeof window.openEventPopup==='function'){window.openEventPopup();return true;}return false;})();''',
                  ),
                ),
                _moreTile(
                  Icons.emoji_events_rounded,
                  'Rankings',
                  fg,
                  () => _openWebPopup(
                    r'''(function(){if(typeof window.openSimple==='function'){window.openSimple('topclans');return true;}return false;})();''',
                  ),
                ),
                _moreTile(
                  Icons.auto_awesome_rounded,
                  'Hero Skins',
                  fg,
                  () => _openWebPopup(
                    r'''(function(){if(typeof window.openSimple==='function'){window.openSimple('heroskins');return true;}return false;})();''',
                  ),
                ),
                _moreTile(
                  Icons.favorite_rounded,
                  'Support',
                  const Color(0xFFFACC15),
                  () {
                    Navigator.of(context).pop();
                    _showSupportSheet();
                  },
                ),
                _moreTile(
                  Icons.refresh_rounded,
                  'Reload',
                  fg,
                  () {
                    Navigator.of(context).pop();
                    controller.reload();
                  },
                ),
                _moreTile(
                  Icons.info_outline_rounded,
                  'About',
                  fg,
                  () => _navigateInternal('/p/about.html'),
                ),
              ],
            ),
          ]),
        ));
      },
    );
    if (mounted) setState(() => moreMenuOpen = false);
  }

  Future<void> _showSupportSheet() async {
    final leftMs =
        _supportAdFreeUntil - DateTime.now().millisecondsSinceEpoch;
    final leftMin = leftMs > 0
        ? ((leftMs + 59999) ~/ 60000).clamp(1, supportAdFreeMinutes)
        : 0;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final fg = isDarkMode
            ? const Color(0xFFF8FAFC)
            : const Color(0xFF111827);
        final bg = isDarkMode
            ? const Color(0xFF0F172A)
            : const Color(0xFFF8FAFC);

        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0x33FACC15)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.favorite_rounded,
                  color: Color(0xFFFACC15),
                  size: 34,
                ),
                const SizedBox(height: 8),
                Text(
                  'Support CocBasePro',
                  style: TextStyle(
                    color: fg,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Watch one short ad to support ongoing development '
                  'and server costs.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.68),
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'As a thank-you, you get $supportAdFreeMinutes minutes '
                  'without interstitial ads.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.82),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _watchSupportAd();
                    },
                    icon: Icon(
                      _supportAdFreeActive
                          ? Icons.check_circle_rounded
                          : Icons.ondemand_video_rounded,
                      size: 20,
                    ),
                    label: Text(
                      _supportAdFreeActive
                          ? 'Ad-Free Active · ${leftMin}m left'
                          : 'Watch Ad · Support CocBasePro',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFACC15),
                      foregroundColor: const Color(0xFF111827),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  'Optional · No features are locked behind this ad',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.48),
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _moreTile(IconData icon,String label,Color color,VoidCallback onTap) => Material(
    color:color.withValues(alpha:.055),borderRadius:BorderRadius.circular(14),
    child:InkWell(borderRadius:BorderRadius.circular(14),onTap:onTap,child:Padding(
      padding:const EdgeInsets.symmetric(horizontal:6,vertical:8),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(icon,size:22,color:color),const SizedBox(height:5),Text(label,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(color:color,fontSize:9.5,fontWeight:FontWeight.w800))]),
    )),
  );

  Widget _navItem({required IconData icon,required String label,required VoidCallback onTap,int badge=0,bool emphasized=false}) {
    final fg = isDarkMode ? const Color(0xFFF8FAFC) : const Color(0xFF111827);
    final c = emphasized ? const Color(0xFFFACC15) : fg;
    return Expanded(child:InkWell(borderRadius:BorderRadius.circular(11),onTap:onTap,child:SizedBox(height:45,child:Stack(alignment:Alignment.center,children:[
      Column(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(icon,size:20,color:c),const SizedBox(height:2),Text(label,maxLines:1,overflow:TextOverflow.fade,softWrap:false,style:TextStyle(color:c,fontSize:8.4,fontWeight:FontWeight.w800,height:1))]),
      if(badge>0) Positioned(top:1,right:7,child:Container(constraints:const BoxConstraints(minWidth:15,minHeight:15),padding:const EdgeInsets.symmetric(horizontal:3),alignment:Alignment.center,decoration:const BoxDecoration(color:Color(0xFFEF4444),borderRadius:BorderRadius.all(Radius.circular(999))),child:Text(badge>9?'9+':'$badge',style:const TextStyle(color:Colors.white,fontSize:8,fontWeight:FontWeight.w900))))
    ]))));
  }

  Widget _compactNativeMenu() {
    final bg = isDarkMode ? const Color(0xF207111F) : Colors.white.withValues(alpha:.97);
    return SafeArea(top:false,child:Container(height:52,padding:const EdgeInsets.symmetric(horizontal:4,vertical:3),decoration:BoxDecoration(color:bg,border:Border(top:BorderSide(color:isDarkMode?Colors.white.withValues(alpha:.07):Colors.black.withValues(alpha:.06),width:.5))),child:Material(color:Colors.transparent,child:Row(children:[
      _navItem(icon:Icons.home_rounded,label:'Home',onTap:_openHome),
      _navItem(icon:Icons.article_outlined,label:'News',badge:unreadNews,onTap:_openNews),
      _navItem(icon:Icons.document_scanner_outlined,label:'Find Source',emphasized:true,onTap:_openFindSource),
      _navItem(icon:Icons.bookmark_rounded,label:'Saved',onTap:_openSaved),
      _navItem(icon:Icons.menu_rounded,label:'More',onTap:_showMoreMenu),
    ]))));
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message),duration:const Duration(seconds:2)));
  }

  Future<void> _back() async {
    if (await controller.canGoBack()) await controller.goBack(); else if (mounted) SystemNavigator.pop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && pageLoaded) _applyIOSAppWebMode();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _netSub?.cancel();
    _loadingFinishTimer?.cancel();
    _interstitialAd?.dispose();
    _rewardedAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = isDarkMode
        ? const Color(0xFF020617)
        : const Color(0xFFF8FAFC);

    final overlay = SystemUiOverlayStyle(
      statusBarColor: bg,
      statusBarIconBrightness:
          isDarkMode ? Brightness.light : Brightness.dark,
      statusBarBrightness:
          isDarkMode ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: bg,
      systemNavigationBarIconBrightness:
          isDarkMode ? Brightness.light : Brightness.dark,
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          await _back();
        }
      },
      child: Scaffold(
        backgroundColor: bg,
        bottomNavigationBar:
            Platform.isIOS && !moreMenuOpen ? _compactNativeMenu() : null,
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlay,
          child: Stack(
            children: [
              SafeArea(
                bottom: false,
                child: WebViewWidget(controller: controller),
              ),
              if (webProgress > 0 && webProgress < 100)
                SafeArea(
                  bottom: false,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      value: webProgress / 100,
                      backgroundColor: Colors.transparent,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFFFACC15),
                      ),
                    ),
                  ),
                ),
              if (isOffline)
                Positioned.fill(
                  child: ColoredBox(
                    color: const Color(0xEE020617),
                    child: SafeArea(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.wifi_off_rounded,
                                size: 44,
                                color: Color(0xFFFACC15),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'You are offline',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Reconnect to continue browsing base layouts.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFFCBD5E1),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 14),
                              FilledButton.icon(
                                onPressed: () async {
                                  final results =
                                      await Connectivity().checkConnectivity();

                                  final offline = results.isEmpty ||
                                      results.every(
                                        (r) =>
                                            r == ConnectivityResult.none,
                                      );

                                  if (!mounted) return;

                                  setState(() => isOffline = offline);

                                  if (!offline) {
                                    controller.reload();
                                  }
                                },
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Try Again'),
                              ),
                            ],
                          ),
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
