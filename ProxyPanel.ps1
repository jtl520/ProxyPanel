param([switch]$Check,[switch]$LibraryOnly)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
if (-not ('LocalClashReadOnly' -as [type])) { Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.IO.Pipes;
using System.Text;
using System.Threading;
public static class LocalClashReadOnly {
  public static string Get(string pipeName, string path, string secret) {
    if (path != "/version" && path != "/configs" && path != "/connections" && path != "/proxies" && path != "/rules") throw new ArgumentException("Read endpoint not allowed");
    using (var pipe = new NamedPipeClientStream(".", pipeName, PipeDirection.InOut, PipeOptions.Asynchronous))
    using (var cancel = new CancellationTokenSource(1800)) {
      pipe.Connect(1200);
      string auth = String.IsNullOrEmpty(secret) ? "" : "Authorization: Bearer " + secret.Replace("\r", "").Replace("\n", "") + "\r\n";
      byte[] request = Encoding.UTF8.GetBytes("GET " + path + " HTTP/1.1\r\nHost: localhost\r\n" + auth + "Connection: close\r\n\r\n");
      pipe.WriteAsync(request,0,request.Length,cancel.Token).GetAwaiter().GetResult();
      using (var output = new MemoryStream()) {
        byte[] buffer = new byte[8192]; int n;
        while ((n = pipe.ReadAsync(buffer,0,buffer.Length,cancel.Token).GetAwaiter().GetResult()) > 0) {
          output.Write(buffer,0,n);
          if (output.Length > 8388608) throw new IOException("Response too large");
        }
        string raw = Encoding.UTF8.GetString(output.ToArray());
        int split = raw.IndexOf("\r\n\r\n");
        if (split < 0 || !raw.StartsWith("HTTP/1.1 200")) throw new IOException("Local API unavailable");
        string header=raw.Substring(0,split), body=raw.Substring(split+4);
        if (header.IndexOf("Transfer-Encoding: chunked",StringComparison.OrdinalIgnoreCase)>=0) {
          var decoded=new StringBuilder(); int pos=0;
          while(true) { int end=body.IndexOf("\r\n",pos); if(end<0) throw new IOException("Invalid response");
            int size=Convert.ToInt32(body.Substring(pos,end-pos).Split(';')[0],16); if(size==0) break;
            // Decode chunks as bytes, since JSON may contain non-ASCII text.
            byte[] bytes=Encoding.UTF8.GetBytes(body.Substring(end+2));
            if(bytes.Length<size) throw new IOException("Incomplete response");
            string chunk=Encoding.UTF8.GetString(bytes,0,size); decoded.Append(chunk); pos=end+2+chunk.Length+2;
          } body=decoded.ToString();
        }
        return body;
      }
    }
  }
}
'@
}

function Read-Scalar([string]$Text,[string]$Key) {
    $m=[regex]::Match($Text,'(?m)^'+[regex]::Escape($Key)+':\s*([^\r\n]*)')
    if (!$m.Success) { return '' }
    return $m.Groups[1].Value.Trim().Trim([char]34,[char]39)
}
function Normalize-IP([string]$Address) {
    $ip=$null
    if([Net.IPAddress]::TryParse($Address,[ref]$ip)) {
        if($ip.IsIPv4MappedToIPv6){$ip=$ip.MapToIPv4()}
        return $ip.ToString()
    }
    return $Address
}
function Resolve-ConnectionOwner($Connection,$SocketIndex,$ProcessIndex) {
    $m=$Connection.metadata
    $named=[IO.Path]::GetFileName([string]$m.processPath)
    if(!$named){$named=[IO.Path]::GetFileName([string]$m.process)}
    if($named){return [pscustomobject]@{name=($named -replace '\.exe$','');path=[string]$m.processPath;basis='Clash 进程记录'}}
    # Do not infer an owner from UDP port alone, or from a shared local TCP endpoint.
    if($m.network -ne 'tcp'){return $null}
    $key="$(Normalize-IP ([string]$m.sourceIP))|$($m.sourcePort)"
    $candidates=@($SocketIndex[$key] | Where-Object { $null -ne $_ })
    if($candidates.Count -gt 1){
        $candidates=@($candidates|Where-Object {
            (Normalize-IP $_.RemoteAddress) -eq (Normalize-IP ([string]$m.destinationIP)) -and $_.RemotePort -eq $m.destinationPort
        })
    }
    if($candidates.Count -ne 1){return $null}
    $socket=$candidates[0]
    # Reject a reused port if the Windows socket was created after the Clash connection.
    if($socket.CreationTime -and $Connection.start){
        try { if(([datetime]$socket.CreationTime).ToUniversalTime() -gt ([datetime]$Connection.start).ToUniversalTime().AddSeconds(3)){return $null} }catch{return $null}
    }
    $proc=$ProcessIndex[[int]$socket.OwningProcess]
    if(!$proc){return $null}
    return [pscustomobject]@{name=$proc.ProcessName;path=[string]$proc.Path;basis='Windows TCP 地址/端口 → PID → Clash 策略链'}
}
function Get-RouteKind($Connection,$ProxyTypes) {
    $chain=@($Connection.chains)
    if($chain.Count -eq 0){return 'unknown'}
    $terminal=[string]$chain[0]
    $type=[string]$ProxyTypes[$terminal]
    if($terminal -eq 'DIRECT' -or $type -eq 'Direct'){return 'direct'}
    if($terminal -match '^REJECT' -or $type -match '^Reject'){return 'blocked'}
    if(!$type -or $type -match '^(Selector|URLTest|Fallback|LoadBalance|Relay|Pass|Compatible)$'){return 'unknown'}
    return 'proxy'
}
function Get-PanelSnapshot {
    $root=Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev'
    $file=Join-Path $root 'clash-verge.yaml'
    $text=''; if(Test-Path -LiteralPath $file){$text=[IO.File]::ReadAllText($file)}
    $tcp=@();$tcpError=$false
    try{$tcp=@(Get-NetTCPConnection -State Established -ErrorAction Stop)}catch{$tcpError=$true}
    $processes=@(Get-Process -ErrorAction SilentlyContinue)
    $processIndex=@{};foreach($proc in $processes){$processIndex[[int]$proc.Id]=$proc}
    $socketIndex=@{};foreach($socket in $tcp){$key="$(Normalize-IP $socket.LocalAddress)|$($socket.LocalPort)";if(!$socketIndex.ContainsKey($key)){$socketIndex[$key]=@()};$socketIndex[$key]+=$socket}
    $snapshot=[ordered]@{
        time=(Get-Date -Format 'HH:mm:ss'); source='本地配置文件（不是运行时验证）'; connected=$false
        mode=(Read-Scalar $text 'mode'); tun='未知'; port=(Read-Scalar $text 'mixed-port')
        version='未连接'; api='未发现受支持的本机接口'; apps=@(); warning=''; total=0; named=0; matched=0; chromeException=$false
    }
    $tunMatch=[regex]::Match($text,'(?ms)^tun:\s*\r?\n(?<block>(?:[ \t]+[^\r\n]*\r?\n|\r?\n)*)')
    if($tunMatch.Success){$enabled=[regex]::Match($tunMatch.Groups['block'].Value,'(?m)^\s+enable:\s*(true|false)'); if($enabled.Success){$snapshot.tun=$enabled.Groups[1].Value}}
    $connections=@();$proxyTypes=@{};$connectionsRead=$false;$ruleList=@();$rulesRead=$false
    $pipe=Read-Scalar $text 'external-controller-pipe'
    if($pipe.StartsWith('\\.\pipe\')) {
        try {
            $pipeName=$pipe.Substring(9); $secret=Read-Scalar $text 'secret'
            $config=[LocalClashReadOnly]::Get($pipeName,'/configs',$secret)|ConvertFrom-Json
            $snapshot.connected=$true; $snapshot.source='Mihomo 本机只读接口'; $snapshot.api='已连接 · 仅 GET 请求'
            $snapshot.mode=$config.mode; $snapshot.tun=[string]$config.tun.enable; $snapshot.port=$config.'mixed-port'
            try {$ruleData=[LocalClashReadOnly]::Get($pipeName,'/rules',$secret)|ConvertFrom-Json;$ruleList=@($ruleData.rules);$snapshot.chromeException=($config.mode -eq 'rule' -and $ruleList.Count -ge 2 -and $ruleList[0].type -eq 'ProcessName' -and $ruleList[0].payload -eq 'chrome.exe' -and $ruleList[0].proxy -eq 'DIRECT' -and @($ruleList | Select-Object -First 5 | Where-Object { $_.type -eq 'Match' -and $_.proxy -eq 'GLOBAL' }).Count -eq 1)}catch{}
            try {$version=[LocalClashReadOnly]::Get($pipeName,'/version',$secret)|ConvertFrom-Json; $snapshot.version=$version.version}catch{$snapshot.version='版本不可用'}
            try {$proxyData=[LocalClashReadOnly]::Get($pipeName,'/proxies',$secret)|ConvertFrom-Json;foreach($entry in $proxyData.proxies.PSObject.Properties){$proxyTypes[$entry.Name]=$entry.Value.type}}catch{}
            try {$response=[LocalClashReadOnly]::Get($pipeName,'/connections',$secret)|ConvertFrom-Json; $connections=@($response.connections|Where-Object {$null -ne $_});$connectionsRead=$true}catch{$snapshot.warning='运行状态可读，但连接列表暂时不可用。'}
        } catch {$snapshot.api='接口暂不可读 · 已回退到配置文件'; $snapshot.warning='未能确认实时状态；程序没有修改接口或权限。'}
    }
    if($snapshot.connected -and $ruleList.Count){$rulesRead=$true}
    $snapshot.routingSummary=if(!$snapshot.connected){'尚未核实运行配置'}elseif($snapshot.mode -eq 'global'){'全局模式：新连接使用 GLOBAL，直连例外不生效。'}elseif($snapshot.mode -eq 'direct'){'直连模式：新连接使用 DIRECT。'}else{'规则模式：新连接按当前规则分流。'}
    $resolved=@(foreach($connection in $connections){
        $owner=Resolve-ConnectionOwner $connection $socketIndex $processIndex
        if($owner){[pscustomobject]@{owner=$owner.name;path=$owner.path;basis=$owner.basis;kind=(Get-RouteKind $connection $proxyTypes);chain=(@($connection.chains) -join ' ← ');ingress=[string]$connection.metadata.type}}
    })
    $snapshot.total=$connections.Count;$snapshot.named=@($connections|Where-Object {$_.metadata.process -or $_.metadata.processPath}).Count;$snapshot.matched=$resolved.Count
    if($tcpError){$snapshot.warning='Windows TCP 表读取失败，仅使用 Clash 自带进程信息；未修改系统权限。'}
    $specs=@(
        @{name='Codex'; match='^(codex|chatgpt)$'; wire='^(codex|chatgpt)\.exe$'; goal='监控目标：沿用 GLOBAL 代理组'; note='子进程（如 Git、Python）需单独核实。'},
        @{name='VMware'; match='^(vmware|vmware-vmx|vmnat)$'; wire='^vmnat\.exe$'; goal='监控目标：NAT 流量沿用 GLOBAL'; note='观察 vmnat.exe；VMware 界面进程不代表虚拟机流量。'},
        @{name='Chrome'; match='^chrome$'; wire='^chrome\.exe$'; goal='监控目标：Clash DIRECT，保留 iGuge'; note='DIRECT 指 Clash 不再叠加代理节点，仍可能由 TUN 转发。'},
        @{name='夸克网盘';match='^quark_cloud_drive$';wire='^quark_cloud_drive\.exe$';path='detect';goal='监控目标：DIRECT，不消耗 Clash 节点流量';note='包含安装目录内的播放器和辅助进程；更改安装位置后须检查规则。'},
        @{name='百度网盘';match='^BaiduNetdisk$';wire='^BaiduNetdisk\.exe$';path='detect';goal='监控目标：DIRECT，不消耗 Clash 节点流量';note='包含安装目录内的下载和辅助进程；没有活动连接时无法验证。'}
    )
    foreach($spec in $specs){
        if($spec.path){
            $roots=@($processes | Where-Object {$_.ProcessName -match $spec.match -and $_.Path} | ForEach-Object {Split-Path -Parent $_.Path} | Sort-Object -Unique)
            $spec.path=if($roots.Count){'(?i)^(?:'+(($roots|ForEach-Object {[regex]::Escape($_+'\')}) -join '|')+')'}else{$null}
        }
        $running=@($processes|Where-Object {$_.ProcessName -match $spec.match -or ($spec.path -and $_.Path -match $spec.path)})
        $observed=@($resolved|Where-Object {($_.owner+'.exe') -match $spec.wire -or ($spec.path -and $_.path -match $spec.path)})
        $proxied=@($observed|Where-Object kind -eq 'proxy').Count
        $direct=@($observed|Where-Object kind -eq 'direct').Count
        $blocked=@($observed|Where-Object kind -eq 'blocked').Count
        $unknown=@($observed|Where-Object kind -eq 'unknown').Count
        $tunProxy=@($observed|Where-Object {$_.kind -eq 'proxy' -and $_.ingress -eq 'Tun'}).Count
        $explicitProxy=@($observed|Where-Object {$_.kind -eq 'proxy' -and $_.ingress -match '^(HTTP|HTTPS|Socks4|Socks5|SOCKS)$'}).Count
        $route=if(!$connectionsRead){'无法确认 · 连接列表不可用'}elseif($observed.Count -eq 0){'无法确认 · 无可归属的活动连接'}else{"已确认：代理 $proxied 条 / 直连 $direct 条 / 阻断 $blocked 条 / 未知 $unknown 条"}
        $basis=if($observed.Count){(@($observed.basis|Sort-Object -Unique) -join '；')}else{'没有匹配记录不代表直连；短连接、UDP 或间接代理可能无法归属。'}
        $routes=@($observed.chain|Sort-Object -Unique)
        $socketCount=@($tcp|Where-Object {($processIndex[[int]$_.OwningProcess].ProcessName+'.exe') -match $spec.wire -or ($spec.path -and $processIndex[[int]$_.OwningProcess].Path -match $spec.path)}).Count
        $transport="代理接入方式：TUN $tunProxy 条 / HTTP、SOCKS $explicitProxy 条"
        $detail="判定依据：$basis`r`n`r`n$transport`r`n全局模式：$($snapshot.mode -eq 'global')；TUN 开启：$($snapshot.tun)`r`nHTTP/SOCKS 连接也可经过全局代理，但不能算作 TUN 接入。`r`n`r`nClash 策略链：`r`n$($routes -join "`r`n")`r`n`r`nWindows 活动 TCP：$socketCount 条；可归属的 Clash 连接：$($observed.Count) 条。`r`n两次采样有时间差，数量不要求相等，未匹配连接不视作直连。`r`n`r`n仅说明本次采样中这些连接的处理方式，不代表整个应用的全部流量，也未验证公网出口。`r`n$($spec.note)"
        # Only describe the simple leading process-rule / GLOBAL setup that this panel manages.
        $policy='unknown'
        if($snapshot.connected){
            if($snapshot.mode -eq 'global'){$policy='global'}
            elseif($snapshot.mode -eq 'direct'){$policy='direct'}
            elseif($snapshot.mode -eq 'rule' -and $rulesRead){
                foreach($r in $ruleList){
                    if($r.type -eq 'ProcessName'){
                        if($r.payload -match $spec.wire){$policy=if($r.proxy -eq 'DIRECT'){'direct'}elseif($r.proxy -eq 'GLOBAL'){'global'}else{'unknown'};break}
                    }elseif($r.type -eq 'ProcessPathRegex'){
                        # Auxiliary-process coverage is checked separately by observed connections.
                        if($spec.name -in @('Codex','VMware')){continue}
                        break
                    }elseif($r.type -eq 'Match'){$policy=if($r.proxy -eq 'GLOBAL'){'global'}elseif($r.proxy -eq 'DIRECT'){'direct'}else{'unknown'};break}
                    else{break}
                }
            }
        }
        $snapshot.apps+= [pscustomobject]@{name=$spec.name;policy=$policy;running=($running.Count -gt 0);count=$running.Count;goal=$spec.goal;note=$spec.note;route=$route;basis=$basis;detail=$detail;connections=$observed.Count;proxied=$proxied;direct=$direct;tunProxy=$tunProxy;explicitProxy=$explicitProxy;transport=$transport}
    }
    return [pscustomobject]$snapshot
}

if($LibraryOnly){ return }
if($Check){ Get-PanelSnapshot | ConvertTo-Json -Depth 6; exit }
& (Join-Path $PSScriptRoot 'Dashboard.ps1')
