param([Parameter(Mandatory=$true)][string]$ManifestPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Core.ps1')
$manifest=Get-Content -LiteralPath $ManifestPath -Raw|ConvertFrom-Json
$fixture=Join-Path $manifest.root 'lifecycle'
$clash=Join-Path $fixture 'clash';$data=Join-Path $fixture 'data'
if(![IO.Path]::GetFullPath($fixture).StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){throw 'Expected TEMP fixture'}
[IO.Directory]::CreateDirectory((Join-Path $clash 'profiles'))|Out-Null
$original="function main(config, profileName) { config.profileName = profileName; return config; }"
$scriptPath=Join-Path $clash 'profiles\Script.js'
Write-AtomicText $scriptPath $original
Write-AtomicText (Join-Path $clash 'config.yaml') "mode: rule`nmixed-port: 7897`n"
$js=@'
const fs=require('fs'),vm=require('vm'),assert=require('assert');
const scope={};vm.createContext(scope);
vm.runInContext(fs.readFileSync(process.argv[2],'utf8'),scope,{timeout:1000});
const expected=JSON.parse(fs.readFileSync(process.argv[3],'utf8'));
const result=scope.main({rules:['MATCH,GLOBAL'],tun:{enable:true}},'kept-profile');
assert.deepStrictEqual(Array.from(result.rules),expected.concat(['MATCH,GLOBAL']));
assert.equal(result.tun.enable,true);assert.equal(result.profileName,'kept-profile');
'@
$jsPath=Join-Path $fixture 'verify.cjs';Write-AtomicText $jsPath $js
$cases=Get-Content (Join-Path $manifest.root 'cases.json') -Raw|ConvertFrom-Json
$results=@()
foreach($case in $cases){
 $settings=Get-Content -LiteralPath $case.settings -Raw|ConvertFrom-Json
 $settings.configRoot=$clash
 $rules=@(Get-AppRules $settings -CheckPaths)
 $before=Read-ManagedState $data
 if($rules.Count){Update-ManagedRules $settings $data -TestMode|Out-Null}
 elseif($before){Update-ManagedRules $settings $data -Remove -TestMode|Out-Null}
 $after=Read-ManagedState $data
 if($rules.Count -and !$after){throw 'Apply failed to write managed state'}
 if(!$rules.Count -and $after){throw 'Undo failed to remove managed state'}
 $expectedPath=Join-Path $fixture 'expected.json';Write-AtomicText $expectedPath (ConvertTo-Json -InputObject $rules -Compress)
 & node $jsPath $scriptPath $expectedPath
 if($LASTEXITCODE -ne 0){throw ('Generated lifecycle script failed: '+$case.name)}
 $results+=@{name=$case.name;rules=$rules.Count;passed=$true}
}
if([IO.File]::ReadAllText($scriptPath) -cne $original){throw 'Final removal did not restore original script'}
Write-AtomicText (Join-Path $manifest.root 'lifecycle-results.json') (ConvertTo-Json -InputObject $results -Depth 5)
Write-Output ('PASS: '+$results.Count+' persisted option scenarios, generated JavaScript execution, all-follow/disabled undo, and final removal restoration.')
