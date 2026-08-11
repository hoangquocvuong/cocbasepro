Base Layout Pro iOS V5.5

Fixes:
1. Native menu background now follows the website's actual Light/Dark mode.
   Detection supports data-mode, data-theme, HTML/body classes, common
   localStorage theme keys, computed body background, then system fallback.
   Website is the source of truth.

2. News badge is stable.
   A missing/not-yet-rendered web badge returns -1 and can no longer erase
   the native unread count. Positive unread count is cached locally.
   Zero is accepted after an explicit News/open/read refresh.

3. Yellow top loading bar no longer stalls near the end.
   WKWebView progress >=88% gets a short 700ms completion fallback.
   onPageFinished and progress=100 still complete immediately.

Version: 5.5.0+19
