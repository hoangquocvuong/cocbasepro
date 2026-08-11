@echo off
setlocal
cd /d "%~dp0"

set "SAFE=%CD:\=/%"
git config --global --add safe.directory "%SAFE%"

git add .
git diff --cached --quiet
if not errorlevel 1 (
  echo Nothing to commit.
  git status
  pause
  exit /b 0
)

git commit -m "iOS V5.4 single menu fast theme startup"
if errorlevel 1 (
  echo Commit failed.
  pause
  exit /b 1
)

git push -u origin main
if errorlevel 1 (
  echo Push failed. If this is the first run, execute GIT_FIRST_SETUP.cmd first.
  pause
  exit /b 1
)

echo.
echo Push completed.
pause
