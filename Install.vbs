Set sh=CreateObject("WScript.Shell")
Set fs=CreateObject("Scripting.FileSystemObject")
p=fs.GetParentFolderName(WScript.ScriptFullName)
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File """ & p & "\Install.ps1""", 0, False
