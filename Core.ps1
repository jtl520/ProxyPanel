$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Security
$script:Utf8=New-Object Text.UTF8Encoding($false)
$script:ManagedStart="`r`n// PROXYPANEL MANAGED BEGIN v2"
$script:ManagedEnd='// PROXYPANEL MANAGED END v2'
function Get-DataDirectory { if($env:PROXYPANEL_DATA_DIR){return $env:PROXYPANEL_DATA_DIR};return (Join-Path $env:LOCALAPPDATA 'ProxyPanel') }
function Write-AtomicText($path,$text){
 $dir=Split-Path -Parent $path;[IO.Directory]::CreateDirectory($dir)|Out-Null
 $temp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 try{[IO.File]::WriteAllText($temp,$text,[Text.UTF8Encoding]::new($false));if(Test-Path -LiteralPath $path){[IO.File]::Replace($temp,$path,[NullString]::Value)}else{[IO.File]::Move($temp,$path)}}finally{if(Test-Path -LiteralPath $temp){[IO.File]::Delete($temp)}}
}
function Get-TextHash([string]$text){$sha=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)))).Replace('-','')}finally{$sha.Dispose()}}
function Find-ClashRoot {
 $root=Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev'
 if(Test-Path -LiteralPath (Join-Path $root 'profiles\Script.js')){return $root};return ''
}
function New-PanelSettings {return [pscustomobject]@{schema=2;configRoot=(Find-ClashRoot);apps=@()}}
function Normalize-App($app){
 $name=([string]$app.name).Trim();$path=[Environment]::ExpandEnvironmentVariables(([string]$app.path).Trim())
 $processName=([string]$app.processName).Trim()
 if($path){if(![IO.Path]::IsPathRooted($path)){throw '程序路径必须是绝对路径。'};$path=[IO.Path]::GetFullPath($path);$processName=[IO.Path]::GetFileName($path)}
 if(!$name){$name=[IO.Path]::GetFileNameWithoutExtension($processName)}
 if(!$name -or $name.Length -gt 100){throw '请填写有效的应用名称（最多 100 个字符）。'}
 if($processName -notmatch '^[^\\/,:\r\n]+\.exe$'){throw '请选择有效的 .exe 程序。'}
 if($path -match '[,\r\n]'){throw '路径中不能包含逗号或换行。'}
 if($app.match -notin @('path','name','folder')){throw '不支持的匹配方式。'}
 if($app.route -notin @('direct','global','follow')){throw '不支持的分流方式。'}
 if($app.match -ne 'name' -and !$path){throw '按路径或目录匹配时需要选择程序文件。'}
 if($app.match -eq 'folder'){
  $parent=Split-Path -Parent $path
  if($parent.TrimEnd('\') -eq [IO.Path]::GetPathRoot($path).TrimEnd('\') -or $parent.TrimEnd('\') -ieq $env:WINDIR.TrimEnd('\')){throw '不能把整个磁盘或 Windows 目录设为应用目录。'}
 }
 $id=[string]$app.id;if($id -notmatch '^[a-fA-F0-9]{32}$'){$id=[guid]::NewGuid().ToString('N')}
 return [pscustomobject]@{id=$id;name=$name;path=$path;processName=$processName;match=[string]$app.match;route=[string]$app.route;enabled=($app.enabled -ne $false)}
}
function Test-AppOwner($app,$owner){
 if($app.match -eq 'name'){return ($owner.name+'.exe') -ieq $app.processName}
 if(!$owner.path){return $false}
 if($app.match -eq 'folder'){return $owner.path.StartsWith((Split-Path -Parent $app.path).TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)}
 return $owner.path -ieq $app.path
}
function Normalize-Settings($settings){
 if($settings.schema -ne 2){throw '不支持的配置版本。'}
 $apps=@($settings.apps|ForEach-Object {Normalize-App $_})
 if($apps.Count -gt 200){throw '最多支持 200 个应用。'}
 $keys=@{};$ids=@{}
 foreach($a in $apps){
  $key=$a.match+':'+$(if($a.match -eq 'name'){$a.processName}elseif($a.match -eq 'folder'){Split-Path -Parent $a.path}else{$a.path})
  if($keys.ContainsKey($key)){throw ('重复的应用匹配项：'+$a.name)};$keys[$key]=$true
  if($ids.ContainsKey($a.id)){throw '应用标识重复。'};$ids[$a.id]=$true
 }
 foreach($a in $apps){foreach($b in $apps){
  if($a.id -eq $b.id -or !$a.enabled -or !$b.enabled -or $a.route -eq $b.route){continue}
  if(($a.match -eq 'folder' -and $b.path -and (Test-AppOwner $a @{name=[IO.Path]::GetFileNameWithoutExtension($b.processName);path=$b.path})) -or ($a.match -eq 'name' -and $a.processName -ieq $b.processName)){
   throw ('匹配范围重叠且分流方式不同：'+$a.name+' / '+$b.name+'。请缩小匹配范围。')
  }
 }}
 return [pscustomobject]@{schema=2;configRoot=[string]$settings.configRoot;apps=$apps}
}
function Read-Settings([string]$dataDirectory=(Get-DataDirectory)){
 $p=Join-Path $dataDirectory 'settings.json';if(!(Test-Path -LiteralPath $p)){return New-PanelSettings}
 return Normalize-Settings ([IO.File]::ReadAllText($p)|ConvertFrom-Json)
}
function Save-Settings($settings,[string]$dataDirectory=(Get-DataDirectory)){
 $valid=Normalize-Settings $settings
 Write-AtomicText (Join-Path $dataDirectory 'settings.json') ($valid|ConvertTo-Json -Depth 10)
 return $valid
}
function Export-AppList($settings,$path){
 # Export only application choices. No controller, subscription, secret or encrypted backup.
 Write-AtomicText $path (@{schema=2;apps=@($settings.apps)}|ConvertTo-Json -Depth 10)
}
function Import-AppList($settings,$path){
 $imported=Normalize-Settings ([IO.File]::ReadAllText($path)|ConvertFrom-Json)
 $imported.configRoot=$settings.configRoot
 return $imported
}
function Get-AppRules($settings,[switch]$CheckPaths){
 $valid=Normalize-Settings $settings;$rules=@()
 foreach($a in $valid.apps){
  if(!$a.enabled -or $a.route -eq 'follow'){continue}
  if($CheckPaths -and $a.match -ne 'name' -and !(Test-Path -LiteralPath $a.path -PathType Leaf)){throw ('找不到程序，请重新定位：'+$a.name)}
  $target=if($a.route -eq 'direct'){'DIRECT'}else{'GLOBAL'}
  $rule=switch($a.match){
   'path'{'PROCESS-PATH,'+$a.path+','+$target}
   'name'{'PROCESS-NAME,'+$a.processName+','+$target}
   'folder'{'PROCESS-PATH-REGEX,(?i)^'+[regex]::Escape((Split-Path -Parent $a.path).TrimEnd('\')+'\')+','+$target}
  }
  $rules+=$rule
 }
 return $rules
}
function Get-ManagedBlock([string[]]$rules){
 $json=ConvertTo-Json -InputObject @($rules) -Compress
 return "`r`n// PROXYPANEL MANAGED BEGIN v2"+"`r`n"+@"
(function () {
  var previousMain = main;
  main = function (config, profileName) {
    var result = previousMain(config, profileName);
    if (!result || typeof result !== 'object') throw new Error('Original main must return a config object');
    result.rules = $json.concat(result.rules || []);
    result['find-process-mode'] = 'always';
    result.mode = 'rule';
    return result;
  };
})();
"@+"`r`n// PROXYPANEL MANAGED END v2"
}
function Read-ManagedState([string]$dataDirectory=(Get-DataDirectory)){
 $p=Join-Path $dataDirectory 'managed.dpapi';if(!(Test-Path -LiteralPath $p)){return $null}
 $plain=[Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($p),$null,0)
 return ([Text.Encoding]::UTF8.GetString($plain)|ConvertFrom-Json)
}
function Save-ProtectedState($state,$path){
 $plain=[Text.Encoding]::UTF8.GetBytes(($state|ConvertTo-Json -Depth 20 -Compress))
 $bytes=[Security.Cryptography.ProtectedData]::Protect($plain,$null,0)
 [IO.Directory]::CreateDirectory((Split-Path -Parent $path))|Out-Null
 $tmp=$path+'.tmp';[IO.File]::WriteAllBytes($tmp,$bytes)
 if(Test-Path -LiteralPath $path){[IO.File]::Replace($tmp,$path,[NullString]::Value)}else{[IO.File]::Move($tmp,$path)}
}
function Get-ModeValue($text){
 $m=[regex]::Match($text,'(?m)^mode:[ \t]*(?:"(rule|global|direct)"|''(rule|global|direct)''|(rule|global|direct))[ \t]*(?:#[^\r\n]*)?\r?$')
 if(!$m.Success){throw 'Clash config.yaml 中没有可识别的 mode 字段；未修改配置。'}
 foreach($i in 1..3){if($m.Groups[$i].Success){return $m.Groups[$i].Value}}
}
function Set-ModeValue($text,$mode){if($mode -notmatch '^(rule|global|direct)$'){throw '不支持的模式值。'};return [regex]::Replace($text,'(?m)^mode:[^\r\n]*',('mode: '+$mode))}
function Invoke-ManagedRuleUpdate($settings,[string]$dataDirectory=(Get-DataDirectory),[switch]$Remove,[switch]$TestMode){
 $settings=Normalize-Settings $settings
 $root=[IO.Path]::GetFullPath($settings.configRoot)
 if($TestMode -and $root -ieq (Find-ClashRoot)){throw '测试不能写入自动检测到的真实配置目录。'}
 $state=Read-ManagedState $dataDirectory
 if($state -and $state.root -ine $root){throw '另一个 Clash 目录还有本工具的规则，请先撤销再更换目录。'}
 if(!$Remove){
  $rules=@(Get-AppRules $settings -CheckPaths:(!$TestMode))
  if(!$rules.Count){$Remove=$true}
 }
 if($Remove -and !$state){
  $candidate=Join-Path $root 'profiles\Script.js'
  if((Test-Path -LiteralPath $candidate) -and [IO.File]::ReadAllText($candidate).Contains('PROXYPANEL MANAGED BEGIN')){throw '发现本工具的规则段，但缺少对应本机备份。请从原电脑撤销或人工核对；未修改配置。'}
  return '本工具没有需要撤销的规则。应用沿用 Clash 现有配置；旧版工具或订阅中的规则未改动。'
 }
 if(!$TestMode -and (Get-Process clash-verge -ErrorAction SilentlyContinue)){throw '请先从系统托盘完全退出 Clash Verge，再应用或撤销。完成后重新打开 Clash 即可。'}
 $scriptPath=Join-Path $root 'profiles\Script.js';$configPath=Join-Path $root 'config.yaml'
 if(!(Test-Path -LiteralPath $scriptPath) -or !(Test-Path -LiteralPath $configPath)){throw '未找到 Clash Verge Rev 的 Script.js 和 config.yaml，请在设置中选择正确目录。'}
 $originalScriptBytes=[IO.File]::ReadAllBytes($scriptPath);$originalConfigBytes=[IO.File]::ReadAllBytes($configPath)
 $scriptText=[IO.File]::ReadAllText($scriptPath);$configText=[IO.File]::ReadAllText($configPath);$mode=Get-ModeValue $configText
 $base=$scriptText
 if($state){
  if(!$scriptText.EndsWith([string]$state.block,[StringComparison]::Ordinal)){throw '本工具管理的脚本段已被外部修改，请先核对。原文件未改动。'}
  $base=$scriptText.Substring(0,$scriptText.Length-$state.block.Length)
 }elseif($scriptText.Contains('PROXYPANEL MANAGED BEGIN')){throw '发现没有对应本机备份的管理段，请从原电脑撤销或人工核对。'}
 if($base -notmatch 'function\s+main\s*\('){throw '原全局脚本不是受支持的 function main 格式；未修改。'}
 if($Remove){
  if(!$state){throw '此目录没有本工具管理的规则。'}
  $newScript=$base
  $newConfig=if($mode -eq 'rule'){Set-ModeValue $configText (Get-ModeValue ('mode: '+$state.originalMode))}else{$configText}
 }else{
  $block=Get-ManagedBlock $rules;$newScript=$base+$block;$newConfig=Set-ModeValue $configText 'rule'
  $newState=@{schema=2;root=$root;block=$block;rules=$rules;originalMode=$(if($state){$state.originalMode}else{$mode});appliedAt=(Get-Date).ToUniversalTime().ToString('o');appsHash=(Get-TextHash ($settings.apps|ConvertTo-Json -Depth 10 -Compress))}
 }
 $journal=Join-Path $dataDirectory ('backups\'+(Get-Date -Format 'yyyyMMdd-HHmmssfff')+'-'+[guid]::NewGuid().ToString('N')+'.dpapi')
 Save-ProtectedState @{root=$root;script=[Convert]::ToBase64String($originalScriptBytes);config=[Convert]::ToBase64String($originalConfigBytes);state=$state} $journal
 # Reject changes made while the update was being prepared.
 if([IO.File]::ReadAllText($scriptPath) -cne $scriptText -or [IO.File]::ReadAllText($configPath) -cne $configText){throw '配置刚被其他程序修改，请重试。'}
 try{
  Write-AtomicText $scriptPath $newScript;Write-AtomicText $configPath $newConfig
  if($Remove){[IO.File]::Delete((Join-Path $dataDirectory 'managed.dpapi'))}else{Save-ProtectedState $newState (Join-Path $dataDirectory 'managed.dpapi')}
 }catch{
  [IO.File]::WriteAllBytes($scriptPath,$originalScriptBytes);[IO.File]::WriteAllBytes($configPath,$originalConfigBytes);throw
 }
 return $(if($Remove){'本工具的规则已撤销。请重新启动 Clash。'}else{'分流规则已保存。请重新启动 Clash，并保持规则模式；TUN 由 Clash 自行管理。'})
}
function Update-ManagedRules($settings,[string]$dataDirectory=(Get-DataDirectory),[switch]$Remove,[switch]$TestMode){
 [IO.Directory]::CreateDirectory($dataDirectory)|Out-Null
 $lock=$null
 try{
  try{$lock=[IO.File]::Open((Join-Path $dataDirectory 'update.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch{throw '另一个窗口正在修改规则，请稍后重试。'}
  Invoke-ManagedRuleUpdate $settings $dataDirectory -Remove:$Remove -TestMode:$TestMode
 }finally{if($lock){$lock.Dispose()}}
}
