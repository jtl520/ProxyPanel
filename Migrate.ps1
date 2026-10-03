param([string]$ConfigRoot=(Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev'),[switch]$Restore,[switch]$TestMode,[string[]]$AppDirectories,[switch]$NoDialog,[switch]$VerifyOnly,[string]$BackupDirectory=$PSScriptRoot)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Security
$utf8=New-Object Text.UTF8Encoding($false)
function Save-Text($path,$text){[IO.File]::WriteAllText($path,$text,$utf8)}
try {
 if($VerifyOnly){Write-Output 'MIGRATION_PREFLIGHT_OK';return}
 if(!$TestMode -and (Get-Process clash-verge -ErrorAction SilentlyContinue)){throw '请先从托盘完全退出 Clash Verge，再运行此工具。'}
 $root=[IO.Path]::GetFullPath($ConfigRoot)
 $relative=@('profiles\Script.js','config.yaml','verge.yaml')
 $journal=Join-Path $BackupDirectory 'migration-backup.dpapi'
 if($Restore){
  if(!(Test-Path $journal)){throw '没有本机迁移备份。'}
  $b=[Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($journal),$null,0))|ConvertFrom-Json
  if($b.root -ne $root){throw '备份目录与当前 Clash 目录不一致。'}
  foreach($f in $b.files){if($f.relative -notin $relative){throw '备份路径无效'};$path=Join-Path $root $f.relative;if((Get-FileHash $path).Hash -ne $f.appliedHash){throw '安装后配置已变化，为避免覆盖，请保留备份并人工核对。'}}
  foreach($f in $b.files){[IO.File]::WriteAllBytes((Join-Path $root $f.relative),[Convert]::FromBase64String($f.data))}
  Move-Item -LiteralPath $journal -Destination ($journal+'.restored-'+(Get-Date -Format yyyyMMddHHmmssfff)+'-'+[guid]::NewGuid().ToString('N'))
 }else{
  if(Test-Path $journal){throw '已存在迁移备份。请勿重复应用；需要时先运行撤销迁移。'}
  foreach($r in $relative){if(!(Test-Path (Join-Path $root $r))){throw '未找到标准 Clash Verge Rev 配置。请先安装并启动一次、导入订阅，然后退出。'}}
  $scriptPath=Join-Path $root 'profiles\Script.js';$old=[IO.File]::ReadAllText($scriptPath)
  $clean=[regex]::Replace($old,'(?m)//[^\r\n]*','').Trim()
  if($clean -notmatch '^function\s+main\s*\(\s*config\s*(,\s*profileName\s*)?\)\s*\{\s*return\s+config\s*;?\s*\}$'){throw '已有自定义全局脚本，工具不会覆盖。请人工合并规则。'}
  if(!$TestMode){
   $AppDirectories=@()
   foreach($name in @('百度网盘','夸克网盘')){
    $d=New-Object Windows.Forms.FolderBrowserDialog;$d.Description='选择'+$name+'安装目录（包含主程序）；未安装请取消'
    if($d.ShowDialog() -eq 'OK'){
     $exe=if($name -eq '百度网盘'){'BaiduNetdisk.exe'}else{'quark_cloud_drive.exe'}
     if(!(Test-Path (Join-Path $d.SelectedPath $exe))){throw ('所选目录没有 '+$exe)}
     $AppDirectories+=$d.SelectedPath
    };$d.Dispose()
   }
  }
  $rules=@('PROCESS-NAME,chrome.exe,DIRECT','PROCESS-NAME,BaiduNetdisk.exe,DIRECT','PROCESS-NAME,quark_cloud_drive.exe,DIRECT')
  foreach($dir in $AppDirectories){if($dir.Contains(',')){throw '目录包含逗号，无法安全生成规则'};$rules+='PROCESS-PATH-REGEX,(?i)^'+[regex]::Escape($dir.TrimEnd('\')+'\')+',DIRECT'}
  $rules+='MATCH,GLOBAL'
  $js='// ProxyPanel migration v1'+"`r`n"+'function main(config) { config.rules = '+(ConvertTo-Json -InputObject $rules -Compress)+'.concat(config.rules || []); config["find-process-mode"]="always"; config.mode="rule"; config.tun=Object.assign({},config.tun||{},{enable:true}); return config; }'
  $config=[IO.File]::ReadAllText((Join-Path $root 'config.yaml'));$verge=[IO.File]::ReadAllText((Join-Path $root 'verge.yaml'))
  if(([regex]::Matches($config,'(?m)^mode:')).Count -ne 1 -or ([regex]::Matches($verge,'(?m)^enable_tun_mode:')).Count -ne 1){throw '配置格式不兼容，未修改。'}
  $new=@($js,[regex]::Replace($config,'(?m)^mode:[^\r\n]*','mode: rule'),[regex]::Replace($verge,'(?m)^enable_tun_mode:[^\r\n]*','enable_tun_mode: true'))
  $files=@();for($i=0;$i -lt 3;$i++){$bytes=$utf8.GetBytes($new[$i]);$sha=[Security.Cryptography.SHA256]::Create();$hash=[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','');$sha.Dispose();$files+=@{relative=$relative[$i];data=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $root $relative[$i])));appliedHash=$hash}}
  $b=@{root=$root;files=$files};$plain=[Text.Encoding]::UTF8.GetBytes(($b|ConvertTo-Json -Depth 8));[IO.File]::WriteAllBytes($journal,[Security.Cryptography.ProtectedData]::Protect($plain,$null,0))
  try{for($i=0;$i -lt 3;$i++){Save-Text (Join-Path $root $relative[$i]) $new[$i]}}catch{foreach($f in $files){[IO.File]::WriteAllBytes((Join-Path $root $f.relative),[Convert]::FromBase64String($f.data))};Remove-Item -LiteralPath $journal;throw}
 }
 if(!$TestMode -and !$NoDialog){[void][Windows.Forms.MessageBox]::Show('完成。请启动 Clash，在 GLOBAL 中选择自己的代理节点，确认规则模式和 TUN 已开启，再打开观察台验证连接。','迁移配置')}
}catch{if($TestMode){throw};[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'未完成迁移');if($NoDialog){throw}}
