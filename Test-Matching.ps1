$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ProxyPanel.ps1') -LibraryOnly
function Assert($Condition,$Message){if(!$Condition){throw $Message}}
$processes=@{42=[pscustomobject]@{ProcessName='chrome'}}
$socket=[pscustomobject]@{LocalAddress='127.0.0.1';LocalPort=50000;RemoteAddress='127.0.0.1';RemotePort=7897;OwningProcess=42;CreationTime=[datetime]'2026-01-01T00:00:00Z'}
$index=@{'127.0.0.1|50000'=@($socket)}
$connection=[pscustomobject]@{metadata=[pscustomobject]@{network='tcp';sourceIP='::ffff:127.0.0.1';sourcePort=50000;destinationIP='203.0.113.1';destinationPort=443};start='2026-01-01T00:00:01Z';chains=@('TestNode','GLOBAL')}
Assert ((Resolve-ConnectionOwner $connection $index $processes).name -eq 'chrome') 'Unique local proxy connection should resolve, including IPv4-mapped IPv6.'
$duplicate=@{'127.0.0.1|50000'=@($socket,$socket)}
Assert ($null -eq (Resolve-ConnectionOwner $connection $duplicate $processes)) 'Ambiguous endpoint must not be attributed.'
$connection.metadata.network='udp'
Assert ($null -eq (Resolve-ConnectionOwner $connection $index $processes)) 'UDP must not use the TCP fallback.'
$connection.metadata.network='tcp'
$connection.start='2025-01-01T00:00:00Z'
Assert ($null -eq (Resolve-ConnectionOwner $connection $index $processes)) 'Reused port must not match an older connection.'
$connection.start='2026-01-01T00:00:01Z'
Assert ($null -eq (Resolve-ConnectionOwner $connection @{} $processes)) 'Missing socket must stay unknown.'
Assert ($null -eq (Resolve-ConnectionOwner $connection $index @{})) 'Missing PID must stay unknown.'
Assert ((Get-RouteKind $connection @{'TestNode'='Shadowsocks'}) -eq 'proxy') 'Known proxy adapter should classify as proxy.'
Assert ((Get-RouteKind $connection @{}) -eq 'unknown') 'Unknown adapter must not be assumed to be a proxy.'
Assert ((Get-RouteKind $connection @{'TestNode'='Direct'}) -eq 'direct') 'Custom-named direct adapter must classify as direct.'
$connection.chains=@('DIRECT','GLOBAL')
Assert ((Get-RouteKind $connection @{}) -eq 'direct') 'Built-in DIRECT should classify as direct.'
$connection.chains=@('REJECT')
Assert ((Get-RouteKind $connection @{}) -eq 'blocked') 'Blocked traffic must not classify as proxy.'
$connection.chains=@()
Assert ((Get-RouteKind $connection @{}) -eq 'unknown') 'Empty chain must remain unknown.'
Assert ((Read-Scalar "secret:`nmode: rule" 'secret') -eq '') 'Empty scalar must not consume the next key.'
$pipe='\\.\pipe\test-panel'
Assert ((Read-Scalar ('external-controller-pipe: '+(ConvertTo-Json -InputObject $pipe -Compress)) 'external-controller-pipe') -ceq $pipe) 'Quoted pipe paths must be decoded.'
Write-Output 'PASS: 12 attribution/routing and 2 YAML scalar checks.'
