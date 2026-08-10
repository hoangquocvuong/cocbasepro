import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/base_result.dart';
import '../widgets/bottom_nav.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String searchApi =
      'https://api.cocbasepro.com/image-search/api/search';
  static const String actionApi =
      'https://api.cocbasepro.com/image-search/api/search-action';
  static const String feedbackApi =
      'https://api.cocbasepro.com/image-search/api/search-feedback';

  // Existing production iOS AdMob IDs from the uploaded project.
  static const String bannerAdUnitId =
      'ca-app-pub-9371341402256787/4621781605';
  static const String interstitialAdUnitId =
      'ca-app-pub-9371341402256787/2615399517';
  static const String rewardedAdUnitId =
      'ca-app-pub-9371341402256787/2152365082';

  static const int adFreeDurationMs = 15 * 60 * 1000;
  static const int interstitialMinSearches = 4;
  static const int interstitialCooldownMs = 90 * 1000;

  final ImagePicker picker = ImagePicker();
  final ScrollController scrollController = ScrollController();
  final GlobalKey resultsKey = GlobalKey();

  File? selectedImage;
  bool loading = false;
  bool analysisVisible = false;
  String currentSearchId = '';

  List<BaseResult> results = [];
  List<BaseResult> savedBases = [];

  BannerAd? bannerAd;
  InterstitialAd? interstitialAd;
  RewardedAd? rewardedAd;
  bool bannerReady = false;
  bool rewardedReady = false;

  int adFreeUntil = 0;
  int searchesSinceInterstitial = 0;
  int lastInterstitialAt = 0;

  bool get adFreeActive =>
      DateTime.now().millisecondsSinceEpoch < adFreeUntil;

  @override
  void initState() {
    super.initState();
    _loadLocalState();
    _loadInterstitial();
    _loadRewarded();
  }

  @override
  void dispose() {
    bannerAd?.dispose();
    interstitialAd?.dispose();
    rewardedAd?.dispose();
    scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLocalState() async {
    final prefs = await SharedPreferences.getInstance();

    final savedRaw = prefs.getString('saved_source_bases');
    if (savedRaw != null && savedRaw.isNotEmpty) {
      try {
        final list = jsonDecode(savedRaw) as List<dynamic>;
        savedBases = list
            .whereType<Map>()
            .map((e) => BaseResult.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {}
    }

    adFreeUntil = prefs.getInt('reward_ad_free_until') ?? 0;
    searchesSinceInterstitial =
        prefs.getInt('searches_since_interstitial') ?? 0;
    lastInterstitialAt = prefs.getInt('last_interstitial_at') ?? 0;

    if (mounted) setState(() {});

    if (!adFreeActive) {
      _loadBanner();
    }
  }

  Future<void> _persistAdState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('reward_ad_free_until', adFreeUntil);
    await prefs.setInt(
      'searches_since_interstitial',
      searchesSinceInterstitial,
    );
    await prefs.setInt('last_interstitial_at', lastInterstitialAt);
  }

  Future<void> _pickImage() async {
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;

    setState(() {
      selectedImage = File(file.path);
      results = [];
      currentSearchId = '';
    });
  }

  void _reset() {
    setState(() {
      selectedImage = null;
      results = [];
      currentSearchId = '';
      loading = false;
    });
  }

  void _loadBanner() {
    if (adFreeActive) {
      bannerAd?.dispose();
      bannerAd = null;
      bannerReady = false;
      return;
    }

    bannerAd?.dispose();
    bannerReady = false;

    bannerAd = BannerAd(
      adUnitId: bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (!mounted || adFreeActive) return;
          setState(() => bannerReady = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (mounted) setState(() => bannerReady = false);
        },
      ),
    )..load();
  }

  void _loadInterstitial() {
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          interstitialAd?.dispose();
          interstitialAd = ad;
        },
        onAdFailedToLoad: (_) {
          interstitialAd = null;
        },
      ),
    );
  }

  void _loadRewarded() {
    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          rewardedAd?.dispose();
          rewardedAd = ad;
          if (mounted) setState(() => rewardedReady = true);
        },
        onAdFailedToLoad: (_) {
          rewardedAd = null;
          if (mounted) setState(() => rewardedReady = false);
        },
      ),
    );
  }

  Future<void> _watchRewardedForAdFree() async {
    if (adFreeActive) {
      _toast('15-minute Ad-Free is already active.');
      return;
    }

    final ad = rewardedAd;
    if (ad == null || !rewardedReady) {
      _toast('Rewarded ad is not ready yet. Please try again shortly.');
      _loadRewarded();
      return;
    }

    rewardedAd = null;
    rewardedReady = false;

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadRewarded();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _loadRewarded();
      },
    );

    ad.show(
      onUserEarnedReward: (_, __) async {
        adFreeUntil =
            DateTime.now().millisecondsSinceEpoch + adFreeDurationMs;

        bannerAd?.dispose();
        bannerAd = null;
        bannerReady = false;

        await _persistAdState();

        if (!mounted) return;
        setState(() {});
        _toast('15 minutes Ad-Free activated.');
      },
    );
  }

  Future<void> _countSearchAndMaybeShowInterstitial() async {
    searchesSinceInterstitial++;
    await _persistAdState();

    if (adFreeActive) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final enoughSearches =
        searchesSinceInterstitial >= interstitialMinSearches;
    final enoughTime =
        now - lastInterstitialAt >= interstitialCooldownMs;

    final ad = interstitialAd;
    if (!enoughSearches || !enoughTime || ad == null) return;

    interstitialAd = null;
    searchesSinceInterstitial = 0;
    lastInterstitialAt = now;
    await _persistAdState();

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _loadInterstitial();
      },
    );

    ad.show();
  }

  Future<void> _search() async {
    if (loading) return;

    final file = selectedImage;
    if (file == null) {
      _toast('Please choose an image first.');
      return;
    }

    await _countSearchAndMaybeShowInterstitial();

    setState(() {
      loading = true;
      results = [];
      analysisVisible = true;
    });

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(searchApi),
      );

      request.headers['User-Agent'] = 'COCBASE-AI-iOS';
      request.files.add(
        await http.MultipartFile.fromPath(
          'image',
          file.path,
          filename: file.uri.pathSegments.isEmpty
              ? 'base_image.jpg'
              : file.uri.pathSegments.last,
        ),
      );

      final streamed = await request.send().timeout(
        const Duration(seconds: 60),
      );
      final response = await http.Response.fromStream(streamed);

      Map<String, dynamic> data = {};
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}

      if (response.statusCode == 429) {
        _toast(
          'Monthly web discovery is full. Known Source DB images still work.',
        );
        return;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detail = (data['detail'] ?? data['error'] ?? '').toString();
        throw Exception(
          detail.isEmpty ? 'Search HTTP ${response.statusCode}' : detail,
        );
      }

      currentSearchId = (data['searchId'] ?? '').toString();

      final list = data['results'] as List<dynamic>? ?? [];
      final parsed = list
          .whereType<Map>()
          .map((e) => BaseResult.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.link.isNotEmpty)
          .toList();

      if (!mounted) return;

      setState(() {
        results = parsed;
      });

      if (parsed.isEmpty) {
        _toast('No reliable Clash of Clans source found yet.');
      } else {
        final localHit = data['sourceDbHit'] == true ||
            (data['cacheType']?.toString().isNotEmpty ?? false);
        _toast(
          localHit
              ? 'Source found from local data.'
              : 'Image sources found.',
        );
      }
    } catch (e) {
      if (mounted) {
        _toast('Image source search failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
          analysisVisible = false;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToResults();
        });
      }
    }
  }

  Future<void> _trackAction(
    String action,
    int rank,
    String url,
  ) async {
    final id = int.tryParse(currentSearchId);
    if (id == null) return;

    try {
      await http.post(
        Uri.parse(actionApi),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'searchId': id,
          'action': action,
          'rank': rank,
          'url': url,
        }),
      );
    } catch (_) {}
  }

  Future<void> _feedback(String value) async {
    final id = int.tryParse(currentSearchId);
    if (id == null) return;

    try {
      await http.post(
        Uri.parse(feedbackApi),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'searchId': id,
          'feedback': value,
        }),
      );
    } catch (_) {}
  }

  Future<void> _openSource(BaseResult item, int rank) async {
    await _trackAction('open_result', rank, item.link);

    final uri = Uri.tryParse(item.link);
    if (uri == null) {
      _toast('Source link is not available.');
      return;
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _confirmCorrect(BaseResult item, int rank) async {
    await _trackAction('open_result', rank, item.link);
    await _feedback('found');
    _toast('Correct source recorded. Thank you!');
  }

  Future<void> _save(BaseResult item) async {
    final exists = savedBases.any((e) => e.link == item.link);
    if (exists) {
      _toast('Already saved.');
      return;
    }

    setState(() => savedBases.add(item));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'saved_source_bases',
      jsonEncode(savedBases.map((e) => e.toJson()).toList()),
    );

    _toast('Source saved.');
  }

  Future<void> _removeSaved(BaseResult item) async {
    setState(() {
      savedBases.removeWhere((e) => e.link == item.link);
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'saved_source_bases',
      jsonEncode(savedBases.map((e) => e.toJson()).toList()),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _scrollToResults() {
    final context = resultsKey.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      alignment: 0.08,
    );
  }

  Widget _glassCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(14),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xD90F172A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x2638BDF8)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x44000000),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0x55FACC15)),
            color: const Color(0x221E293B),
          ),
          child: const Icon(
            Icons.travel_explore_rounded,
            color: Color(0xFFFACC15),
            size: 27,
          ),
        ),
        const SizedBox(width: 11),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'COCBASE AI',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .4,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Free Image Source Finder',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 9,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: const Color(0x1822C55E),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: const Color(0x3322C55E)),
          ),
          child: const Text(
            'FREE',
            style: TextStyle(
              color: Color(0xFF86EFAC),
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  Widget _freeStatusCard() {
    final remainingMs =
        adFreeUntil - DateTime.now().millisecondsSinceEpoch;
    final minutes = remainingMs > 0
        ? ((remainingMs + 59999) ~/ 60000)
        : 0;

    return _glassCard(
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FREE IMAGE SOURCE SEARCH',
                  style: TextStyle(
                    color: Color(0xFF86EFAC),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .5,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'No search limit',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Cache + Source DB checked first',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          Text(
            adFreeActive ? 'Ad-Free ${minutes}m' : 'Ad-supported',
            style: TextStyle(
              color: adFreeActive
                  ? const Color(0xFF86EFAC)
                  : const Color(0xFFFACC15),
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _rewardCard() {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton.icon(
        onPressed: _watchRewardedForAdFree,
        icon: const Icon(Icons.ondemand_video_rounded, size: 19),
        label: Text(
          adFreeActive
              ? '15 min Ad-Free Active'
              : 'Watch Ad · Get 15 min Ad-Free',
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFFACC15),
          side: const BorderSide(color: Color(0x55FACC15)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget _imagePickerCard() {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        width: double.infinity,
        height: 245,
        decoration: BoxDecoration(
          color: const Color(0xAA0F172A),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: const Color(0x5538BDF8),
            width: 1.2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: selectedImage == null
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate_rounded,
                    color: Color(0xFF38BDF8),
                    size: 46,
                  ),
                  SizedBox(height: 9),
                  Text(
                    'Upload Base Screenshot',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'PNG · JPG · WEBP',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                    ),
                  ),
                ],
              )
            : Image.file(
                selectedImage!,
                fit: BoxFit.contain,
              ),
      ),
    );
  }

  Widget _imageActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.photo_library_rounded, size: 18),
            label: const Text('Choose'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF38BDF8),
              side: const BorderSide(color: Color(0x5538BDF8)),
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Reset'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFE2E8F0),
              side: const BorderSide(color: Color(0x22FFFFFF)),
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _searchButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: FilledButton.icon(
        onPressed: loading ? null : _search,
        icon: const Icon(Icons.search_rounded, size: 22),
        label: Text(
          loading ? 'Searching Image Sources...' : 'Find Image Source',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFFACC15),
          foregroundColor: const Color(0xFF111827),
          disabledBackgroundColor: const Color(0xFF665D22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
    );
  }

  Widget _banner() {
    if (adFreeActive || !bannerReady || bannerAd == null) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: bannerAd!.size.width.toDouble(),
      height: bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: bannerAd!),
    );
  }

  Widget _resultsHeader() {
    return Row(
      key: resultsKey,
      children: [
        const Expanded(
          child: Text(
            'Image Source Results',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: _openSaved,
          icon: const Icon(Icons.bookmark_rounded, size: 17),
          label: Text('${savedBases.length} Saved'),
        ),
      ],
    );
  }

  Widget _resultCard(BaseResult item, int index) {
    final exact = item.matchType.toLowerCase() == 'exact';
    final saved = savedBases.any((e) => e.link == item.link);
    final preview = item.previewImage;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xD90F172A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: exact
              ? const Color(0x5534D399)
              : const Color(0x5538BDF8),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (preview.isNotEmpty)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                preview,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: const Color(0xFF111827),
                  child: const Center(
                    child: Icon(Icons.broken_image_rounded),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: exact
                            ? const Color(0x1F22C55E)
                            : const Color(0x1F3B82F6),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        exact ? 'EXACT' : 'SIMILAR',
                        style: TextStyle(
                          color: exact
                              ? const Color(0xFF86EFAC)
                              : const Color(0xFF93C5FD),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        item.domain,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF93C5FD),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _save(item),
                      icon: Icon(
                        saved
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        size: 21,
                      ),
                      color: saved
                          ? const Color(0xFFFACC15)
                          : const Color(0xFFCBD5E1),
                    ),
                  ],
                ),
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _openSource(item, index + 1),
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: const Text('Open Source'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF38BDF8),
                          foregroundColor: const Color(0xFF082F49),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _confirmCorrect(item, index + 1),
                        icon: const Icon(Icons.check_circle_rounded, size: 16),
                        label: const Text('Correct'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF86EFAC),
                          side: const BorderSide(color: Color(0x4422C55E)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openSaved() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      isScrollControlled: true,
      builder: (_) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * .68,
            child: savedBases.isEmpty
                ? const Center(
                    child: Text('No saved sources yet.'),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(14),
                    itemCount: savedBases.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: Color(0x2238BDF8)),
                    itemBuilder: (_, i) {
                      final item = savedBases[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: item.previewImage.isEmpty
                            ? const CircleAvatar(
                                child: Icon(Icons.image_rounded),
                              )
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  item.previewImage,
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                ),
                              ),
                        title: Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(item.domain),
                        onTap: () {
                          Navigator.pop(context);
                          _openSource(item, i + 1);
                        },
                        trailing: IconButton(
                          onPressed: () {
                            _removeSaved(item);
                            Navigator.pop(context);
                            _openSaved();
                          },
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      );
                    },
                  ),
          ),
        );
      },
    );
  }

  void _openMore() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      builder: (_) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('About COCBASE AI'),
                subtitle: const Text(
                  'Free Clash of Clans image-source search.',
                ),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.email_outlined),
                title: const Text('Contact'),
                onTap: () async {
                  Navigator.pop(context);
                  await launchUrl(
                    Uri.parse('mailto:contact@cocbasepro.com'),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _analysisOverlay() {
    if (!analysisVisible) return const SizedBox.shrink();

    return Positioned.fill(
      child: Container(
        color: const Color(0xCC020617),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(22),
        child: Container(
          width: 390,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0x3338BDF8)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x99000000),
                blurRadius: 40,
              ),
            ],
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Color(0xFF38BDF8),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI SOURCE SEARCH',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Analyzing your base',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'LIVE',
                    style: TextStyle(
                      color: Color(0xFF86EFAC),
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 15),
              LinearProgressIndicator(
                minHeight: 6,
                backgroundColor: Color(0xFF1E293B),
                color: Color(0xFFFACC15),
              ),
              SizedBox(height: 12),
              Text(
                'Image fingerprint  ·  Source matching  ·  Result ranking',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFCBD5E1),
                  fontSize: 10.5,
                ),
              ),
              SizedBox(height: 7),
              Text(
                'Local Cache + Source DB are checked before web discovery.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/bg_ai_finder.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Container(color: const Color(0xFF020617)),
            ),
          ),
          Positioned.fill(
            child: Container(color: Colors.black.withOpacity(.72)),
          ),
          SafeArea(
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(),
                  const SizedBox(height: 10),
                  _freeStatusCard(),
                  const SizedBox(height: 8),
                  _rewardCard(),
                  const SizedBox(height: 12),
                  _imagePickerCard(),
                  if (!adFreeActive && bannerReady) ...[
                    const SizedBox(height: 8),
                    Center(child: _banner()),
                  ],
                  const SizedBox(height: 10),
                  _imageActions(),
                  const SizedBox(height: 10),
                  _searchButton(),
                  const SizedBox(height: 7),
                  const Center(
                    child: Text(
                      'Free search · No credits · Image only',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 9.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const SizedBox(height: 18),
                  _resultsHeader(),
                  const SizedBox(height: 9),
                  if (!loading && results.isEmpty)
                    _glassCard(
                      child: const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 18),
                          child: Text(
                            'Upload a base screenshot to find its source.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFF94A3B8)),
                          ),
                        ),
                      ),
                    ),
                  ...List.generate(
                    results.length,
                    (i) => _resultCard(results[i], i),
                  ),
                ],
              ),
            ),
          ),
          _analysisOverlay(),
        ],
      ),
      bottomNavigationBar: BottomNav(
        onHome: () => scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        ),
        onSaved: _openSaved,
        onPremium: _watchRewardedForAdFree,
        onMore: _openMore,
      ),
    );
  }
}
