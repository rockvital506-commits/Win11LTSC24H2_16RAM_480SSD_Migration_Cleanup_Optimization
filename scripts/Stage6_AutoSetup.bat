@echo off
rem ===========================================================================
rem Stage6_AutoSetup.bat - Stage 6 immunity contour runtime initializer (PAT-NEW-3)
rem Deployed to: D:\GD_Tool\AutoSetup.bat
rem Declarations: tweaks/acl/AclManifest.json, tweaks/tasks/TaskManifest.json
rem Runtime core: D:\GD_Tool\ImmunityCore.ps1
rem Rules: AR-105 (ASCII only), AR-201 (no file deletion), AR-204 (non-destructive),
rem        AR-501 (declarative tweaks), AR-709 (never raises the network)
rem ===========================================================================
setlocal EnableExtensions
set "GD_TOOL=D:\GD_Tool"
set "CORE=%GD_TOOL%\ImmunityCore.ps1"
set "LOG_DIR=%GD_TOOL%\logs"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>&1
set "LOG=%LOG_DIR%\AutoSetup.log"

rem Elevated check: NET SESSION fails without administrator rights.
net session >nul 2>&1
if errorlevel 1 (
    echo [%DATE% %TIME%] [FAIL] elevation required >>"%LOG%"
    endlocal
    exit /b 20
)

echo [%DATE% %TIME%] [INFO] AutoSetup start >>"%LOG%"

if not exist "%CORE%" (
    echo [%DATE% %TIME%] [FAIL] runtime core not found: %CORE% >>"%LOG%"
    endlocal
    exit /b 20
)

powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%CORE%" >>"%LOG%" 2>&1
set "CORE_EXIT=%ERRORLEVEL%"
echo [%DATE% %TIME%] [INFO] ImmunityCore exit=%CORE_EXIT% >>"%LOG%"

endlocal & exit /b %CORE_EXIT%
