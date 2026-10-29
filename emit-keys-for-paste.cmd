@echo off
REM Key paste helper: copies each vault key to clipboard one at a time for
REM pasting into TypingMind after a crash. Values never touch disk.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Users\shawn\tm-bridge\emit-keys-for-paste.ps1"
pause
