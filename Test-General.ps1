$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Core.ps1')
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('ProxyPanel-general-'+[guid]::NewGuid().ToString('N'))
$root=Join-Path $testRoot 'clash';$data=Join-Path $testRoot 'data'
[IO.Directory]::CreateDirectory((Join-Path $root 'profiles'))|Out-Null
$utf8=New-Object Text.UTF8Encoding($false)
$original="// Keep the user's custom logic.`nfunction main(config, profileName) { config.userSetting = profileName; config.rules = ['DOMAIN,example.test,DIRECT'].concat(config.rules || []); return config; }"
[IO.File]::WriteAllText((Join-Path $root 'profiles\Script.js'),$original,$utf8)
[IO.File]::WriteAllText((Join-Path $root 'config.yaml'),"mode: global`nmixed-port: 7897`n",$utf8)
function Assert($condition,$message){if(!$condition){throw $message}}
function Throws($action,$message){$failed=$false;try{& $action|Out-Null}catch{$failed=$true};Assert $failed $message}
$s=New-PanelSettings;$s.configRoot=$root
$a=Normalize-App @{name='Browser';path='C:\Apps\Browser\browser.exe';match='path';route='direct'}
$b=Normalize-App @{name='Cloud';path='D:\Cloud Drive\cloud.exe';match='folder';route='global'}
$c=Normalize-App @{name='Editor';processName='editor.exe';match='name';route='follow'}
$s.apps=@($a,$b,$c);$s=Save-Settings $s $data
Assert ((Read-Settings $data).apps.Count -eq 3) 'Settings roundtrip'
$rules=@(Get-AppRules $s)
Assert ($rules.Count -eq 2) 'Follow should not generate override'
Assert ($rules[0] -eq 'PROCESS-PATH,C:\Apps\Browser\browser.exe,DIRECT') 'Path rule'
Assert ('D:\Cloud Drive\bin\helper.exe' -match (($rules[1] -split ',')[1])) 'Folder helper matching'
Assert (!(Test-AppOwner $b @{name='cloud';path='D:\Cloud Drive Evil\cloud.exe'})) 'Folder prefix boundary'
Throws {Normalize-App @{name='Bad';path='C:\a,b\bad.exe';match='path';route='direct'}} 'Rule injection not rejected'
Throws {Normalize-App @{name='Bad';path='C:\app.exe';match='folder';route='direct'}} 'Drive root not rejected'
$overlap=$s|ConvertTo-Json -Depth 10|ConvertFrom-Json;$overlap.apps+=Normalize-App @{name='Conflicting';path='D:\Cloud Drive\helper.exe';match='path';route='direct'}
Throws {Normalize-Settings $overlap} 'Conflicting scopes not rejected'
Throws {Get-AppRules $s -CheckPaths} 'Missing paths not rejected'
$export=Join-Path $testRoot 'apps.json';Export-AppList $s $export
Assert (![IO.File]::ReadAllText($export).Contains($root)) 'Export leaked local config directory'
$imported=Import-AppList (New-PanelSettings) $export;Assert ($imported.apps.Count -eq 3) 'Portable import'
Update-ManagedRules $s $data -TestMode|Out-Null
$first=[IO.File]::ReadAllText((Join-Path $root 'profiles\Script.js'));Assert ($first.StartsWith($original)) 'Original script was overwritten'
$state=Read-ManagedState $data;Assert ($state.originalMode -eq 'global' -and $state.rules.Count -eq 2) 'Managed state missing'
$fixturePath=Join-Path $testRoot 'fixture.js';[IO.File]::WriteAllText($fixturePath,$first,$utf8)
$jsTest=Join-Path $testRoot 'check.cjs'
[IO.File]::WriteAllText($jsTest,"const fs=require('fs'),vm=require('vm'),assert=require('assert');const c={};vm.createContext(c);vm.runInContext(fs.readFileSync(process.argv[2],'utf8'),c,{timeout:1000});const x=c.main({rules:['MATCH,Existing'],tun:{enable:false}},'my-profile');assert.equal(x.userSetting,'my-profile');assert.equal(x.rules[0],'PROCESS-PATH,C:\\Apps\\Browser\\browser.exe,DIRECT');assert.equal(x.rules[2],'DOMAIN,example.test,DIRECT');assert.equal(x.rules[3],'MATCH,Existing');assert.equal(x.tun.enable,false);assert.equal(x.mode,'rule');console.log('PASS: generated JavaScript retains existing rules, profile and TUN');",$utf8)
if(Get-Command node -ErrorAction SilentlyContinue){& node $jsTest $fixturePath;if($LASTEXITCODE -ne 0){throw 'Generated JavaScript failed'}}else{Write-Output 'SKIP: Node.js fixture execution (not required by the app)'}
$s.apps[0].route='global';Update-ManagedRules $s $data -TestMode|Out-Null
$second=[IO.File]::ReadAllText((Join-Path $root 'profiles\Script.js'));Assert (([regex]::Matches($second,'PROXYPANEL MANAGED BEGIN')).Count -eq 1) 'Repeated apply duplicated wrappers'
[IO.File]::WriteAllText((Join-Path $root 'profiles\Script.js'),"// new user comment`n"+$second,$utf8)
Add-Content -LiteralPath (Join-Path $root 'config.yaml') -Value 'log-level: warning'
Update-ManagedRules $s $data -Remove -TestMode|Out-Null
Assert ([IO.File]::ReadAllText((Join-Path $root 'profiles\Script.js')) -ceq ("// new user comment`n"+$original)) 'Undo lost user edits'
$config=[IO.File]::ReadAllText((Join-Path $root 'config.yaml'));Assert ($config -match 'mode: global' -and $config -match 'log-level: warning') 'Undo clobbered config'
Assert ($null -eq (Read-ManagedState $data)) 'Undo left active state'
Update-ManagedRules $s $data -TestMode|Out-Null
[IO.File]::AppendAllText((Join-Path $root 'profiles\Script.js'),"`n// external change inside managed tail",$utf8)
$before=[IO.File]::ReadAllText((Join-Path $root 'profiles\Script.js'))
Throws {Update-ManagedRules $s $data -Remove -TestMode} 'Conflicting managed edits must block undo'
Assert ([IO.File]::ReadAllText((Join-Path $root 'profiles\Script.js')) -ceq $before) 'Failed undo changed source'
Write-Output 'PASS: settings, validation, import/export, idempotent rules, protected backup, selective undo and conflict protection.'

# Quoted YAML modes must survive apply/undo; unsupported values must fail before mutation.
foreach($modeText in @('mode: "global" # kept',"mode: 'direct'",'mode: rule')){
 Assert ((Get-ModeValue $modeText) -in @('global','direct','rule')) 'Quoted mode parsing'
}
Throws {Get-ModeValue 'mode: unknown'} 'Unsupported mode accepted'
$emptyRoot=Join-Path $testRoot 'all-follow';$emptyData=Join-Path $testRoot 'empty-data'
[IO.Directory]::CreateDirectory((Join-Path $emptyRoot 'profiles'))|Out-Null
Write-AtomicText (Join-Path $emptyRoot 'profiles\Script.js') $original
Write-AtomicText (Join-Path $emptyRoot 'config.yaml') "mode: 'global' # original`nmixed-port: 7897`n"
$s.configRoot=$emptyRoot;Update-ManagedRules $s $emptyData -TestMode|Out-Null
Assert ((Read-ManagedState $emptyData).originalMode -eq 'global') 'Quoted original mode not normalized'
$legacyState=Read-ManagedState $emptyData;$legacyState.originalMode='"global"'
Save-ProtectedState $legacyState (Join-Path $emptyData 'managed.dpapi')
foreach($app in $s.apps){$app.route='follow'}
Update-ManagedRules $s $emptyData -TestMode|Out-Null
Assert ($null -eq (Read-ManagedState $emptyData)) 'All-follow apply retained overrides'
Assert ([IO.File]::ReadAllText((Join-Path $emptyRoot 'profiles\Script.js')) -ceq $original) 'All-follow failed to restore original script'
Assert ((Get-ModeValue ([IO.File]::ReadAllText((Join-Path $emptyRoot 'config.yaml')))) -eq 'global') 'Original mode not restored'
$saved=[IO.File]::ReadAllText((Join-Path $emptyRoot 'config.yaml'))
Update-ManagedRules $s $emptyData -TestMode|Out-Null
Assert ([IO.File]::ReadAllText((Join-Path $emptyRoot 'config.yaml')) -ceq $saved) 'Repeated empty apply modified config'
$s.apps=@();Update-ManagedRules $s $emptyData -TestMode|Out-Null
Write-AtomicText (Join-Path $emptyRoot 'profiles\Script.js') ($original+"`n// PROXYPANEL MANAGED BEGIN v2")
Throws {Update-ManagedRules $s $emptyData -TestMode} 'Orphaned managed rules must not be reported as a successful no-op'
'PASS: quoted mode restoration, all-follow application, repeated no-op and empty list.'
