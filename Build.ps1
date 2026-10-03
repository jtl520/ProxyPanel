param([string]$Version='1.1.0')
$ErrorActionPreference='Stop'
if($Version -notmatch '^\d+\.\d+\.\d+$'){throw 'Invalid version'}
$app=$PSScriptRoot
& (Join-Path $app 'Build-Icon.ps1')
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$automation=[System.Management.Automation.PSObject].Assembly.Location
if(!(Test-Path $compiler) -or !(Test-Path $automation)){throw 'Build with Windows PowerShell 5.1 on 64-bit Windows.'}
& $compiler /nologo /target:winexe /platform:anycpu ('/out:'+(Join-Path $app 'ProxyPanel.exe')) ('/win32icon:'+(Join-Path $app 'ProxyPanel.ico')) ('/reference:'+$automation) /reference:System.Windows.Forms.dll (Join-Path $app 'Launcher.cs')
if($LASTEXITCODE -ne 0){throw 'Launcher compilation failed'}
$dist=Join-Path $PSScriptRoot 'dist'
New-Item -ItemType Directory -Path $dist -Force|Out-Null
$zip=Join-Path $dist "ProxyPanel-v$Version-windows-portable.zip"
# Explicit allowlist: never package machine backups, logs or subscription files.
$names=@('ProxyPanel.exe','ProxyPanel.ico','ProxyPanel.ps1','Dashboard.ps1','Core.ps1','Monitor.ps1','Launch.vbs','Install.ps1','Install.vbs')
$paths=@($names|ForEach-Object {Join-Path $app $_})+@('README.md','CHANGELOG.md','VALIDATION.md'|ForEach-Object {Join-Path $PSScriptRoot $_})
Compress-Archive -LiteralPath $paths -DestinationPath $zip -Force
$hash=Get-FileHash -LiteralPath $zip -Algorithm SHA256
($hash.Hash.ToLower()+'  '+[IO.Path]::GetFileName($zip))|Set-Content (Join-Path $dist 'SHA256SUMS.txt') -Encoding ASCII
Write-Output $zip
