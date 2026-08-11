BASE LAYOUT PRO iOS V5.4 — GIT READY FULL

This package contains a real .git directory.

Configured:
- branch: main
- origin: https://github.com/hoangquocvuong/cocbasepro.git
- V5.4 full source included
- no Firebase runtime/dependencies
- native-only iOS menu
- fast Light/Dark sync
- faster cold-start logic
- Rewarded Support + 15-minute interstitial-free reward

IMPORTANT:
The build environment used to generate this ZIP has no internet access, so the
GitHub commit objects cannot be embedded here. On Windows, run once:

    GIT_FIRST_SETUP.cmd

That script:
1. Marks the extracted folder as Git safe.directory.
2. Fetches origin/main.
3. Attaches the included V5.4 files to the real GitHub history.
4. Leaves the V5.4 changes ready for git add/commit/push.

After that, normal workflow is:
    git add .
    git commit -m "update ios"
    git push

Do NOT run git init again.
Do NOT use force push.
