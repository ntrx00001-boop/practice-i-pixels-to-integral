@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo.
echo ===== HASKELL =====
echo.
runghc Haskell\Main.hs curva_binaria_P4.pbm
if errorlevel 1 (
  echo.
  echo Haskell failed. Is GHC installed?
  pause
  exit /b 1
)

echo.
echo ===== PROLOG =====
echo.

where swipl >nul 2>&1
if %errorlevel%==0 (
  swipl -q -t main -s Prolog\area.pl -- curva_binaria_P4.pbm
) else (
  "C:\Program Files\swipl\bin\swipl.exe" -q -t main -s Prolog\area.pl -- curva_binaria_P4.pbm
)

echo.
pause
