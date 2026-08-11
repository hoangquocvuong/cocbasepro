Base Layout Pro iOS V7.1 — Seamless page navigation

Observed in the supplied video:
- between internal page loads, the website disappeared;
- only the native bottom menu remained;
- a full dark/light solid background was shown for several moments;
- then the next web page appeared.

Root cause:
`onPageStarted` set `_webShellReady = false` for EVERY navigation.
The Flutter layer then hid the entire WKWebView and painted a solid theme
background until `onPageFinished` completed `_applyIOSAppWebMode()`.

Fix:
- The solid cover is now cold-start only.
- After the first page is presented, the WKWebView stays visible during all
  later navigations.
- The previous page remains visible while WKWebView works on the next page.
- Later `onPageFinished` does not wait for iOS-mode JavaScript before painting.
- The thin yellow progress indicator can continue showing load progress.
- First launch still keeps the defensive menu-flash protection.
- Existing native menu, News badge, AdMob and external-link logic are unchanged.

Version: 7.1.0+2
