param([switch]$NoDialog,[string]$Destination=(Join-Path $env:LOCALAPPDATA 'Programs\ProxyPanel'),[switch]$NoShortcuts)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
try{
 $destinationPath=[IO.Path]::GetFullPath($Destination)
 if($destinationPath.TrimEnd('\') -ieq $PSScriptRoot.TrimEnd('\')){throw '已经在安装目录中，无需重复安装。'}
 if(Get-Process ProxyPanel -ErrorAction SilentlyContinue|Where-Object {$_.Path -ieq (Join-Path $destinationPath 'ProxyPanel.exe')}){throw '请先关闭安装目录中的 ProxyPanel。'}
 $files=@('ProxyPanel.exe','ProxyPanel.ico','ProxyPanel.ps1','Dashboard.ps1','Core.ps1','Monitor.ps1','Launch.vbs','README.md')
 foreach($name in $files){if(!(Test-Path -LiteralPath (Join-Path $PSScriptRoot $name))){throw ('缺少安装文件：'+$name)}}
 [IO.Directory]::CreateDirectory($destinationPath)|Out-Null
 foreach($name in $files){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $destinationPath $name) -Force}
 if(!$NoShortcuts){$ws=New-Object -ComObject WScript.Shell;foreach($dir in @([Environment]::GetFolderPath('Desktop'),[Environment]::GetFolderPath('Programs'))){$link=$ws.CreateShortcut((Join-Path $dir 'ProxyPanel.lnk'));$link.TargetPath=Join-Path $destinationPath 'ProxyPanel.exe';$link.WorkingDirectory=$destinationPath;$link.IconLocation=Join-Path $destinationPath 'ProxyPanel.ico';$link.Save()}}
 if(!$NoDialog){[void][Windows.Forms.MessageBox]::Show('安装完成。可从桌面或开始菜单打开 ProxyPanel。应用列表与规则备份单独保留，不随程序升级覆盖。','ProxyPanel')};Write-Output $destinationPath
}catch{if($NoDialog){throw};[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'安装未完成')}
