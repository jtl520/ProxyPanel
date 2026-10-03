param([switch]$LayoutTest,[switch]$InteractionTest)
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
[xml]$markup=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
 Title="应用代理观察台" Width="1080" Height="800" MinWidth="620" MinHeight="520" WindowStartupLocation="CenterScreen"
 Background="#F3F6F8" FontFamily="Microsoft YaHei UI" FontSize="13" Foreground="#172B3A" UseLayoutRounding="True" SnapsToDevicePixels="True">
 <Window.Resources>
  <Style TargetType="Button">
   <Setter Property="Background" Value="#FFFFFF"/><Setter Property="Foreground" Value="#294252"/>
   <Setter Property="BorderBrush" Value="#D8E2E8"/><Setter Property="BorderThickness" Value="1"/>
   <Setter Property="Padding" Value="16,9"/><Setter Property="Cursor" Value="Hand"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
    <Border x:Name="ButtonBorder" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8" Padding="{TemplateBinding Padding}">
     <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border>
    <ControlTemplate.Triggers>
     <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="ButtonBorder" Property="Opacity" Value="0.78"/></Trigger>
     <Trigger Property="IsEnabled" Value="False"><Setter TargetName="ButtonBorder" Property="Opacity" Value="0.4"/></Trigger>
    </ControlTemplate.Triggers>
   </ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style TargetType="TextBlock"><Setter Property="TextWrapping" Value="Wrap"/></Style>
 </Window.Resources>
 <Grid x:Name="Root" Background="#F3F6F8">
  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <Border x:Name="Header" Background="White" BorderBrush="#E0E7ED" BorderThickness="0,0,0,1" Padding="26,20">
   <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
    <StackPanel Margin="0,0,16,0">
     <TextBlock Text="应用代理观察台" FontSize="25" FontWeight="SemiBold"/>
     <TextBlock Text="查看流量去向，安心使用每个应用。" Foreground="#718493" Margin="0,5,0,0"/>
    </StackPanel>
    <Border Grid.Column="1" Background="#EAF6F1" CornerRadius="12" Padding="12,7" VerticalAlignment="Center">
     <TextBlock Text="●  只读监控" Foreground="#23745D" FontSize="12"/>
    </Border>
   </Grid>
  </Border>
  <ScrollViewer x:Name="Viewport" Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" CanContentScroll="False" Padding="20,18,20,18">
   <StackPanel>
    <Border Background="#163B40" CornerRadius="14" Padding="20,17" Margin="6,0,6,18">
     <StackPanel>
      <TextBlock x:Name="StateTitle" Text="正在读取连接状态…" Foreground="White" FontSize="18" FontWeight="SemiBold"/>
      <WrapPanel Margin="0,12,0,0">
       <TextBlock x:Name="ModeText" Text="模式 —" Foreground="#BFE5DE" Margin="0,0,24,5"/>
       <TextBlock x:Name="TunText" Text="TUN —" Foreground="#BFE5DE" Margin="0,0,24,5"/>
       <TextBlock x:Name="PortText" Text="端口 —" Foreground="#BFE5DE" Margin="0,0,24,5"/>
      </WrapPanel>
      <TextBlock x:Name="StateHint" Text="刷新只读取状态，不改变 Clash 的代理设置。" Foreground="#C0D4D5" FontSize="12" Margin="0,3,0,0"/>
     </StackPanel>
    </Border>
    <Grid Margin="6,0,6,10">
     <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
     <TextBlock Text="应用连接" FontSize="17" FontWeight="SemiBold"/>
     <TextBlock Grid.Column="1" Text="5 个应用" Foreground="#718493" VerticalAlignment="Center"/>
    </Grid>
    <WrapPanel x:Name="Cards" HorizontalAlignment="Stretch"/>
    <TextBlock Text="切换后已有连接可能继续沿用旧路线；数字是实际活动连接，不会随按钮立即清零。没有记录不等于直连。" Margin="8,8,8,4" Foreground="#718493" FontSize="12"/>
   </StackPanel>
  </ScrollViewer>
  <Border x:Name="Footer" Grid.Row="2" Background="White" BorderBrush="#E0E7ED" BorderThickness="0,1,0,0" Padding="26,12">
   <StackPanel>
    <WrapPanel>
     <Button x:Name="Refresh" Content="刷新状态" Background="#207663" Foreground="White" BorderBrush="#207663" Margin="0,0,12,8"/>
     <CheckBox x:Name="AutoRefresh" Content="自动刷新（3 秒）" IsChecked="True" VerticalAlignment="Center" Margin="0,0,18,8" Foreground="#536C7C"/>
     <Button x:Name="EnableBypass" Content="配置本机分流" Margin="0,0,10,8" Background="#207663" Foreground="White" ToolTip="首次使用或重新启用分流。请先从托盘退出 Clash，再选择本机网盘目录。"/>
     <Button x:Name="UndoNetdisk" Visibility="Collapsed" Content="撤销网盘调整" Margin="0,0,10,8" ToolTip="恢复到 Chrome 直连、其余走 GLOBAL 的备份状态。会覆盖该备份之后相关配置文件的改动。"/>
     <Button x:Name="RestoreAll" Content="撤销本工具配置" Margin="0,0,0,8" ToolTip="退出 Clash 后恢复在本机配置分流之前的备份。"/>
    </WrapPanel>
    <TextBlock x:Name="Updated" Text="等待首次读取…" Foreground="#718493" FontSize="11"/>
   </StackPanel>
  </Border>
 </Grid>
</Window>
'@
$window=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $markup))
$window.Icon=[Windows.Media.Imaging.BitmapFrame]::Create([uri](Join-Path $PSScriptRoot 'ProxyPanel.ico'))
$work=[Windows.SystemParameters]::WorkArea
$window.Width=[Math]::Min(1080,$work.Width*0.92)
$window.Height=[Math]::Min(800,$work.Height*0.92)
$ui=@{};foreach($name in @('Root','Header','Viewport','Cards','Footer','StateTitle','StateHint','ModeText','TunText','PortText','Refresh','AutoRefresh','EnableBypass','UndoNetdisk','RestoreAll','Updated')){$ui[$name]=$window.FindName($name)}
$script:tiles=@()
function New-Text($text,$size,$color){
 $v=New-Object Windows.Controls.TextBlock;$v.Text=$text;$v.FontSize=$size;$v.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString($color);$v.TextWrapping='Wrap';return $v
}
foreach($appName in @('Codex','VMware','Chrome','夸克网盘','百度网盘')){
 $card=New-Object Windows.Controls.Border;$card.Background=[Windows.Media.Brushes]::White;$card.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFromString('#DFE7EC');$card.BorderThickness='1';$card.CornerRadius='12';$card.Padding='18';$card.Margin='6,0,6,12';$card.Height=182
 $grid=New-Object Windows.Controls.Grid
 foreach($h in @('Auto','Auto','*','Auto')){$row=New-Object Windows.Controls.RowDefinition;$row.Height=[Windows.GridLengthConverter]::new().ConvertFromString($h);$grid.RowDefinitions.Add($row)}
 $top=New-Object Windows.Controls.DockPanel
 $badge=New-Object Windows.Controls.Border;$badge.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#F0F4F7');$badge.CornerRadius='9';$badge.Padding='9,4';$badge.HorizontalAlignment='Right';[Windows.Controls.DockPanel]::SetDock($badge,'Right')
 $badgeText=New-Text '待检测' 11 '#708493';$badge.Child=$badgeText;[void]$top.Children.Add($badge)
 $title=New-Text $appName 18 '#172B3A';$title.FontWeight='SemiBold';$title.Margin='0,0,12,0';[void]$top.Children.Add($title);[void]$grid.Children.Add($top)
 $goalText='当前配置 · 正在读取…'
 $goal=New-Text $goalText 12 '#718493';$goal.Margin='0,8,0,9';[Windows.Controls.Grid]::SetRow($goal,1);[void]$grid.Children.Add($goal)
 $content=New-Object Windows.Controls.StackPanel;[Windows.Controls.Grid]::SetRow($content,2)
 $summary=New-Text '等待连接数据' 16 '#294252';$summary.FontWeight='SemiBold';[void]$content.Children.Add($summary)
 $transport=New-Text '—' 11 '#718493';$transport.Margin='0,6,0,0';[void]$content.Children.Add($transport);[void]$grid.Children.Add($content)
 $bottom=New-Object Windows.Controls.DockPanel;[Windows.Controls.Grid]::SetRow($bottom,3)
 $details=New-Object Windows.Controls.Button;$details.Content='连接详情  →';$details.Padding='10,5';$details.FontSize=11;$details.IsEnabled=$false;[Windows.Controls.DockPanel]::SetDock($details,'Right');[void]$bottom.Children.Add($details)
 $run=New-Text '等待检测' 11 '#718493';$run.VerticalAlignment='Center';[void]$bottom.Children.Add($run);[void]$grid.Children.Add($bottom)
 $details.Add_Click({param($sender,$eventArgs)
  $dialog=New-Object Windows.Window;$dialog.Owner=$window;$dialog.Title='连接判定依据';$dialog.Width=[Math]::Min(650,$work.Width*0.85);$dialog.Height=[Math]::Min(510,$work.Height*0.85);$dialog.WindowStartupLocation='CenterOwner';$dialog.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#F3F6F8')
  $scroll=New-Object Windows.Controls.ScrollViewer;$scroll.VerticalScrollBarVisibility='Auto';$scroll.Padding='24'
  $body=New-Text ([string]$sender.Tag) 13 '#294252';$body.FontFamily='Microsoft YaHei UI';$scroll.Content=$body;$dialog.Content=$scroll;[void]$dialog.ShowDialog()
 })
 $card.Child=$grid;[void]$ui.Cards.Children.Add($card)
 $script:tiles+=@{card=$card;goal=$goal;badge=$badge;badgeText=$badgeText;summary=$summary;transport=$transport;run=$run;details=$details}
}
function Resize-Cards {
 $available=$ui.Viewport.ActualWidth-58
 if($available -lt 200){return}
 $columns=if($available -ge 810){2}else{1}
 $width=[Math]::Floor($available/$columns)-12
 foreach($tile in $script:tiles){$tile.card.Width=$width}
}
$ui.Viewport.Add_SizeChanged({Resize-Cards})
function Show-Snapshot($snapshot){
 $ui.ModeText.Text='模式 · '+$(switch($snapshot.mode){'rule'{'规则'}'global'{'全局'}'direct'{'直连'}default{'未知'}})
 $ui.TunText.Text='TUN · '+$(if($snapshot.tun -eq 'True'){'已开启'}elseif($snapshot.tun -eq 'False'){'已关闭'}else{'未知'})
 $ui.PortText.Text='代理端口 · '+$snapshot.port
 $ui.StateTitle.Text=if($snapshot.connected){'已连接 Clash · 本机实时状态'}else{'暂未连接 Clash · 当前为文件配置'}
 $ui.StateHint.Text=if($snapshot.warning){$snapshot.warning}else{$snapshot.routingSummary+' 已有连接可能保留切换前的路线。'}
 for($i=0;$i -lt $script:tiles.Count;$i++){
  $a=$snapshot.apps[$i];$tile=$script:tiles[$i]
  $tile.goal.Text=switch($a.policy){'direct'{'当前配置 · DIRECT 直连'}'global'{'当前配置 · 使用 GLOBAL 组'}default{'当前配置 · 按规则，需查看连接'}}
  $tile.summary.Text=if($a.connections -gt 0){"直连 $($a.direct)    代理 $($a.proxied)"}else{'暂无可归属的活动连接'}
  $tile.transport.Text=if($a.connections -gt 0){"代理接入：TUN $($a.tunProxy) · HTTP/SOCKS $($a.explicitProxy)"}else{'无记录不代表直连，使用应用后可再次刷新。'}
  $tile.summary.ToolTip=$a.route
  $tile.run.Text=if($a.running){"●  运行中 · $($a.count) 个进程"}else{'○  未运行'}
  $expected=if($a.policy -eq 'global'){$a.proxied}elseif($a.policy -eq 'direct'){$a.direct}else{0}
  $unexpected=if($a.policy -eq 'global'){$a.direct}elseif($a.policy -eq 'direct'){$a.proxied}else{0}
  $label='待确认';$color='#718493';$background='#F0F4F7'
  if($a.connections -gt 0 -and $unexpected -gt 0){$label='路线不一致';$color='#A36020';$background='#FFF1DE'}
  elseif($a.connections -gt 0 -and $expected -eq $a.connections){$label='符合配置';$color='#23745D';$background='#EAF6F1'}
  $tile.badge.ToolTip='对比当前配置与实际连接。切换前的旧连接可能继续存在。'
  $tile.badgeText.Text=$label;$tile.badgeText.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString($color);$tile.badge.Background=[Windows.Media.BrushConverter]::new().ConvertFromString($background)
  $tile.details.Tag=$a.detail;$tile.details.IsEnabled=$true
 }
 $ui.Updated.Text="更新于 $($snapshot.time)  ·  已识别 $($snapshot.matched) / $($snapshot.total) 条 Clash 连接  ·  刷新不会修改代理配置"
}
$script:reader=$null;$script:pending=$null;$script:lastRefresh=[datetime]::MinValue
$script:action=$null;$script:refreshRequested=$false;$script:actionNotice='';$script:refreshCount=0
function Start-Refresh {
 if($script:pending -or $script:action){$script:refreshRequested=$true;return}
 $script:refreshRequested=$false
 $ui.Refresh.IsEnabled=$false;$ui.Refresh.Content='读取中…'
 if(!$script:reader){
  $script:reader=[PowerShell]::Create()
  [void]$script:reader.AddScript('param($source) . $source -LibraryOnly; Get-PanelSnapshot').AddArgument((Join-Path $PSScriptRoot 'ProxyPanel.ps1'))
 }else{$script:reader.Commands.Clear();$script:reader.Streams.Error.Clear();[void]$script:reader.AddScript('Get-PanelSnapshot')}
 $script:pending=$script:reader.BeginInvoke()
}
function Set-ActionEnabled($enabled){foreach($name in @('EnableBypass','UndoNetdisk','RestoreAll')){$ui[$name].IsEnabled=$enabled}}
function Start-ConfigAction([string]$scriptName,[string]$extra=''){
 if($script:action){return}
 try{
  $actionArgs='-NoProfile -ExecutionPolicy Bypass -STA -File "'+(Join-Path $PSScriptRoot $scriptName)+'" -NoDialog '+$extra
  $script:action=Start-Process -FilePath 'powershell.exe' -ArgumentList $actionArgs -WindowStyle Hidden -PassThru
  Set-ActionEnabled $false
  $script:actionNotice='';$ui.StateTitle.Text='正在切换配置…';$ui.Updated.Text='切换完成后自动读取实际状态，请稍候。'
 }catch{$ui.Updated.Text='无法启动切换：'+$_.Exception.Message;Set-ActionEnabled $true}
}
$pulse=New-Object Windows.Threading.DispatcherTimer;$pulse.Interval=[timespan]::FromMilliseconds(250)
function Invoke-PanelPulse {
 # Drain pre-switch reads before observing completion so stale snapshots cannot overwrite new state.
 if($script:pending -and $script:pending.IsCompleted){
  try{
   $data=$script:reader.EndInvoke($script:pending)
   if(!$script:action){
    if($script:reader.HadErrors -or $data.Count -eq 0){throw 'Read failed'}
    Show-Snapshot $data[0];$script:refreshCount++
    if($script:actionNotice){$ui.Updated.Text=$script:actionNotice+'  ·  '+$ui.Updated.Text}
   }
  }catch{if(!$script:action){$ui.StateTitle.Text='读取失败，请稍后刷新';$ui.Updated.Text='上次数据可能已过期；请重新刷新。'}}
  finally{$script:pending=$null;$ui.Refresh.IsEnabled=$true;$ui.Refresh.Content='刷新状态';$script:lastRefresh=Get-Date}
 }
 if($script:action -and $script:action.HasExited -and !$script:pending){
  $script:action.WaitForExit();$code=$script:action.ExitCode;$script:action.Dispose();$script:action=$null
  Set-ActionEnabled $true
  $script:actionNotice=if($code -eq 0){'配置完成；请启动 Clash 后查看状态'}else{'未完成配置；请查看错误提示'}
  $script:refreshRequested=$true
 }
 if(!$script:action -and !$script:pending -and ($script:refreshRequested -or ($ui.AutoRefresh.IsChecked -and ((Get-Date)-$script:lastRefresh).TotalSeconds -ge 3))){Start-Refresh}
}
$pulse.Add_Tick({Invoke-PanelPulse})
$ui.Refresh.Add_Click({Start-Refresh})
$ui.EnableBypass.Add_Click({Start-ConfigAction 'Migrate.ps1'})
$ui.UndoNetdisk.Add_Click({Start-ConfigAction 'Migrate.ps1' '-Restore'})
$ui.RestoreAll.Add_Click({Start-ConfigAction 'Migrate.ps1' '-Restore'})
$window.Add_Closed({$pulse.Stop();if($script:reader){$script:reader.Stop();$script:reader.Dispose();$script:reader=$null};if($script:action){$script:action.Dispose()}})
if($InteractionTest){
 $ui.AutoRefresh.IsChecked=$false
 Start-Refresh
 Start-ConfigAction 'Migrate.ps1' '-VerifyOnly'
 if($ui.EnableBypass.IsEnabled){throw 'Switch buttons must be disabled while running'}
 $deadline=(Get-Date).AddSeconds(30)
 while(($script:action -or $script:pending -or $script:refreshRequested) -and (Get-Date) -lt $deadline){Start-Sleep -Milliseconds 100;Invoke-PanelPulse}
 if($script:refreshCount -ne 1 -or !$ui.EnableBypass.IsEnabled -or $script:actionNotice -notlike '配置完成*'){throw 'Completion refresh failed'}
 Start-Refresh
 while($script:pending -and (Get-Date) -lt $deadline){Start-Sleep -Milliseconds 100;Invoke-PanelPulse}
 if($script:refreshCount -ne 2){throw 'Persistent reader second refresh failed'}
 Start-ConfigAction 'Missing-Action-Test.ps1'
 while(($script:action -or $script:pending -or $script:refreshRequested) -and (Get-Date) -lt $deadline){Start-Sleep -Milliseconds 100;Invoke-PanelPulse}
 if($script:actionNotice -notlike '未完成配置*' -or !$ui.EnableBypass.IsEnabled -or $script:refreshCount -ne 3){throw 'Failed action recovery failed'}
 $window.Close();Write-Output 'INTERACTION_TEST_PASSED (read-only preflight; no proxy changes)'
}elseif($LayoutTest){
 Show-Snapshot (Get-PanelSnapshot)
 $window.Show()
 $results=@()
 foreach($size in @(@(1080,800),@(700,600),@(620,520))){
  $window.Width=$size[0];$window.Height=$size[1];$window.UpdateLayout();Resize-Cards;$window.UpdateLayout()
  $footerBottom=$ui.Footer.TranslatePoint([Windows.Point]::new(0,$ui.Footer.ActualHeight),$ui.Root).Y
  $fits=($footerBottom -le $ui.Root.ActualHeight+1 -and $ui.Viewport.ViewportHeight -gt 60)
  if(!$fits){throw 'Footer or scroll viewport does not fit'}
  $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$ui.Root.ActualWidth,[int]$ui.Root.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32)
  $bitmap.Render($ui.Root);$encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
  $file=Join-Path $PSScriptRoot ("layout-$($size[0])x$($size[1]).png");$stream=[IO.File]::Create($file);try{$encoder.Save($stream)}finally{$stream.Dispose()}
  $results+=[pscustomobject]@{width=$size[0];height=$size[1];footerVisible=$fits;cardWidth=$script:tiles[0].card.Width;scrollable=($ui.Viewport.ExtentHeight -gt $ui.Viewport.ViewportHeight)}
 }
 $window.Close();$results|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'verification-layout.json') -Encoding UTF8
 $results|ConvertTo-Json
}else{
 $window.Add_ContentRendered({Resize-Cards;Start-Refresh;$pulse.Start()})
 [void]$window.ShowDialog()
}
