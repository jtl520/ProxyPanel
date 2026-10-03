param([switch]$Layout)
$ErrorActionPreference='Stop'
$env:PROXYPANEL_DATA_DIR=Join-Path ([IO.Path]::GetTempPath()) ('ProxyPanel-ui-'+[guid]::NewGuid().ToString('N'))
. (Join-Path $PSScriptRoot 'ProxyPanel.ps1') -LibraryOnly
$s=New-PanelSettings
$examples=@(@{name='Google Chrome';processName='chrome.exe';match='name';route='direct'},@{name='Visual Studio Code';processName='Code.exe';match='name';route='global'},@{name='Cloud Drive';processName='cloud.exe';match='name';route='direct'},@{name='My application';processName='example.exe';match='name';route='follow'})
$s.apps=@($examples|ForEach-Object {Normalize-App $_});Save-Settings $s|Out-Null
if($Layout){& (Join-Path $PSScriptRoot 'Dashboard.ps1') -LayoutTest}else{& (Join-Path $PSScriptRoot 'Dashboard.ps1') -InteractionTest}
