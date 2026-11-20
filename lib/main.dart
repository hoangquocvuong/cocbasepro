import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:uuid/uuid.dart';
import 'ios_backend.dart';
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
  static const String homeUrl = 'https://basecoc.net';
  static const String rewardedAdUnitId =
      'ca-app-pub-9371341402256787/5585456052';

  static const String bannerAdUnitId =
      'ca-app-pub-9371341402256787/6534238850';

  static const int bannerStartupDelaySeconds = 8;

  static const int resumeHealthCheckDelayMs = 300;
  static const int resumeLongBackgroundSeconds = 15;
  static const int recoveryCooldownSeconds = 8;
  static const String lastInternalUrlKey = 'cbp_last_internal_web_url';

  late final WebViewController controller;
  StreamSubscription<List<ConnectivityResult>>? _netSub;
  final DateTime sessionStartedAt = DateTime.now();

  RewardedAd? _rewardedAd;
  BannerAd? _bannerAd;
  bool _bannerLoaded = false;
  bool _adsReady = false;
  final _api = IosBackend();
  bool _vip = false;
  bool _membershipKnown = false;
  bool _copyBusy = false;
  bool _accountOpen = false;
  bool _inboxOpen = false;
  int _vipUnread = 0;
  Completer<RewardedAd?>? _rewardLoad;
  Timer? _inboxTimer;
  bool _inboxRefreshing = false;
  StreamSubscription<String>? _pushRefresh;
  bool isOffline = false;
  bool pageLoaded = false;
  bool _webShellReady = false;
  bool _hasPresentedFirstPage = false;
  bool isDarkMode = true;
  bool moreMenuOpen = false;
  int webProgress = 0;
  int unreadNews = 0;
  bool _newsBadgeKnown = false;
  Timer? _loadingFinishTimer;
  Timer? _resumeRecoveryTimer;
  String currentUrl = homeUrl;
  String lastFinishedInternalUrl = '';
  DateTime? _backgroundedAt;
  DateTime _lastWebRecoveryAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _resumeRecoveryRunning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller = WebViewController();
    unawaited(_configureAndLoadWebView());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupConnectivity();
      _initDeferredServices();
    });
  }

  Future<void> _configureAndLoadWebView() async {
    // IMPORTANT: WebKit must receive the custom UA BEFORE the first request.
    // In the old cascade, setUserAgent() and loadRequest() were both async
    // but were invoked without awaiting, so the first page could start with
    // Safari's default UA. The template then rendered its web navigation for
    // one frame before the app-side CSS hid it.
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setUserAgent(
      Platform.isIOS ? 'CocBaseProApp-iOS' : 'CocBaseProApp-Android',
    );
    await controller.setBackgroundColor(const Color(0xFF050505));

    await controller.addJavaScriptChannel('Flutter', onMessageReceived: (message) {
        final count = int.tryParse(message.message.trim());
        if (count == null || count < 0) return;
        _setNewsBadge(count, explicit: true);
      });

    await controller.addJavaScriptChannel('AppTheme', onMessageReceived: (message) {
        final dark = message.message.trim().toLowerCase() == 'dark';
        _setTheme(dark, persist: true);
      });

    await controller.addJavaScriptChannel('BaseActionV81', onMessageReceived: (message) {
      unawaited(_handleWebAction(message.message));
    });
    await controller.setNavigationDelegate(NavigationDelegate(
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
              // Only the very first app load is visually covered.
              // For every later navigation keep the previous page visible
              // while WKWebView loads the next one behind it.
              if (!_hasPresentedFirstPage) {
                _webShellReady = false;
              }
              webProgress = 5;
            });
          }

          // Template + UA already suppress the web navigation. This is only
          // a lightweight defensive reinforcement and never blocks painting.
        },
        onPageFinished: (url) async {
          _loadingFinishTimer?.cancel();
          currentUrl = url;

          if (!_hasPresentedFirstPage) {
            // First launch only: make sure iOS web mode is active before
            // revealing the first page.
            await _applyIOSAppWebMode();
          } else {
            // Later navigations: never wait on JS before showing content.
            unawaited(_applyIOSAppWebMode());
          }

          if (mounted) {
            setState(() {
              pageLoaded = true;
              _webShellReady = true;
              _hasPresentedFirstPage = true;
              webProgress = 100;
            });
          }

          final finishedUri = Uri.tryParse(url);
          if (finishedUri != null && (finishedUri.path.startsWith('/api/') || finishedUri.path.startsWith('/e/'))) {
            final id = _premiumId(finishedUri);
            final backUrl = lastFinishedInternalUrl.isEmpty ? homeUrl : lastFinishedInternalUrl;
            await controller.loadRequest(Uri.parse(backUrl));
            if (id != null) unawaited(_premiumCopy(id));
            return;
          }
          if (_isInternalWebUrl(url)) lastFinishedInternalUrl = url;
          unawaited(_saveLastInternalUrl(url));

          Future<void>.delayed(
            const Duration(milliseconds: 350),
            () => _refreshNewsBadge(),
          );
        },
        onWebResourceError: (error) {
          debugPrint('WebView error: ${error.description} mainFrame=${error.isForMainFrame}');
          if (error.isForMainFrame == true && !isOffline) {
            _scheduleResumeRecovery(reason: 'main-frame-error', forceHealthCheck: true);
          }
        },
        onNavigationRequest: _handleNavigationRequest,
      ));

    // UA + delegate are fully installed before the very first navigation.
    await controller.loadRequest(Uri.parse(homeUrl));
  }

  Future<void> _initDeferredServices() async {
    unawaited(_loadNativeTheme());
    if (Platform.isIOS) {
      IosBackend.store.setMethodCallHandler((call) async {
        if (call.method == "transaction") {
          try { await _api.initialize(); await _api.verify(call.arguments as Map); await _refreshMembership(); } catch (e) { _toast("Purchase verification pending: $e"); }
        }
      });
      await _refreshMembership(sync: true);
      unawaited(_restorePushRegistration());
      unawaited(_refreshInbox());
      _inboxTimer = Timer.periodic(const Duration(minutes: 1), (_) => unawaited(_refreshInbox()));
    }
    unawaited(_loadNativeNewsBadge());

    // Let WebKit paint before starting the AdMob SDK.
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    if (!mounted) return;

    try {
      await MobileAds.instance.initialize();
      _adsReady = true;
      _loadRewarded();

      // Keep the fast first paint: request the sticky banner later.
      Future<void>.delayed(
        const Duration(seconds: bannerStartupDelaySeconds),
        () {
          if (mounted) _loadBanner();
        },
      );
    } catch (e) {
      debugPrint('AdMob init error: $e');
    }
  }

  void _setupConnectivity() {
    _netSub = Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.isEmpty || results.every((r) => r == ConnectivityResult.none);
      if (!mounted || offline == isOffline) return;
      setState(() => isOffline = offline);
      if (!offline) {
        if (pageLoaded) unawaited(_applyIOSAppWebMode());
        _scheduleResumeRecovery(reason: 'network-restored', forceHealthCheck: true);
      }
    });
  }

  void _loadBanner() {
    if (!_adsReady || !_membershipKnown || _vip || _bannerAd != null || isOffline) return;

    final ad = BannerAd(
      adUnitId: bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(nonPersonalizedAds: true),
      listener: BannerAdListener(
        onAdLoaded: (loadedAd) {
          if (!mounted) {
            loadedAd.dispose();
            return;
          }
          setState(() => _bannerLoaded = true);
        },
        onAdFailedToLoad: (failedAd, error) {
          failedAd.dispose();
          _bannerAd = null;
          if (mounted) {
            setState(() => _bannerLoaded = false);
          }
          debugPrint('Banner load failed: $error');
        },
      ),
    );

    _bannerAd = ad;
    ad.load();
  }

  bool get _showStickyBanner =>
      Platform.isIOS &&
      _membershipKnown && !_vip &&
      _bannerLoaded &&
      _bannerAd != null &&
      !isOffline &&
      !moreMenuOpen;

  Widget _stickyBanner() {
    final ad = _bannerAd;
    if (ad == null) return const SizedBox.shrink();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      height: _showStickyBanner ? ad.size.height.toDouble() : 0,
      width: double.infinity,
      alignment: Alignment.center,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF020617)
            : const Color(0xFFF8FAFC),
      ),
      child: _showStickyBanner
          ? SizedBox(
              width: ad.size.width.toDouble(),
              height: ad.size.height.toDouble(),
              child: AdWidget(ad: ad),
            )
          : const SizedBox.shrink(),
    );
  }

  Future<RewardedAd?> _loadRewarded() async {
    if (!_adsReady || !_membershipKnown || _vip || !mounted) return null;
    if (_rewardedAd != null) return _rewardedAd;
    if (_rewardLoad != null) return _rewardLoad!.future;
    final load = Completer<RewardedAd?>();
    _rewardLoad = load;
    void finish(RewardedAd? ad) {
      if (load.isCompleted) { ad?.dispose(); return; }
      if (!mounted || _vip) { ad?.dispose(); ad = null; }
      _rewardedAd = ad;
      _rewardLoad = null;
      
      load.complete(ad);
    }
    final timer = Timer(const Duration(seconds: 25), () => finish(null));
    try {
      await RewardedAd.load(adUnitId: rewardedAdUnitId,
        request: const AdRequest(nonPersonalizedAds: true),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) { timer.cancel(); finish(ad); },
          onAdFailedToLoad: (_) { timer.cancel(); finish(null); },
        ));
    } catch (_) { timer.cancel(); finish(null); }
    return load.future;
  }

  String? _premiumId(Uri uri) {
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.port != 443 || !['seo.cocbaseai.com', 'basecoc.net', 'www.basecoc.net'].contains(uri.host)) return null;
    return RegExp(r'^/(?:api/premium/base|e)/([0-9a-fA-F]{32})/?$').firstMatch(uri.path)?.group(1)?.toLowerCase();
  }

  bool _isCoffee(Uri uri) => uri.scheme == 'https' && uri.userInfo.isEmpty && uri.port == 443 &&
      (uri.host == 'buymeacoffee.com' || uri.host == 'www.buymeacoffee.com') && uri.pathSegments.isNotEmpty;

  bool _isLayout(Uri uri) => uri.scheme == 'https' && uri.host == 'link.clashofclans.com' && uri.userInfo.isEmpty && uri.port == 443;

  Future<NavigationDecision> _handleNavigationRequest(NavigationRequest request) async {
    // Navigation callbacks do not prove a user gesture. Never launch Safari here.
    if (isOffline) return NavigationDecision.prevent;
    final uri = Uri.tryParse(request.url);
    final id = uri == null ? null : _premiumId(uri);
    if (id != null) {
      if (request.isMainFrame) unawaited(_handleWebAction(request.url));
      return NavigationDecision.prevent;
    }
    if (uri != null && (uri.path.startsWith('/e/') || uri.path.startsWith('/api/'))) {
      if (request.isMainFrame && _isInternalWebUrl(request.url)) {
        _toast('Unable to identify this base. Please try again.');
      }
      return NavigationDecision.prevent;
    }
    if (_isInternalWebUrl(request.url)) {
      if (request.isMainFrame) currentUrl = request.url;
      return NavigationDecision.navigate;
    }
    return NavigationDecision.prevent;
  }

  DateTime _lastAction = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _handleWebAction(String raw) async {
    if (!mounted || isOffline || raw.length > 4096) return;
    final page = await controller.currentUrl().timeout(const Duration(seconds: 2), onTimeout: () => lastFinishedInternalUrl);
    if (!_isInternalWebUrl(page) && !_isInternalWebUrl(lastFinishedInternalUrl)) return;
    if (raw.startsWith('premium:')) {
      final id = raw.substring(8).toLowerCase();
      if (RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) await _premiumCopy(id);
      return;
    }
    if (raw == 'native-inbox') { await _showNotifications(); return; }
    if (raw == 'native-account') { if (mounted) await _showAccount(); return; }
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    final id = _premiumId(uri);
    if (id == null && !_isLayout(uri) && !_isCoffee(uri)) return;
    final now = DateTime.now();
    if (now.difference(_lastAction).inMilliseconds < 800) return;
    _lastAction = now;
    if (id != null) { await _premiumCopy(id); return; }
    if (_isLayout(uri)) { await _classifyLayout(raw); return; }
    // A native confirmation also protects against a forged JS channel message.
    if (!mounted) return;
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Support BASECOC'), content: const Text('Open Buy Me a Coffee in your browser?'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue'))]));
    if (confirmed == true) await _openExternal(raw);
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.port != 443) return;
    if (!_isLayout(uri) && !_isCoffee(uri) &&
        url != 'https://apps.apple.com/account/subscriptions' &&
        url != 'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/') return;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _toast('Unable to open the selected link.');
    } catch (_) { _toast('Unable to open the selected link.'); }
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

  if (!window.__baseActionV81) {
    window.__baseActionV81 = true;
    document.addEventListener('click', function(e) {
      if (!e.isTrusted || window.top !== window.self) return;
      const a = e.target && e.target.closest && e.target.closest('a[href]');
      if (!a) return;
      let u;
      try { u = new URL(a.href, location.href); } catch (_) { return; }
      if (u.protocol !== 'https:') return;
      const internal = ['basecoc.net','www.basecoc.net'].includes(u.hostname);
      const premium = (internal || u.hostname === 'seo.cocbaseai.com') && /^\/(?:api\/premium\/base|e)\/([0-9a-f]{32})\/?$/i.test(u.pathname);
      if (premium) { e.preventDefault(); e.stopImmediatePropagation(); BaseActionV81.postMessage(u.href); return; }
      if (internal) { if (a.target === '_blank') a.target = '_self'; return; }
      const allowed = u.hostname === 'link.clashofclans.com' ||
        (u.hostname === 'seo.cocbaseai.com' && /^\/api\/premium\/base\/[0-9a-f]{32}$/.test(u.pathname)) ||
        ['buymeacoffee.com','www.buymeacoffee.com'].includes(u.hostname);
      e.preventDefault(); e.stopImmediatePropagation();
      if (allowed) BaseActionV81.postMessage(u.href);
    }, true);
  }

  // Compatibility with the website's existing Android bridge contract.
  if (!window.Android) window.Android = {};
  window.Android.copyPremiumBase = function(id) {
    if (window.top === window.self && /^[0-9a-f]{32}$/i.test(String(id))) {
      BaseActionV81.postMessage('premium:' + id);
    }
  };
  window.Android.openAccount = function() { BaseActionV81.postMessage('native-account'); };
  window.Android.openPremium = window.Android.openAccount;

  // Suppress only the legacy bottom navigation, not the website header.
  if (!document.getElementById('basecoc-hide-legacy-nav')) {
    const css = document.createElement('style');
    css.id = 'basecoc-hide-legacy-nav';
    css.textContent = '#mobile-nav,.bottom-nav,#mobile-more-sheet{display:none!important;visibility:hidden!important;}';
    (document.head || html).appendChild(css);
  }
  function placeAccount() {
    const header = document.querySelector('header');
    if (!header) return;
    const controls = Array.from(header.querySelectorAll('button,a,[role="button"]'));
    const key = el => [el.id,el.className,el.title,el.getAttribute('aria-label'),el.getAttribute('onclick'),el.getAttribute('href')].join(' ');
    const menu = controls.find(el => /hamburger|menu|nav-toggle/i.test(key(el)) && !/account/i.test(key(el)) && el.getBoundingClientRect().width > 0);
    const visible = controls.filter(el => !['basecoc-native-account','basecoc-native-inbox'].includes(el.id) && el.getBoundingClientRect().width > 0);
    const anchor = menu || visible[visible.length-1];
    if (!anchor) return;
    const parent = anchor.parentElement;
    if (!parent) return;
    let button = document.getElementById('basecoc-native-account');
    if (!button) {
      button = document.createElement('button');
      button.id = 'basecoc-native-account';
      button.type = 'button';
      button.title = 'My Account';
      button.setAttribute('aria-label','My Account');
      button.style.cssText = 'display:inline-flex!important;visibility:visible!important;opacity:1!important;align-items:center;justify-content:center;box-sizing:border-box;padding:0;cursor:pointer;flex-shrink:0;';
      button.innerHTML = '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="8" r="3.5"/><path d="M5 21v-2a7 7 0 0 1 14 0v2"/></svg>';
      button.addEventListener('click', function(e) {
        if (e.isTrusted && window.top === window.self) BaseActionV81.postMessage('native-account');
      });
    }
    const vip = window.__basecocVip === true;
    button.title = vip ? 'VIP Account' : 'My Account';
    button.setAttribute('aria-label',button.title);
    if (button.dataset.vip !== String(vip)) {
      button.dataset.vip = String(vip);
      button.innerHTML = vip ? '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M5 2l3 2 4-3 4 3 3-2-2 6H7z" fill="#FACC15" stroke="#A16207"/><circle cx="12" cy="12" r="3"/><path d="M5 23v-2a7 7 0 0 1 14 0v2"/></svg>' : '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="8" r="3.5"/><path d="M5 21v-2a7 7 0 0 1 14 0v2"/></svg>';
    }
    const style = getComputedStyle(anchor);
    const rect = anchor.getBoundingClientRect();
    button.style.width = Math.max(28,Math.min(44,rect.width))+'px';
    button.style.height = Math.max(28,Math.min(44,rect.height))+'px';
    button.style.border = style.border;
    button.style.borderRadius = style.borderRadius;
    button.style.setProperty('color',style.color,'important');
    button.style.setProperty('background',style.backgroundColor,'important');
    if (button.parentElement !== parent || button.nextElementSibling !== anchor) {
      anchor.insertAdjacentElement('beforebegin',button);
    }
    let bell = document.getElementById('basecoc-native-inbox');
    if (!bell) {
      bell = document.createElement('button'); bell.id = 'basecoc-native-inbox'; bell.type = 'button';
      bell.title = 'VIP Notifications'; bell.setAttribute('aria-label', bell.title);
      bell.innerHTML = '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4"/></svg><span style="position:absolute;right:-3px;top:-4px;background:#dc2626;color:white;border-radius:10px;min-width:15px;font-size:10px;line-height:15px;text-align:center"></span>';
      bell.addEventListener('click', e => { if(e.isTrusted && window.top===window.self) BaseActionV81.postMessage('native-inbox'); });
    }
    bell.style.cssText = button.style.cssText + ';position:relative;';
    const count = Number(window.__basecocVipUnread || 0);
    const badge = bell.querySelector('span');
    const label = count > 99 ? '99+' : String(count);
    if (badge.textContent !== label) badge.textContent = label;
    badge.style.display = count > 0 ? 'block' : 'none';
    if (bell.parentElement !== parent || bell.nextElementSibling !== button) button.insertAdjacentElement('beforebegin',bell);
  }
  window.__basecocPlaceAccount = placeAccount;
  placeAccount();
  if (!window.__baseAccountObserver) {
    window.__baseAccountObserver = new MutationObserver(placeAccount);
    window.__baseAccountObserver.observe(html,{childList:true,subtree:true});
  }

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
      unawaited(_syncAccountBadge());
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

  Future<void> _openSupport() async {
    try {
      final result = await controller.runJavaScriptReturningResult(r'''(function(){
        for (const a of document.querySelectorAll('a[href]')) {
          try { const u = new URL(a.href); if (['buymeacoffee.com','www.buymeacoffee.com'].includes(u.hostname)) return u.href; } catch (_) {}
        }
        return '';
      })();''');
      var raw = result.toString();
      if (raw.startsWith('"')) raw = jsonDecode(raw) as String;
      final uri = Uri.tryParse(raw);
      if (uri != null && _isCoffee(uri)) { await _openExternal(raw); return; }
    } catch (_) {}
    _toast('Support link is not available on this page.');
  }

  Future<void> _showBenefits() async {
    await showModalBottomSheet<void>(context: context, builder: (ctx) => SafeArea(child: Padding(
      padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('FREE vs VIP', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        const ListTile(leading: Icon(Icons.person_outline), title: Text('FREE'), subtitle: Text('Free bases • Banner ads • Watch video to unlock premium bases')),
        const ListTile(leading: Icon(Icons.workspace_premium, color: Colors.amber), title: Text('VIP'), subtitle: Text('No ads • Unlimited premium bases • VIP recommendations')),
        FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
      ]))));
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
            Row(children:[Expanded(child:Text('Explore BASECOC',style:TextStyle(color:fg,fontSize:16,fontWeight:FontWeight.w900))),IconButton(visualDensity:VisualDensity.compact,onPressed:()=>Navigator.pop(sheetContext),icon:Icon(Icons.close_rounded,color:fg))]),
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
                  Icons.coffee_rounded,
                  'Support',
                  const Color(0xFFB8860B),
                  () {
                    Navigator.pop(sheetContext);
                    unawaited(_openSupport());
                  },
                ),
                _moreTile(
                  Icons.workspace_premium_outlined,
                  'VIP Benefits',
                  fg,
                  () {
                    Navigator.pop(sheetContext);
                    unawaited(_showBenefits());
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

  Future<void> _classifyLayout(String link) async {
    try {
      final result = await _api.request('base/classify', body: {'link': link}, auth: false);
      if (result['premium'] == false && result['protected'] != true || result['protected'] == false && result['premium'] != true) {
        await _openVerifiedLayout(link);
      } else {
        _toast('Open this premium base using its secure Copy Base button.');
      }
    } catch (_) { _toast('Unable to verify this base. Please try again.'); }
  }

  Future<void> _registerPush(String token) async {
    var device = await _api.storage.read(key: 'ios_device_id');
    if (device == null) { device = const Uuid().v4(); await _api.storage.write(key: 'ios_device_id', value: device); }
    await _api.request('notifications/register', body: {'device_id': device, 'fcm_token': token});
  }

  Future<void> _restorePushRegistration() async {
    try {
      final settings = await _api.request('notifications/settings');
      if (settings['push_enabled'] == true || settings['push_enabled'] == 1) await _enablePush(true, ask: false);
    } catch (_) { /* Firebase setup or registration not available yet. */ }
  }

  Future<void> _enablePush(bool enabled, {bool ask = true}) async {
    await _api.initialize();
    final settings = await _api.request('notifications/settings');
    if (enabled) {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      final permission = ask ? await messaging.requestPermission() : await messaging.getNotificationSettings();
      if (permission.authorizationStatus != AuthorizationStatus.authorized && permission.authorizationStatus != AuthorizationStatus.provisional) throw StateError('Notification permission not granted');
      await messaging.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);
      if (await messaging.getAPNSToken() == null) throw StateError('APNs not ready. Try again shortly.');
      final token = await messaging.getToken();
      if (token == null) throw StateError('Push token unavailable');
      await _registerPush(token);
      await _pushRefresh?.cancel();
      _pushRefresh = messaging.onTokenRefresh.listen((value) async { try { await _registerPush(value); } catch (_) {} });
    } else { await _pushRefresh?.cancel(); _pushRefresh = null; }
    await _api.request('notifications/settings', body: {'push_enabled': enabled, 'email_enabled': settings['email_enabled'] == true || settings['email_enabled'] == 1});
  }

  Future<void> _syncAccountBadge() async {
    try { await controller.runJavaScript('window.__basecocVip = ${_membershipKnown && _vip}; window.__basecocVipUnread = $_vipUnread; if(window.__basecocPlaceAccount) window.__basecocPlaceAccount();').timeout(const Duration(seconds: 3)); } catch (_) {}
  }

  Future<void> _refreshMembership({bool sync = false}) async {
    try {
      if (_api.accountToken == null) await _api.initialize();
      if (sync) {
        final rows = await IosBackend.store.invokeListMethod<dynamic>('entitlements') ?? [];
        for (final row in rows) {
          try { await _api.verify(row as Map); } catch (e) { _toast('Restore requires account verification.'); }
        }
      }
      final data = await _api.request('vip/status');
      if (!mounted) return;
      setState(() { _vip = data['vip'] == true; _membershipKnown = true; });
      unawaited(_syncAccountBadge());
      if (_vip) {
        _bannerAd?.dispose(); _bannerAd = null; _bannerLoaded = false;
        _rewardedAd?.dispose(); _rewardedAd = null;
      } else { _loadBanner(); _loadRewarded(); }
    } catch (_) {
      if (mounted) setState(() => _membershipKnown = false);
      unawaited(_syncAccountBadge());
    }
  }

  Widget _membershipComparison(Color fg, Color subtle) {
    const gold = Color(0xFFFACC15);
    Widget cell(String title, bool vip, List<String> items) => Expanded(child: Container(
      padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: vip ? gold.withValues(alpha: .12) : fg.withValues(alpha: .045), borderRadius: BorderRadius.circular(12), border: Border.all(color: vip ? gold : subtle.withValues(alpha: .2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(vip ? Icons.workspace_premium : Icons.person_outline, size: 18, color: vip ? const Color(0xFFB8870A) : subtle), const SizedBox(width: 5), Text(title, style: TextStyle(color: fg, fontWeight: FontWeight.w800))]),
        const SizedBox(height: 8),
        for (final item in items) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(vip ? Icons.check_circle_outline : Icons.remove_circle_outline, size: 15, color: vip ? const Color(0xFFB8870A) : subtle), const SizedBox(width: 5), Expanded(child: Text(item, style: TextStyle(color: fg, fontSize: 12)))])),
      ])));
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [cell('FREE', false, ['Free layouts', 'Video per premium base', 'Banner ads', 'No VIP alerts']), const SizedBox(width: 8), cell('VIP', true, ['All layouts', 'Instant premium copy', 'Ad-free experience', 'VIP alerts 3× monthly'])]);
  }

  Future<String?> _unlockChoice() => showModalBottomSheet<String>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (ctx) {
    final fg = isDarkMode ? const Color(0xFFF8FAFC) : const Color(0xFF111827);
    final bg = isDarkMode ? const Color(0xFF111827) : Colors.white;
    final subtle = isDarkMode ? const Color(0xFFCBD5E1) : const Color(0xFF475569);
    return Container(decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))), child: SafeArea(top: false, child: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [const Icon(Icons.workspace_premium, color: Color(0xFFEAB308)), const SizedBox(width: 8), Expanded(child: Text('Unlock Premium Base', style: TextStyle(color: fg, fontSize: 20, fontWeight: FontWeight.w800))), IconButton(onPressed: () => Navigator.pop(ctx), icon: Icon(Icons.close, color: fg))]),
      _membershipComparison(fg, subtle), const SizedBox(height: 12),
      Text('VIP base recommendations on the 5th, 15th and 25th via Inbox, push or email (opt-in).', style: TextStyle(color: fg, fontSize: 13)), const SizedBox(height: 12),
      FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFACC15), foregroundColor: Colors.black), onPressed: () => Navigator.pop(ctx, 'vip'), icon: const Icon(Icons.workspace_premium), label: const Text('Explore VIP plans')),
      OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: fg), onPressed: () => Navigator.pop(ctx, 'reward'), icon: const Icon(Icons.play_circle_outline), label: const Text('Watch video • Unlock this base')),
    ])))));
  });

  Future<void> _showAccount() async {
    if (_accountOpen || !mounted) return;
    _accountOpen = true;
    try {
      await _refreshMembership();
      final products = await IosBackend.store.invokeListMethod<dynamic>('products') ?? [];
      if (!mounted) return;
      final action = await showModalBottomSheet<String>(
        context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
        builder: (ctx) {
          final fg = isDarkMode ? const Color(0xFFF8FAFC) : const Color(0xFF111827);
          final bg = isDarkMode ? const Color(0xFF111827) : Colors.white;
          final subtle = isDarkMode ? const Color(0xFFCBD5E1) : const Color(0xFF475569);
          const gold = Color(0xFFFACC15);
          Widget link(String label, String action, IconData icon) => Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2), child: TextButton(
              style: TextButton.styleFrom(foregroundColor: fg, padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5), minimumSize: const Size(0, 44)),
              onPressed: () => Navigator.pop(ctx, action), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 19), const SizedBox(height: 3), Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11))]))));
          return Container(decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
            child: SafeArea(top: false, child: SingleChildScrollView(child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: subtle.withValues(alpha: .35), borderRadius: BorderRadius.circular(4)))),
                Row(children: [const Icon(Icons.account_circle_outlined, color: gold, size: 30), const SizedBox(width: 10),
                  Expanded(child: Text('My Account', style: TextStyle(color: fg, fontSize: 20, fontWeight: FontWeight.w800))),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: Icon(Icons.close, color: fg))]),
                Text(_membershipKnown ? (_vip ? 'Current plan: VIP' : 'Current plan: FREE') : 'Membership unavailable', style: TextStyle(color: subtle, fontSize: 12)),
                const SizedBox(height: 8), _membershipComparison(fg, subtle),
                const SizedBox(height: 6), Text('VIP alerts: 5th, 15th & 25th • Inbox, push & email (opt-in)', style: TextStyle(color: subtle, fontSize: 11)),
                if (!_vip) ...[
                  const SizedBox(height: 8),
                  if (products.isEmpty) Text('Plans temporarily unavailable', style: TextStyle(color: subtle)),
                  Row(children: [for (final id in ['premium_monthly', 'premium_yearly'])
                    for (final p in products.where((p) => p['id'] == id)) Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: InkWell(
                      onTap: () => Navigator.pop(ctx, id), borderRadius: BorderRadius.circular(12), child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 4), decoration: BoxDecoration(color: id == 'premium_yearly' ? gold : fg.withValues(alpha: .07), borderRadius: BorderRadius.circular(12), border: Border.all(color: gold)),
                        child: Column(children: [Text(id == 'premium_monthly' ? 'Monthly' : 'Yearly', style: TextStyle(color: id == 'premium_yearly' ? Colors.black : fg, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 5), Text('${p['price']}', textAlign: TextAlign.center, style: TextStyle(color: id == 'premium_yearly' ? Colors.black : fg, fontWeight: FontWeight.w800, fontSize: 15))]))))) ]),
                  const SizedBox(height: 7), Text('Auto-renews unless cancelled in Apple subscriptions.', style: TextStyle(color: subtle, fontSize: 11)),
                ],
                Divider(color: subtle.withValues(alpha: .24)),
                Row(children: [link('Restore', 'restore', Icons.restore), link('Manage Plan', 'manage', Icons.settings_outlined), link('Email Preferences', 'email', Icons.mail_outline)]),
                Wrap(alignment: WrapAlignment.center, spacing: 12, children: [for (final item in ['terms', 'privacy']) TextButton(style: TextButton.styleFrom(foregroundColor: subtle, minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 4)), onPressed: () => Navigator.pop(ctx, item), child: Text(item == 'terms' ? 'Terms of Use' : 'Privacy Policy', style: const TextStyle(fontSize: 11)))]),
              ])))));
        },
      );
      if (action == null) return;
      if (action == 'manage') { await _openExternal('https://apps.apple.com/account/subscriptions'); return; }
      if (action == 'terms') { await _openExternal('https://www.apple.com/legal/internet-services/itunes/dev/stdeula/'); return; }
      if (action == 'privacy') { await controller.loadRequest(Uri.parse('$homeUrl/p/privacy-policy.html')); return; }
      if (action == 'benefits') { await _showBenefits(); return; }
      if (action == 'email') { await _emailPreferences(); return; }
      await _api.initialize();
      if (action == 'restore') {
        final rows = await IosBackend.store.invokeListMethod<dynamic>('restore') ?? [];
        for (final row in rows) { await _api.verify(row as Map, restore: true); }
        _toast(rows.isEmpty ? 'No active purchase found.' : 'Purchases checked.');
      } else {
        final preference = await _emailForm();
        if (preference == null) return;
        final tx = await IosBackend.store.invokeMapMethod<String, dynamic>('buy', {'id': action, 'token': _api.accountToken});
        if (tx != null) { await _api.verify(tx); await _refreshMembership(); if (_vip) await _saveEmail(preference); }
      }
      await _refreshMembership();
    } catch (e) { _toast('$e'); } finally { _accountOpen = false; }
  }

  Future<Map<String, dynamic>?> _emailForm({String initial = '', bool enabled = true}) async {
    if (!mounted) return null;
    final email = TextEditingController(text: initial);
    final key = GlobalKey<FormState>();
    try {
      return await showModalBottomSheet<Map<String, dynamic>>(context: context, isScrollControlled: true,
        builder: (ctx) => StatefulBuilder(builder: (ctx, update) => SafeArea(child: Padding(
          padding: EdgeInsets.fromLTRB(18, 18, 18, MediaQuery.of(ctx).viewInsets.bottom + 18),
          child: SingleChildScrollView(child: Form(key: key, child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('VIP Email Notifications', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            CheckboxListTile(value: enabled, onChanged: (v) => update(() => enabled = v ?? false), title: const Text('Receive selected VIP bases'), subtitle: const Text('Email only for curated VIP base releases during your membership. No promotional emails.')),
            if (enabled) TextFormField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email address'), validator: (v) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v?.trim() ?? '') ? null : 'Enter a valid email'),
            FilledButton(onPressed: () { if (key.currentState!.validate()) Navigator.pop(ctx, {'email_enabled': enabled, 'email': enabled ? email.text.trim() : ''}); }, child: const Text('Continue')),
          ])))))));
    } finally { email.dispose(); }
  }

  Future<void> _saveEmail(Map<String, dynamic> preference) async {
    try {
      final settings = await _api.request('notifications/settings');
      await _api.request('notifications/settings', body: {...preference, 'push_enabled': settings['push_enabled'] == true || settings['push_enabled'] == 1});
      final updated = await _api.request('notifications/settings');
      final enabled = updated['email_enabled'] == true || updated['email_enabled'] == 1;
      if (enabled != preference['email_enabled'] || (enabled && updated['email'] != preference['email'])) throw StateError('Email not saved');
    } catch (_) { _toast('VIP is active. Email preference could not be saved. Update it later in My Account.'); }
  }

  Future<void> _emailPreferences() async {
    if (!_vip) { _toast('Email alerts are a VIP benefit.'); return; }
    final settings = await _api.request('notifications/settings');
    final choice = await _emailForm(initial: '${settings['email'] ?? ''}', enabled: settings['email_enabled'] == true || settings['email_enabled'] == 1);
    if (choice != null) await _saveEmail(choice);
  }

  List<dynamic> _inboxItems(Map<String, dynamic> data) => (data['items'] ?? data['inbox'] ?? []) as List;
  Future<void> _refreshInbox() async {
    if (_inboxRefreshing || !mounted || !_membershipKnown) return;
    if (!_vip) { _vipUnread = 0; await _syncAccountBadge(); return; }
    _inboxRefreshing = true;
    try {
      final inbox = await _api.request('notifications/inbox');
      final count = inbox['unread_count'] ?? inbox['unread'];
      _vipUnread = count is num ? count.toInt() : _inboxItems(inbox).where((i) => i is Map && (i['read'] == false || i['is_read'] == false || (i.containsKey('read_at') && i['read_at'] == null))).length;
      await _syncAccountBadge();
    } catch (_) {} finally { _inboxRefreshing = false; }
  }

  Future<void> _showNotifications() async {
    if (_inboxOpen || !mounted) return;
    _inboxOpen = true;
    try {
      await _api.initialize();
      if (!_vip) { _toast('VIP notifications are available to members.'); return; }
      final inbox = await _api.request('notifications/inbox');
      final items = _inboxItems(inbox).take(5).toList();
      if (!mounted) return;
      await showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (ctx) => SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [const Expanded(child: Text('VIP Notifications', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))), IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close))]),
        if (items.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('No new VIP notifications.')),
        for (final item in items) ListTile(leading: const Icon(Icons.notifications_outlined), title: Text('${item['title'] ?? ''}'), subtitle: Text('${item['body'] ?? ''}'), onTap: () { final url = '${item['url'] ?? item['link'] ?? ''}'; if (_isInternalWebUrl(url)) { Navigator.pop(ctx); unawaited(controller.loadRequest(Uri.parse(url))); } }),
        if (items.isNotEmpty) TextButton(onPressed: () async { try { await _api.request('notifications/read-all', body: {}); _vipUnread = 0; await _syncAccountBadge(); if (ctx.mounted) Navigator.pop(ctx); } catch (_) { _toast('Unable to mark notifications as read.'); } }, child: const Text('Mark all as read')),
      ])))));
    } catch (_) { _toast('Notifications unavailable. Try again later.'); } finally { _inboxOpen = false; unawaited(_refreshInbox()); }
  }

  Future<void> _premiumCopy(String id) async {
    if (_copyBusy) return;
    _copyBusy = true;
    bool progress = false;
    void busy(String message) { if (mounted) { ScaffoldMessenger.of(context).hideCurrentSnackBar(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(minutes: 3))); progress = true; } }
    void clear() { if (progress && mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar(); progress = false; }
    try {
      if (!_membershipKnown) await _refreshMembership().timeout(const Duration(seconds: 15));
      if (!_membershipKnown) throw StateError('Membership unavailable');
      if (_vip) { await _openVerifiedLayout(await _api.copy(id)); return; }
      if (!mounted) return;
      final action = await _unlockChoice();
      if (action == 'vip') { await _showAccount(); if (_membershipKnown && _vip) await _openVerifiedLayout(await _api.copy(id)); return; }
      if (action != 'reward') return;
      busy('Loading video…');
      final saved = await _api.storage.read(key: 'reward_$id');
      if (saved != null) {
        final previous = Map<String, dynamic>.from(jsonDecode(saved) as Map);
        if (DateTime.now().millisecondsSinceEpoch < (previous['deadline'] as int)) {
          busy('Opening base…');
          if (await _claimReward(id, previous)) return;
          clear(); _toast('Video reward is still pending. Please try again later.'); return;
        }
        await _api.storage.delete(key: 'reward_$id');
      }
      if (!_adsReady) { await MobileAds.instance.initialize().timeout(const Duration(seconds: 15)); _adsReady = true; }
      final ad = await _loadRewarded().timeout(const Duration(seconds: 30));
      if (ad == null || !mounted) { clear(); _toast('No video available. Please try again.'); return; }
      final start = await _api.request('reward/start', body: {'base_id': id}).timeout(const Duration(seconds: 20));
      await ad.setServerSideOptions(ServerSideVerificationOptions(customData: start['custom_data'] as String));
      _rewardedAd = null;
      final completed = Completer<bool>();
      bool earned = false;
      ad.fullScreenContentCallback = FullScreenContentCallback(onAdDismissedFullScreenContent: (a) { a.dispose(); if (!completed.isCompleted) completed.complete(earned); }, onAdFailedToShowFullScreenContent: (a, e) { a.dispose(); if (!completed.isCompleted) completed.complete(false); });
      clear();
      try { await ad.show(onUserEarnedReward: (_, __) { earned = true; }); } catch (_) { ad.dispose(); rethrow; }
      final watched = await completed.future.timeout(const Duration(minutes: 5));
      unawaited(_loadRewarded());
      if (!watched) { _toast('Video not completed.'); return; }
      start['deadline'] = DateTime.now().millisecondsSinceEpoch + 23 * 3600000;
      await _api.storage.write(key: 'reward_$id', value: jsonEncode(start));
      busy('Opening base…');
      if (!await _claimReward(id, start)) { clear(); _toast('Video reward is still pending. Please try again later.'); }
    } catch (_) { clear(); _toast('Unable to unlock this base. Please try again.'); } finally { clear(); _copyBusy = false; }
  }

  Future<bool> _claimReward(String id, Map<String, dynamic> start) async {
    final until = DateTime.now().add(const Duration(seconds: 65));
    while (mounted && DateTime.now().isBefore(until)) {
      try {
        final remaining = until.difference(DateTime.now());
        if (remaining.isNegative) break;
        final claim = await _api.request('reward/claim', body: {'custom_data': start['custom_data'], 'claim_secret': start['claim_secret']}).timeout(remaining);
        if (claim['link'] is String) { await _openVerifiedLayout(claim['link'] as String); await _api.storage.delete(key: 'reward_$id'); return true; }
      } on TimeoutException { return false; } on ApiFailure catch (e) { if (e.status != 409 && e.status != 425) rethrow; }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return false;
  }

  Future<void> _openVerifiedLayout(String link) async {
    final uri = Uri.parse(link);
    if (!_isLayout(uri)) throw StateError('Invalid layout link');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) { throw StateError('Could not open Clash of Clans. Please try again.'); }
  }

  Widget _moreTile(IconData icon,String label,Color color,VoidCallback onTap) => Material(
    color:color.withValues(alpha:.055),borderRadius:BorderRadius.circular(14),
    child:InkWell(borderRadius:BorderRadius.circular(14),onTap:onTap,child:Padding(
      padding:const EdgeInsets.symmetric(horizontal:6,vertical:8),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(icon,size:22,color:color),const SizedBox(height:5),Text(label,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(color:color,fontSize:9.5,fontWeight:FontWeight.w800))]),
    )),
  );

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message),duration:const Duration(seconds:2)));
  }

  Future<void> _back() async {
    if (await controller.canGoBack()) await controller.goBack(); else if (mounted) SystemNavigator.pop();
  }


  bool _isInternalWebUrl(String? raw) {
    if (raw == null || raw.trim().isEmpty) return false;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    return uri.scheme == 'https' && uri.userInfo.isEmpty && uri.port == 443 && (host == 'basecoc.net' || host == 'www.basecoc.net');
  }

  Future<void> _saveLastInternalUrl(String url) async {
    if (!_isInternalWebUrl(url)) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(lastInternalUrlKey, url);
    } catch (_) {}
  }

  Future<String> _recoveryTargetUrl() async {
    if (_isInternalWebUrl(currentUrl)) return currentUrl;
    if (_isInternalWebUrl(lastFinishedInternalUrl)) return lastFinishedInternalUrl;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(lastInternalUrlKey);
      if (_isInternalWebUrl(saved)) return saved!;
    } catch (_) {}
    return homeUrl;
  }

  Future<bool> _isWebViewHealthy() async {
    try {
      final result = await controller.runJavaScriptReturningResult(
        r'''(function(){
          try {
            var href = String(location.href || '');
            var ready = String(document.readyState || '');
            var body = document.body;
            var bodySize = body ? String(body.innerHTML || '').length : 0;
            var rootSize = document.documentElement
              ? String(document.documentElement.innerHTML || '').length : 0;
            if (!href || href === 'about:blank') return 'BAD|blank';
            if (!body) return 'BAD|no-body';
            if (ready !== 'interactive' && ready !== 'complete') return 'BAD|ready-' + ready;
            if (bodySize < 100 && rootSize < 300) return 'BAD|empty';
            return 'OK|' + href + '|' + bodySize + '|' + rootSize;
          } catch (e) {
            return 'BAD|js|' + String(e);
          }
        })();''',
      );
      final probe = result.toString();
      debugPrint('WebView resume probe: $probe');
      return probe.contains('OK|');
    } catch (e) {
      debugPrint('WebView resume probe failed: $e');
      return false;
    }
  }

  void _scheduleResumeRecovery({
    required String reason,
    bool forceHealthCheck = false,
  }) {
    _resumeRecoveryTimer?.cancel();
    _resumeRecoveryTimer = Timer(
      Duration(milliseconds: forceHealthCheck ? 80 : resumeHealthCheckDelayMs),
      () => unawaited(
        _recoverWebViewIfNeeded(
          reason: reason,
          forceHealthCheck: forceHealthCheck,
        ),
      ),
    );
  }

  Future<void> _recoverWebViewIfNeeded({
    required String reason,
    bool forceHealthCheck = false,
  }) async {
    if (!mounted || isOffline || _resumeRecoveryRunning) return;

    final now = DateTime.now();
    if (now.difference(_lastWebRecoveryAt).inSeconds <
        recoveryCooldownSeconds) {
      return;
    }

    final backgroundDuration = _backgroundedAt == null
        ? Duration.zero
        : now.difference(_backgroundedAt!);

    final longBackground =
        backgroundDuration.inSeconds >= resumeLongBackgroundSeconds;

    _resumeRecoveryRunning = true;

    try {
      // V7.4 IMPORTANT:
      // DOM health is NOT enough after iOS background reclaim.
      // WKWebView can still have HTML/document.readyState while the page's
      // JavaScript/Firebase runtime is stale or permanently disconnected.
      //
      // Therefore after a meaningful background period we ALWAYS perform a
      // real page reload. This recreates the website JS runtime and forces
      // Firebase to initialise/reconnect from scratch.
      if (longBackground) {
        _lastWebRecoveryAt = DateTime.now();
        final target = await _recoveryTargetUrl();

        debugPrint(
          'V7.4 force runtime restore after $reason '
          'background=${backgroundDuration.inSeconds}s target=$target',
        );

        if (mounted) {
          setState(() {
            pageLoaded = false;
            webProgress = 5;
          });
        }

        try {
          await controller
              .reload()
              .timeout(const Duration(seconds: 6));
        } catch (e) {
          debugPrint('V7.4 reload failed/timeout: $e');

          // If the old WKWebView content process is too damaged to reload,
          // issue a fresh navigation to the last known-good internal URL.
          await controller
              .loadRequest(Uri.parse(target))
              .timeout(const Duration(seconds: 8));
        }

        return;
      }

      // Short resumes/network restoration do not force a reload.
      // Probe the document first so ordinary app switching stays seamless.
      if (forceHealthCheck) {
        final healthy = await _isWebViewHealthy()
            .timeout(
              const Duration(seconds: 3),
              onTimeout: () => false,
            );

        if (!healthy) {
          _lastWebRecoveryAt = DateTime.now();
          final target = await _recoveryTargetUrl();

          debugPrint(
            'V7.4 unhealthy WebView after $reason; '
            'fresh navigation to $target',
          );

          if (mounted) {
            setState(() {
              pageLoaded = false;
              webProgress = 5;
            });
          }

          await controller
              .loadRequest(Uri.parse(target))
              .timeout(const Duration(seconds: 8));

          return;
        }
      }

      if (pageLoaded) {
        unawaited(_applyIOSAppWebMode());
        unawaited(_refreshNewsBadge());
      }
    } catch (e) {
      debugPrint('V7.4 WKWebView/Firebase recovery failed: $e');

      try {
        final target = await _recoveryTargetUrl();
        await controller.loadRequest(Uri.parse(target));
      } catch (_) {
        try {
          await controller.loadRequest(Uri.parse(homeUrl));
        } catch (_) {}
      }
    } finally {
      _resumeRecoveryRunning = false;
      _backgroundedAt = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _scheduleResumeRecovery(reason: 'app-resumed');
        if (Platform.isIOS && !_copyBusy) { unawaited(_refreshMembership().then((_) => _refreshInbox())); }
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _backgroundedAt ??= DateTime.now();
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    IosBackend.store.setMethodCallHandler(null);
    _netSub?.cancel();
    _pushRefresh?.cancel();
    _inboxTimer?.cancel();
    _loadingFinishTimer?.cancel();
    _resumeRecoveryTimer?.cancel();
    _rewardedAd?.dispose();
    _bannerAd?.dispose();
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
        bottomNavigationBar: Platform.isIOS && _showStickyBanner
            ? SafeArea(top: false, child: _stickyBanner())
            : null,
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlay,
          child: Stack(
            children: [
              SafeArea(
                bottom: !_showStickyBanner,
                child: AnimatedOpacity(
                  opacity: (_hasPresentedFirstPage || _webShellReady) ? 1 : 0,
                  duration: const Duration(milliseconds: 70),
                  child: WebViewWidget(controller: controller),
                ),
              ),

              // Cold-start cover only. Never put a solid light/dark screen
              // between normal page navigations after the first page is shown.
              if (!_hasPresentedFirstPage && !_webShellReady)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: bg,
                    ),
                  ),
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
