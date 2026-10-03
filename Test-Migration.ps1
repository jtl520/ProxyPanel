$ErrorActionPreference='Stop'
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('ProxyPanel-test-'+[guid]::NewGuid().ToString('N'))
$configRoot=Join-Path $testRoot 'config'
New-Item -ItemType Directory -Path (Join-Path $configRoot 'profiles'),(Join-Path $testRoot 'backup')|Out-Null
$utf8=New-Object Text.UTF8Encoding($false)
$fixture=@{'profiles\Script.js'="// example`nfunction main(config, profileName) { return config; }";'config.yaml'="mode: global`n";'verge.yaml'="enable_tun_mode: false`n"}
foreach($name in $fixture.Keys){[IO.File]::WriteAllText((Join-Path $configRoot $name),$fixture[$name],$utf8)}
$migration=Join-Path $PSScriptRoot 'Migrate.ps1'
$arguments=@{ConfigRoot=$configRoot;BackupDirectory=(Join-Path $testRoot 'backup');TestMode=$true;AppDirectories=@('C:\Example Apps\Baidu','E:\Cloud Apps\Quark')}
function Assert($condition,$message){if(!$condition){throw $message}}
& $migration @arguments
Assert (Test-Path (Join-Path $arguments.BackupDirectory 'migration-backup.dpapi')) 'Encrypted backup missing'
$js=[IO.File]::ReadAllText((Join-Path $configRoot 'profiles\Script.js'))
$json=[regex]::Match($js,'config.rules = (\[.*?\])\.concat').Groups[1].Value
$rules=$json|ConvertFrom-Json
Assert ($rules.Count -eq 6) 'Expected process, path and GLOBAL rules'
Assert ('C:\Example Apps\Baidu\helper.exe' -match (($rules[3] -split ',')[1])) 'Baidu path rule does not match'
Assert ('E:\Cloud Apps\Quark\nested\helper.exe' -match (($rules[4] -split ',')[1])) 'Quark path rule does not match'
Assert ([IO.File]::ReadAllText((Join-Path $configRoot 'config.yaml')) -match 'mode: rule') 'Rule mode missing'
# External changes must prevent destructive rollback.
Add-Content -LiteralPath (Join-Path $configRoot 'config.yaml') -Value '# later edit'
$blocked=$false;try{& $migration @arguments -Restore}catch{$blocked=$true}
Assert $blocked 'Restore must reject externally changed files'
[IO.File]::WriteAllText((Join-Path $configRoot 'config.yaml'),"mode: rule`n",$utf8)
& $migration @arguments -Restore
foreach($name in $fixture.Keys){Assert ([IO.File]::ReadAllText((Join-Path $configRoot $name)) -ceq $fixture[$name]) ('Restore mismatch: '+$name)}
Assert (!(Test-Path (Join-Path $arguments.BackupDirectory 'migration-backup.dpapi'))) 'Active journal should be archived'
# Reapply after restoring is supported.
& $migration @arguments
& $migration @arguments -Restore
[IO.File]::WriteAllText((Join-Path $configRoot 'profiles\Script.js'),'function main(config) { config.rules=[]; return config; }',$utf8)
$blocked=$false;try{& $migration @arguments}catch{$blocked=$true}
Assert $blocked 'Custom scripts must not be overwritten'
Write-Output 'PASS: isolated migration, path rules, conflict protection, exact restore, reapply and custom-script protection.'
