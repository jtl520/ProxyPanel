param([string]$MihomoPath=(Join-Path $env:ProgramFiles 'Clash Verge\verge-mihomo.exe'))
$ErrorActionPreference='Stop'
if(!(Test-Path -LiteralPath $MihomoPath)){throw 'Specify -MihomoPath to an installed Mihomo executable.'}
. (Join-Path $PSScriptRoot 'ProxyPanel.ps1') -LibraryOnly
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('ProxyPanel-core-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($fixture)|Out-Null
$settings=New-PanelSettings;$settings.configRoot=$fixture
$settings.apps=@(@{name='Path app';path='C:\Sample Apps\Editor\editor.exe';match='path';route='direct'},@{name='Folder app';path='C:\Sample Apps\Cloud\cloud.exe';match='folder';route='global'},@{name='Named app';processName='browser.exe';match='name';route='direct'}|ForEach-Object {Normalize-App $_})
$pipe='\\.\pipe\proxypanel-test-'+[guid]::NewGuid().ToString('N')
$yaml="mode: rule`nfind-process-mode: always`nmixed-port: 0`nport: 0`nsocks-port: 0`nexternal-controller-pipe: "+(ConvertTo-Json -InputObject $pipe -Compress)+"`ntun:`n  enable: false`nrules:`n"+((@(Get-AppRules $settings)+@('MATCH,DIRECT')|ForEach-Object {'  - '+(ConvertTo-Json -InputObject $_ -Compress)}) -join "`n")
$config=Join-Path $fixture 'clash-verge.yaml';[IO.File]::WriteAllText($config,$yaml)
& $MihomoPath -t -d $fixture -f $config
if($LASTEXITCODE -ne 0){throw 'Generated rule syntax was rejected by Mihomo'}
$process=$null
try{
 $process=Start-Process -FilePath $MihomoPath -ArgumentList ('-d "'+$fixture+'" -f "'+$config+'"') -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $fixture 'stdout.log') -RedirectStandardError (Join-Path $fixture 'stderr.log')
 $deadline=(Get-Date).AddSeconds(15)
 do{$snapshot=Get-ApplicationSnapshot $settings;if($snapshot.connected -and $snapshot.rulesLoaded){break};Start-Sleep -Milliseconds 200}while((Get-Date) -lt $deadline -and !$process.HasExited)
 if(!$snapshot.connected -or !$snapshot.rulesLoaded -or $snapshot.tun -ne 'False'){throw ('Isolated live validation failed: '+$snapshot.warning)}
 if(@($snapshot.apps|Where-Object status -eq '设置已生效').Count -ne 1){
  # Missing fixture executable paths correctly remain marked invalid; process-name rule is loaded.
  throw 'App rule status mismatch'
 }
 Write-Output 'PASS: isolated Mihomo syntax, named-pipe API, rule-prefix verification, TUN disabled, no proxy listeners.'
}finally{if($process -and !$process.HasExited){Stop-Process -Id $process.Id;[void]$process.WaitForExit(5000)}}
