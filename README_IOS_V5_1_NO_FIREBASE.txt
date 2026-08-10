Base Layout Pro iOS V5.1 — Firebase fully removed

Removed:
- firebase_core
- firebase_messaging
- Firebase initialization
- background message handler
- notification permission request
- foreground push listener
- GoogleService-Info.plist if present

Startup:
- runApp() immediately
- WebView starts immediately
- AdMob initializes after first frame
- premium-map refresh remains deferred
- no Firebase work at startup or runtime

Ads:
- no subscriptions
- no rewarded gate
- no startup ad
- interstitial after natural browsing only

Version: 5.1.0+13
