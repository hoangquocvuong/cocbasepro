Base Layout Pro iOS V5.6

Fix Buy Me a Coffee routing from News:

1. Premium product links:
   https://buymeacoffee.com/cocbase/e/<id>
   -> never open the BMC product page
   -> resolve via premium-map.json
   -> open the original Clash of Clans link directly

2. News/editorial links:
   https://buymeacoffee.com/cocbase/<article-slug>
   -> open in the external browser
   -> no incorrect Donate/Support warning

3. Root/profile/support BMC links remain blocked from the iOS WebView.

Example now supported:
https://buymeacoffee.com/cocbase/chief-chronicles-are-here

Version: 5.6.0+20
