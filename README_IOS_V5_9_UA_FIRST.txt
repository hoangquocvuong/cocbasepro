Base Layout Pro iOS V5.9

Root-cause fix for the web navigation flash.

Cause:
The previous WebView setup used a Dart cascade:
  setUserAgent(...)
  ...
  loadRequest(...)

These WebView controller calls are asynchronous. The first loadRequest could
begin before setUserAgent had actually reached WKWebView. On that first
request the Blogger template saw a normal Safari UA, rendered #mobile-nav,
then later app JS/CSS hid it. This produced the brief second-menu flash.

Fix:
- WebViewController is created synchronously in initState.
- WebView configuration runs asynchronously.
- setUserAgent() is explicitly awaited.
- JavaScript channels and NavigationDelegate are installed.
- Only then is loadRequest(homeUrl) executed.

With the template critical iOS CSS already installed, the server/page now sees
CocBaseProApp-iOS from the first navigation, so the web nav is hidden before
its first paint.

Version: 5.9.0+23
