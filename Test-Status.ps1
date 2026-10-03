$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Monitor.ps1')
function Expect($expected,$app,$snapshot,$missing=$false){$actual=Get-SettingStatus $app $snapshot $missing;if($actual.text -ne $expected -or !$actual.hint){throw ('Status mismatch: '+$actual.text+' / '+$expected)}}
$app=@{enabled=$true;route='direct'}
$snapshot=@{connected=$true;mode='rule';rulesLoaded=$false;managed=$false;pending=$false}
Expect '尚未应用' $app $snapshot
$snapshot.managed=$true;Expect '等待 Clash 加载' $app $snapshot
$snapshot.rulesLoaded=$true;Expect '设置已生效' $app $snapshot
$snapshot.pending=$true;Expect '更改尚未应用' $app $snapshot
$app.enabled=$false;Expect '更改尚未应用' $app $snapshot
$snapshot.pending=$false;Expect '不添加分流规则' $app $snapshot
$app.enabled=$true;$app.route='follow';Expect '使用 Clash 原有规则' $app $snapshot
$snapshot.pending=$true;Expect '更改尚未应用' $app $snapshot
$snapshot.pending=$false;$app.route='global';$snapshot.mode='global';Expect '请切换到规则模式' $app $snapshot
$snapshot.connected=$false;Expect '等待连接 Clash' $app $snapshot
Expect '请重新选择程序' $app $snapshot $true
'PASS: 11 configuration status states, including pending disable/follow and actionable explanations.'
. (Join-Path $PSScriptRoot 'Core.ps1')
$settings=New-PanelSettings;$settings.apps=@(Normalize-App @{name='Test';processName='example.exe';match='name';route='global'})
$state=@{rules=@(Get-AppRules $settings)}
$settings.apps[0].name='Renamed only'
if(Test-RulesPending $settings $state){throw 'Rename must not mark routing pending'}
$settings.apps[0].route='direct'
if(!(Test-RulesPending $settings $state)){throw 'Route change must mark pending'}
$settings.apps[0].route='global';$settings.apps[0].enabled=$false
if(!(Test-RulesPending $settings $state)){throw 'Disable must mark pending'}
$proxyData='{"proxies":{"GLOBAL":{"now":"Nested"},"Nested":{"type":"Selector","now":"DIRECT"},"DIRECT":{"type":"Direct"},"Node":{"type":"Shadowsocks"}}}'|ConvertFrom-Json
if(!(Get-GlobalRouteInfo $proxyData).isDirect){throw 'Nested DIRECT was not detected'}
$proxyData.proxies.Nested.now='Node'
if((Get-GlobalRouteInfo $proxyData).isDirect){throw 'Proxy node incorrectly labeled DIRECT'}
$proxyData.proxies.Nested.now='Nested'
if((Get-GlobalRouteInfo $proxyData).isDirect){throw 'Cyclic selection incorrectly labeled DIRECT'}
$snapshot=@{connected=$true;mode='rule';rulesLoaded=$true;managed=$true;pending=$false;globalIsDirect=$true}
$app=@{enabled=$true;route='global'}
Expect '代理组当前为直连' $app $snapshot
'PASS: rule-only change detection, nested proxy destination and DIRECT warning.'
