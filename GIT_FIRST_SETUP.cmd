@echo off
setlocal
cd /d "%~dp0"

set "SAFE=%CD:\=/%"
git config --global --add safe.directory "%SAFE%"

echo.
echo === CocBasePro iOS V5.4 Git Setup ===
echo Repo: %CD%
echo Remote:
git remote -v

echo.
echo Fetching current GitHub main...
git fetch origin
if errorlevel 1 (
  echo.
  echo ERROR: Could not fetch GitHub. Check your internet/login and run this file again.
  pause
  exit /b 1
)

echo.
echo Attaching V5.4 source to origin/main without force-push...
git reset --mixed origin/main
git branch -M main

echo.
echo === READY ===
git status
echo.
echo Next commands:
echo   git add .
echo   git commit -m "iOS V5.4 single menu fast theme startup"
echo   git push -u origin main
echo.
pause
