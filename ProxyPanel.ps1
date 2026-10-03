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
    $m=[regex]::Match($Text,'(?m)^'+[regex]::Escape($Key)+':[ \t]*([^\r\n]*)')
    if (!$m.Success) { return '' }
    $value=$m.Groups[1].Value.Trim()
    if($value.StartsWith('"')){return ($value|ConvertFrom-Json)}
    if($value.StartsWith("'")){
        if(!$value.EndsWith("'")){throw 'Invalid quoted YAML scalar'}
        return $value.Substring(1,$value.Length-2).Replace("''","'")
    }
    return [regex]::Replace($value,'[ \t]+#.*$','')
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
. (Join-Path $PSScriptRoot 'Core.ps1')
. (Join-Path $PSScriptRoot 'Monitor.ps1')
function Get-PanelSnapshot { Get-ApplicationSnapshot (Read-Settings) }
if($LibraryOnly){return}
if($Check){Get-PanelSnapshot|ConvertTo-Json -Depth 8;exit}
& (Join-Path $PSScriptRoot 'Dashboard.ps1')
