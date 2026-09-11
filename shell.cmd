@echo off
rem Double-click to open the OMNeT++ (MSYS2 mingw64) terminal in this folder.
rem Every .sh script in the project must be run from this terminal - not from
rem PowerShell, cmd or Git Bash, which lack the OMNeT++ toolchain.
cd /d "%~dp0"
call "D:\omnetpp-6.0.2\tools\win32.x86_64\msys2_shell.cmd" -mingw64 -here
