param([Parameter(Mandatory=$true)][string]$ManifestPath)
$ErrorActionPreference='Stop'
$manifest=Get-Content -LiteralPath $ManifestPath -Raw|ConvertFrom-Json
$testRoot=[IO.Path]::GetFullPath($manifest.root)
if(!$testRoot.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){throw 'Options tests require a TEMP fixture'}
$env:PROXYPANEL_DATA_DIR=Join-Path $testRoot 'data'
. (Join-Path $PSScriptRoot 'ProxyPanel.ps1') -LibraryOnly
$initial=New-PanelSettings
Save-Settings $initial|Out-Null
# Load the production window and event handlers, excluding only its modal entry point.
$source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Dashboard.ps1'))
$boundary=$source.IndexOf('if($LayoutTest){',[StringComparison]::Ordinal)
if($boundary -lt 0){throw 'Dashboard test boundary changed'}
. ([scriptblock]::Create($source.Substring(0,$boundary).Replace('$PSScriptRoot',("'"+$PSScriptRoot.Replace("'","''")+"'"))))
$window.Show()
function Assert($ok,$message){if(!$ok){throw $message}}
function Save-ThroughEditor($existing,$spec,$match,$route,$enabled){
 $driver=New-Object Windows.Threading.DispatcherTimer
 $driver.Interval=[timespan]::FromMilliseconds(100)
 $driver.Tag=@{owner=$window;spec=$spec;match=$match;route=$route;enabled=$enabled;error=''}
 $driver.Add_Tick({param($sender,$eventArgs)
  $sender.Stop();$ctx=$sender.Tag
  try{
   $dialogs=@($ctx.owner.OwnedWindows|Where-Object Title -eq '应用设置')
   if($dialogs.Count -ne 1){throw 'Expected one app editor'}
   $dialog=$dialogs[0];$children=@($dialog.Content.Children)
   $boxes=@($children|Where-Object {$_ -is [Windows.Controls.TextBox]})
   $combos=@($children|Where-Object {$_ -is [Windows.Controls.ComboBox]})
   $toggle=@($children|Where-Object {$_ -is [Windows.Controls.CheckBox]})
   $save=@($children|Where-Object {$_ -is [Windows.Controls.Button] -and $_.Content -eq '保存应用'})
   if($boxes.Count -ne 2 -or $combos.Count -ne 2 -or $toggle.Count -ne 1 -or $save.Count -ne 1){throw 'Editor control contract changed'}
   $boxes[0].Text=$ctx.spec.name;$boxes[1].Text=$ctx.spec.path
   $combos[0].SelectedIndex=[array]::IndexOf(@('path','folder','name'),$ctx.match)
   $combos[1].SelectedIndex=[array]::IndexOf(@('direct','global','follow'),$ctx.route)
   $toggle[0].IsChecked=$ctx.enabled
   $save[0].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
  }catch{$ctx.error=$_.Exception.Message;foreach($d in @($ctx.owner.OwnedWindows)){$d.Close()}}
 })
 $driver.Start()
 try{$result=Show-AppEditor $existing $spec.path;if($driver.Tag.error){throw $driver.Tag.error};return $result}finally{$driver.Stop()}
}
$cases=@();$checks=0
try{
 foreach($match in @('path','folder','name')){foreach($enabled in @($true,$false)){foreach($route in @('direct','global','follow')){
  foreach($spec in $manifest.apps){
   $existing=$script:settings.apps|Where-Object name -eq $spec.name
   $edited=Save-ThroughEditor $existing $spec $match $route $enabled
   Assert ($edited -and $edited.match -eq $match -and $edited.route -eq $route -and $edited.enabled -eq $enabled) 'Editor failed to save requested options'
   $script:settings.apps=@($script:settings.apps|Where-Object name -ne $spec.name)+@($edited)
   Save-Changes;Render-Apps
   if($enabled){
    # Exercise every list dropdown event as well as the editor's save event.
    $script:rows[$edited.id].combo.SelectedIndex=([array]::IndexOf(@('direct','global','follow'),$route)+1)%3
    $script:rows[$edited.id].combo.SelectedIndex=[array]::IndexOf(@('direct','global','follow'),$route)
   }else{Assert (!$script:rows[$edited.id].combo.IsEnabled) 'Disabled app dropdown should be disabled'}
   $persisted=(Read-Settings).apps|Where-Object id -eq $edited.id
   Assert ($persisted.route -eq $route -and $persisted.match -eq $match -and $persisted.enabled -eq $enabled) 'UI and saved settings disagree'
   $checks++
  }
  $name=$match+'-'+$route+'-'+$(if($enabled){'enabled'}else{'disabled'})
  $casePath=Join-Path $testRoot ('cases\'+$name+'.json')
  Write-AtomicText $casePath ($script:settings|ConvertTo-Json -Depth 10)
  $cases+=@{name=$name;match=$match;route=$route;enabled=$enabled;settings=$casePath}
 }}}
 foreach($id in @($script:rows.Keys)){
  $card=$script:rows[$id].card
  $ops=$card.Child.Children[$card.Child.Children.Count-1]
  $remove=@($ops.Children|Where-Object {$_ -is [Windows.Controls.Button] -and $_.Content -eq '移除'})
  Assert ($remove.Count -eq 1) 'Remove control not found'
  $remove[0].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
  Assert (!((Read-Settings).apps|Where-Object id -eq $id)) 'Removed application was retained'
  $checks++
 }
 $casePath=Join-Path $testRoot 'cases\removed.json'
 Write-AtomicText $casePath ($script:settings|ConvertTo-Json -Depth 10)
 $cases+=@{name='removed';match='none';route='follow';enabled=$false;settings=$casePath}
 Write-AtomicText (Join-Path $testRoot 'cases.json') (ConvertTo-Json -InputObject $cases -Depth 8)
 Write-Output ('PASS: '+$checks+' app/option UI cases, real editor save, all dropdown values, disabled controls, remove, and persisted settings.')
}finally{$window.Close()}
