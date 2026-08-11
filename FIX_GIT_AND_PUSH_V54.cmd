@echo off
setlocal
cd /d "%~dp0"

echo.
echo === CocBasePro iOS V5.4 - Git Repair and Push ===
echo Folder: %CD%
echo.

set "SAFE=%CD:\=/%"
git config --global --add safe.directory "%SAFE%"

if not exist ".git" (
  echo [1/7] Initializing Git...
  git init
  if errorlevel 1 goto :fail
) else (
  echo [1/7] Git repository already exists.
)

git branch -M main

echo [2/7] Configuring origin...
git remote get-url origin >nul 2>&1
if errorlevel 1 (
  git remote add origin https://github.com/hoangquocvuong/cocbasepro.git
) else (
  git remote set-url origin https://github.com/hoangquocvuong/cocbasepro.git
)

echo [3/7] Fetching origin/main...
git fetch origin
if errorlevel 1 goto :fail

echo [4/7] Attaching current V5.4 files to GitHub history...
git reset --mixed origin/main
if errorlevel 1 goto :fail

git branch -M main

echo [5/7] Staging V5.4...
git add .
if errorlevel 1 goto :fail

echo [6/7] Creating commit...
git diff --cached --quiet
if not errorlevel 1 (
  echo Nothing changed. Source may already match origin/main.
) else (
  git commit -m "iOS V5.4 single menu fast theme startup"
  if errorlevel 1 goto :fail
)

echo [7/7] Pushing main...
git push -u origin main
if errorlevel 1 goto :fail

echo.
echo ==========================================
echo SUCCESS
echo ==========================================
git status
git log --oneline -5
echo.
pause
exit /b 0

:fail
echo.
echo ==========================================
echo FAILED - copy the output above and send it
echo ==========================================
pause
exit /b 1
