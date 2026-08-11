Base Layout Pro iOS V5.4

Single native menu:
- iOS native bottom menu is the only app navigation.
- Web mobile nav / bottom nav are force-hidden inside iOS WebView.

Fast Light/Dark:
- Removed the old onPageFinished theme query round-trip.
- A MutationObserver watches website theme changes and sends them directly to Flutter.
- Native menu theme updates immediately without page reload.
- Theme is cached locally.

Startup V3:
- WebView starts immediately.
- Connectivity remains after first Flutter frame.
- WebView progress updates are throttled to reduce rebuilds.
- onPageFinished no longer waits for hide-menu + theme-query + news-query sequentially.
- News badge refresh is delayed until after first paint settles.
- Premium map does not fresh-fetch at startup.
- AdMob initializes about 2.2 seconds after first frame.
- Firebase remains removed.

Ads and 3x3 More menu logic are unchanged.

Version: 5.4.0+18
