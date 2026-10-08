@echo off
cd /d "%~dp0"
if exist "bondi_app\build\windows\x64\runner\Debug\bondi_app.exe" (
    start "" "bondi_app\build\windows\x64\runner\Debug\bondi_app.exe"
) else (
    cd bondi_app
    flutter run -d windows
)
