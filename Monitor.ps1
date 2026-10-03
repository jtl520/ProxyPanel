function Get-SettingStatus($app,$snapshot,[bool]$missing){
 if($missing){return @{text='请重新选择程序';hint='原程序路径已失效。点击编辑，重新选择程序文件。';tone='warning'}}
 if($snapshot.pending){return @{text='更改尚未应用';hint='选择已保存。退出 Clash Verge → 应用设置 → 重新打开 Clash Verge。全部停用或交由 Clash 决定时，应用设置会移除本工具的规则。';tone='pending'}}
 if(!$app.enabled -or $app.route -eq 'follow'){return @{text=$(if(!$app.enabled){'不添加分流规则'}else{'使用 Clash 原有规则'});hint='本工具不为此应用添加覆盖规则，实际路线由原有规则决定。其他工具的规则仍然有效。';tone='neutral'}}
 if(!$snapshot.connected){return @{text='等待连接 Clash';hint='请先打开 Clash，再检查设置中的配置目录。';tone='neutral'}}
 if($snapshot.mode -ne 'rule'){return @{text='请切换到规则模式';hint='应用分流需要 Clash 使用规则模式。';tone='warning'}}
 if($snapshot.rulesLoaded -and $app.route -eq 'global' -and $snapshot.globalIsDirect){return @{text='代理组当前为直连';hint='GLOBAL 组最终选择了 DIRECT。请在 Clash Verge 中为该组选择代理节点；本工具不会自动切换节点。';tone='warning'}}
 if($snapshot.rulesLoaded){return @{text='设置已生效';hint='已在 Clash 中找到所选规则。右侧显示当前活动连接，旧连接可能保留原路线。';tone='success'}}
 if(!$snapshot.managed){return @{text='尚未应用';hint='当前只在观察已有连接。所选设置尚未通过本工具应用；已有连接可能来自旧配置。';tone='neutral'}}
 return @{text='等待 Clash 加载';hint='设置已写入，但运行规则尚未匹配。请重新打开 Clash；若仍未生效，请核对配置目录。';tone='pending'}
}
function Test-RulesPending($settings,$state){
 if(!$state){return $false}
 return (ConvertTo-Json -InputObject @(Get-AppRules $settings) -Compress) -cne (ConvertTo-Json -InputObject @($state.rules) -Compress)
}
function Get-GlobalRouteInfo($proxyData){
 $selected=[string]$proxyData.proxies.GLOBAL.now;$current=$selected;$visited=@{}
 while($current -and !$visited.ContainsKey($current)){
  $visited[$current]=$true;$entry=$proxyData.proxies.PSObject.Properties[$current]
  if(!$entry){break}
  if($entry.Value.type -eq 'Direct'){return @{selected=$selected;isDirect=$true}}
  $current=[string]$entry.Value.now
 }
 return @{selected=$selected;isDirect=$false}
}
function Get-ApplicationSnapshot($settings){
 $settings=Normalize-Settings $settings
 $snapshot=[ordered]@{time=(Get-Date -Format 'HH:mm:ss');connected=$false;mode='unknown';tun='未知';port='—';apps=@();warning='';version='';total=0;matched=0;rulesLoaded=$false;managed=$false;pending=$false;globalSelected='';globalIsDirect=$false;tcpFallbackUsed=$false}
 $root=$settings.configRoot;if(!$root){$root=Find-ClashRoot}
 $file=if($root){Join-Path $root 'clash-verge.yaml'}else{''}
 $connections=@();$ruleList=@();$proxyTypes=@{};$config=$null;$state=$null
 try{
  $state=Read-ManagedState;$snapshot.managed=($null -ne $state)
  if($state){$snapshot.pending=Test-RulesPending $settings $state}
 }catch{$snapshot.warning='无法读取本机规则备份，请检查设置目录。'}
 if($file -and (Test-Path -LiteralPath $file)){
  try{
   $yaml=[IO.File]::ReadAllText($file);$pipe=Read-Scalar $yaml 'external-controller-pipe';$secret=Read-Scalar $yaml 'secret'
   if(!$pipe.StartsWith('\\.\pipe\')){throw '当前客户端未提供受支持的本机管道。'}
   $pipe=$pipe.Substring(9)
   $config=[LocalClashReadOnly]::Get($pipe,'/configs',$secret)|ConvertFrom-Json
   $snapshot.connected=$true;$snapshot.mode=$config.mode;$snapshot.tun=[string]$config.tun.enable;$snapshot.port=$config.'mixed-port'
   $ruleList=@(([LocalClashReadOnly]::Get($pipe,'/rules',$secret)|ConvertFrom-Json).rules)
   $proxyData=[LocalClashReadOnly]::Get($pipe,'/proxies',$secret)|ConvertFrom-Json
   $globalInfo=Get-GlobalRouteInfo $proxyData;$snapshot.globalSelected=$globalInfo.selected;$snapshot.globalIsDirect=$globalInfo.isDirect
   foreach($entry in $proxyData.proxies.PSObject.Properties){$proxyTypes[$entry.Name]=$entry.Value.type}
   $connections=@(([LocalClashReadOnly]::Get($pipe,'/connections',$secret)|ConvertFrom-Json).connections|Where-Object {$null -ne $_})
   $expectedRules=@(Get-AppRules $settings)
   $snapshot.rulesLoaded=($config.mode -eq 'rule' -and $expectedRules.Count -gt 0 -and $ruleList.Count -ge $expectedRules.Count)
   if($snapshot.rulesLoaded){for($i=0;$i -lt $expectedRules.Count;$i++){
    $pieces=$expectedRules[$i] -split ','; $type=switch($pieces[0]){'PROCESS-NAME'{'ProcessName'}'PROCESS-PATH'{'ProcessPath'}'PROCESS-PATH-REGEX'{'ProcessPathRegex'}}
    if($ruleList[$i].type -ne $type -or $ruleList[$i].payload -ine $pieces[1] -or $ruleList[$i].proxy -ne $pieces[2]){$snapshot.rulesLoaded=$false;break}
   }}
  }catch{$snapshot.warning='无法完整读取 Clash：'+$_.Exception.Message}
 }else{$snapshot.warning='尚未找到 Clash Verge Rev。请在“设置”中检测或选择配置目录。'}
 $tcp=@();$socketIndex=@{};$processIndex=@{}
 if(@($connections|Where-Object {$_.metadata.network -eq 'tcp' -and !$_.metadata.processPath -and !$_.metadata.process}).Count){
  $snapshot.tcpFallbackUsed=$true
  try{$tcp=@(Get-NetTCPConnection -State Established -ErrorAction Stop)}catch{$snapshot.warning='无法读取系统 TCP 表，仅使用 Clash 的进程信息。'}
 }
 $processes=@(Get-Process -ErrorAction SilentlyContinue)
 foreach($proc in $processes){$processIndex[[int]$proc.Id]=$proc}
 foreach($socket in $tcp){$key="$(Normalize-IP $socket.LocalAddress)|$($socket.LocalPort)";if(!$socketIndex.ContainsKey($key)){$socketIndex[$key]=@()};$socketIndex[$key]+=$socket}
 $resolved=@(foreach($c in $connections){$owner=Resolve-ConnectionOwner $c $socketIndex $processIndex;if($owner){[pscustomobject]@{name=$owner.name;path=$owner.path;basis=$owner.basis;kind=(Get-RouteKind $c $proxyTypes);start=$c.start;chain=(@($c.chains)-join ' ← ');rule=$c.rule}}})
 $snapshot.total=$connections.Count;$snapshot.matched=$resolved.Count
 foreach($a in $settings.apps){
  $observed=@($resolved|Where-Object {Test-AppOwner $a $_})
  $running=@($processes|Where-Object {Test-AppOwner $a @{name=$_.ProcessName;path=[string]$_.Path}})
  $direct=@($observed|Where-Object kind -eq 'direct').Count;$proxied=@($observed|Where-Object kind -eq 'proxy').Count
  $unknown=@($observed|Where-Object kind -eq 'unknown').Count;$blocked=@($observed|Where-Object kind -eq 'blocked').Count
  $oldProxy=0
  if($snapshot.rulesLoaded -and !$snapshot.pending -and $state -and $state.root -ieq $root -and $a.enabled -and $a.route -eq 'direct'){
   foreach($c in $observed){if($c.kind -eq 'proxy' -and $c.start){try{if(([datetime]$c.start).ToUniversalTime() -lt ([datetime]$state.appliedAt).ToUniversalTime()){$oldProxy++}}catch{}}}
  }
  $missing=($a.match -ne 'name' -and !(Test-Path -LiteralPath $a.path -PathType Leaf))
  $settingStatus=Get-SettingStatus $a $snapshot $missing;$status=$settingStatus.text
  $detail="应用：$($a.name)`r`n匹配方式：$($a.match)`r`n程序：$($a.path)`r`n`r`n直连 $direct / 代理 $proxied / 阻断 $blocked / 未知 $unknown`r`n$((@($observed|ForEach-Object {$_.name+' · '+$_.basis+' · '+$_.chain}|Sort-Object -Unique)) -join "`r`n")`r`n`r`n只代表本次识别到的活动连接，未验证公网出口。跟随现有规则不会移除其他工具或订阅设置的规则。"
  $snapshot.apps+= [pscustomobject]@{id=$a.id;name=$a.name;running=($running.Count -gt 0);connections=$observed.Count;direct=$direct;proxied=$proxied;unknown=$unknown;blocked=$blocked;oldProxy=$oldProxy;status=$status;statusHint=$settingStatus.hint;statusTone=$settingStatus.tone;missing=$missing;detail=$detail}
 }
 return [pscustomobject]$snapshot
}
