' Stage6_Launcher.vbs - hidden launcher for the immunity contour (PAT-NEW-3)
' Deployed to: D:\GD_Tool\Launcher.vbs
' Action of the scheduled task System_Immunity_Core: wscript.exe D:\GD_Tool\Launcher.vbs
' Rules: AR-105 (ASCII only), AR-201 (no file deletion), AR-204 (non-destructive)
Option Explicit

Dim shell, fso, bat
bat = "D:\GD_Tool\AutoSetup.bat"

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

If Not fso.FileExists(bat) Then
    WScript.Quit 20
End If

' 0 = hidden window, False = do not wait for completion
shell.Run "cmd.exe /c """ & bat & """", 0, False
WScript.Quit 0
