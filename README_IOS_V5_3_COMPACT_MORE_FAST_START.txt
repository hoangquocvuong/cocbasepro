Base Layout Pro iOS V5.3

More menu:
- Exact 3 x 3 grid (9 items)
- Town Hall / Builder Hall / Capital Hall
- Events / Rankings / Hero Skins
- Support / Reload / About
- Removed broken All Bases -> /p/coc-bases.html (404)
- About uses valid website route /p/about.html
- No Donate/payment menu

Startup optimization:
- WebView starts immediately.
- Connectivity listener begins after first Flutter frame.
- Premium map no longer performs a fresh network request during startup.
- Startup reads cached premium map only.
- Fresh premium map is requested only when a premium mapping is actually needed.
- Support reward state restores asynchronously after first frame.
- AdMob initialization waits ~1.4 seconds after first frame.
- Removed leftover firebase.json and lib/firebase_options.dart.

Ads:
- Rewarded Support -> 15 minutes without interstitial.
- Interstitial logic unchanged.
- No subscription / IAP / Firebase.

Version: 5.3.0+17
