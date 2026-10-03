param([switch]$LayoutTest,[switch]$InteractionTest,[switch]$PickerTest)
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$script:settings=Read-Settings
$script:rows=@{};$script:refreshRequested=$false;$script:revision=0;$script:reader=$null;$script:pending=$null;$script:lastRefresh=[datetime]::MinValue;$script:readRevision=0;$script:rendering=$false
$script:routeKeys=@('direct','global','follow');$script:matchKeys=@('path','folder','name')
[xml]$markup=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="ProxyPanel · 应用分流" Width="1180" Height="800" MinWidth="820" MinHeight="600" WindowStartupLocation="CenterScreen" Background="#F4F6FA" FontFamily="Microsoft YaHei UI" FontSize="13" Foreground="#17283B">
 <Window.Resources>
  <Style TargetType="Button"><Setter Property="Padding" Value="14,9"/><Setter Property="Margin" Value="0,0,8,0"/><Setter Property="Background" Value="White"/><Setter Property="Foreground" Value="#293D52"/><Setter Property="BorderBrush" Value="#DCE3EB"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="B" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="8" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Opacity" Value="0.8"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter TargetName="B" Property="Opacity" Value="0.45"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
  <Style TargetType="TextBox"><Setter Property="Padding" Value="9,7"/><Setter Property="BorderBrush" Value="#DCE3EB"/><Setter Property="VerticalContentAlignment" Value="Center"/></Style>
  <Style TargetType="ComboBox"><Setter Property="Padding" Value="8,6"/><Setter Property="VerticalContentAlignment" Value="Center"/></Style>
 </Window.Resources>
 <Grid x:Name="Root" Background="#F4F6FA">
  <Grid.ColumnDefinitions><ColumnDefinition x:Name="SidebarWidth" Width="185"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
  <Border x:Name="Sidebar" Background="#142D3B" Padding="22,28"><Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><StackPanel><TextBlock Text="◉  ProxyPanel" Foreground="White" FontSize="20" FontWeight="SemiBold"/><TextBlock Text="让应用各走其路" Foreground="#8EA7B5" Margin="0,8,0,34"/><Border Background="#244653" CornerRadius="8" Padding="12,11"><TextBlock Text="▤  应用分流" Foreground="#B9F2DE" FontWeight="SemiBold"/></Border><TextBlock Text="添加应用，设定路线。&#10;原有 Clash 规则继续保留。" Foreground="#8EA7B5" TextWrapping="Wrap" LineHeight="22" Margin="0,22,0,0"/></StackPanel><StackPanel Grid.Row="2"><TextBlock Text="WINDOWS · VERGE REV" Foreground="#8EA7B5" FontSize="10"/><TextBlock Text="1.1.0  /  通用版" Foreground="#C4D6E0" Margin="0,6,0,0"/></StackPanel></Grid></Border>
  <Grid Grid.Column="1" Margin="26,24,26,18">
   <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
   <Grid Margin="0,0,0,22"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><StackPanel><TextBlock Text="应用分流" FontSize="29" FontWeight="SemiBold"/><TextBlock Text="选择应用 · 设置路线 · 查看真实连接" Foreground="#7B8C9E" Margin="0,6,0,0"/></StackPanel><Button x:Name="Settings" Grid.Column="1" Content="⚙  设置" VerticalAlignment="Center" Margin="0"/></Grid>
   <Border Grid.Row="1" Background="White" BorderBrush="#E1E7EE" BorderThickness="1" CornerRadius="12" Padding="18,15" Margin="0,0,0,18"><StackPanel><DockPanel><TextBlock x:Name="ConnectionState" Text="●  正在连接 Clash…" FontSize="15" FontWeight="SemiBold"/><TextBlock x:Name="Mode" HorizontalAlignment="Right" Foreground="#637B8D"/></DockPanel><TextBlock x:Name="StateHint" Text="正在读取配置" TextWrapping="Wrap" Foreground="#7B8C9E" FontSize="12" Margin="0,9,0,0"/></StackPanel></Border>
   <Grid Grid.Row="2" Margin="0,0,0,12"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><WrapPanel><Button x:Name="Add" Content="＋  添加应用" Background="#167D6B" BorderBrush="#167D6B" Foreground="White"/><Button x:Name="Running" Content="选择已打开的应用"/><Button x:Name="Import" Content="导入"/><Button x:Name="Export" Content="导出"/><Button x:Name="Refresh" Content="刷新"/></WrapPanel><DockPanel Grid.Row="1" Margin="0,14,0,0"><TextBlock x:Name="Count" Text="我的应用" FontWeight="SemiBold" VerticalAlignment="Center"/><StackPanel Orientation="Horizontal" HorizontalAlignment="Right"><TextBlock Text="搜索" VerticalAlignment="Center" Foreground="#7B8C9E" Margin="0,0,10,0"/><TextBox x:Name="Search" Width="180" ToolTip="搜索名称或进程"/></StackPanel></DockPanel></Grid>
   <Grid Grid.Row="3"><ScrollViewer x:Name="Viewport" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"><StackPanel x:Name="AppList"/></ScrollViewer><StackPanel x:Name="Empty" HorizontalAlignment="Center" VerticalAlignment="Center"><TextBlock Text="＋" FontSize="48" Foreground="#A8C9C1" HorizontalAlignment="Center"/><TextBlock x:Name="EmptyTitle" Text="从第一个应用开始" FontSize="20" FontWeight="SemiBold" HorizontalAlignment="Center" Margin="0,12,0,8"/><TextBlock Text="选择程序文件，或从正在运行的应用中添加。&#10;点击“应用设置”才会改变 Clash 配置。" TextAlignment="Center" Foreground="#7B8C9E" LineHeight="24"/></StackPanel></Grid>
   <StackPanel Grid.Row="4" Margin="0,16,0,0"><Border Background="#EAF3F1" CornerRadius="8" Padding="12,9" Margin="0,0,0,12"><TextBlock x:Name="Notice" Text="已有连接可能保留旧路线；刷新不会强制断开下载。" TextWrapping="Wrap" FontSize="12" Foreground="#487369"/></Border><DockPanel><StackPanel Orientation="Horizontal" DockPanel.Dock="Right"><Button x:Name="Undo" Content="撤销本工具规则"/><Button x:Name="Apply" Content="应用设置" Background="#167D6B" BorderBrush="#167D6B" Foreground="White" Margin="0"/></StackPanel><StackPanel><CheckBox x:Name="AutoRefresh" Content="自动刷新" IsChecked="True" Foreground="#637B8D"/><TextBlock x:Name="Updated" Text="尚未刷新" FontSize="11" Foreground="#8798A9" Margin="0,5,0,0"/></StackPanel></DockPanel></StackPanel>
  </Grid>
 </Grid>
</Window>
'@
$window=[Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $markup))
if(Test-Path (Join-Path $PSScriptRoot 'ProxyPanel.ico')){$window.Icon=[Windows.Media.Imaging.BitmapFrame]::Create([uri](Join-Path $PSScriptRoot 'ProxyPanel.ico'))}
$ui=@{};foreach($n in @('Root','Sidebar','SidebarWidth','Settings','ConnectionState','Mode','StateHint','Add','Running','Import','Export','Refresh','Count','Search','AppList','Viewport','Empty','EmptyTitle','Notice','Undo','Apply','AutoRefresh','Updated')){$ui[$n]=$window.FindName($n)}
function Brush($color){return [Windows.Media.BrushConverter]::new().ConvertFromString($color)}
function Text($value,$size=13,$color='#293D52'){$t=New-Object Windows.Controls.TextBlock;$t.Text=$value;$t.FontSize=$size;$t.Foreground=Brush $color;$t.TextTrimming='CharacterEllipsis';return $t}
function Button($label){$b=New-Object Windows.Controls.Button;$b.Content=$label;return $b}
function Show-Error($message){[void][Windows.MessageBox]::Show($window,[string]$message,'未完成','OK','Warning')}
function Get-RouteDescription($route){switch($route){'direct'{'不通过 Clash 的代理节点联网。'}'global'{'使用 Clash 的 GLOBAL 组所选节点；该组若选择 DIRECT，仍会直连。'}'follow'{'交给 Clash 原有规则决定，可能直连，也可能代理。'}}}
function Mark-Draft {
 try{
  $state=Read-ManagedState
  if($state -and !(Test-RulesPending $script:settings $state)){
   foreach($row in $script:rows.Values){$row.status.Text='联网规则未改变';$row.status.Foreground=Brush '#8798A9';$row.status.ToolTip='当前选择与已保存的分流规则一致，无需重新应用。'}
   $ui.StateHint.Text='应用信息已保存，联网规则未改变。';$ui.Notice.Text='当前选择与已保存的规则一致，无需重新应用。';return
  }
 }catch{}
 foreach($row in $script:rows.Values){$row.status.Text='更改尚未应用';$row.status.Foreground=Brush '#A47635';$row.status.ToolTip='退出 Clash → 应用设置 → 重新打开 Clash。'}
 $ui.StateHint.Text='选择已保存，当前网络尚未改变。退出 Clash → 应用设置 → 重新打开 Clash。'
}
function Save-Changes {$script:settings=Save-Settings $script:settings;$script:revision++;$ui.Notice.Text='应用列表已保存。修改分流后，点击“应用设置”使其生效。';$script:lastRefresh=[datetime]::MinValue;Mark-Draft}
function Set-AppRoute($id,$route){$copy=$script:settings|ConvertTo-Json -Depth 10|ConvertFrom-Json;($copy.apps|Where-Object id -eq $id).route=$route;$script:settings=Save-Settings $copy;$script:revision++;$script:lastRefresh=[datetime]::MinValue;$ui.Notice.Text='选择已保存。退出 Clash → 应用设置 → 重新打开 Clash。';$script:rows[$id].combo.ToolTip=Get-RouteDescription $route;Mark-Draft}
function New-Dialog($title,$width,$height){$d=New-Object Windows.Window;$d.Owner=$window;$d.Title=$title;$d.Width=$width;$d.Height=$height;$d.WindowStartupLocation='CenterOwner';$d.ResizeMode='NoResize';$d.Background=Brush '#F4F6FA';$d.FontFamily='Microsoft YaHei UI';$d.FontSize=13;$d.Resources=$window.Resources;return $d}
function Show-AppEditor($existing,$initialPath='',[switch]$AutoTest){
 $d=New-Dialog '应用设置' 620 660;$stack=New-Object Windows.Controls.StackPanel;$stack.Margin='25';$d.Content=$stack
 $heading=Text '选择应用与分流方式' 22;$heading.FontWeight='SemiBold';$heading.Margin='0,0,0,18';[void]$stack.Children.Add($heading);$fields=@{}
 foreach($item in @(@('name','显示名称'),@('path','程序文件 (.exe)'))){$label=Text $item[1] 12 '#637B8D';$label.Margin='0,8,0,6';[void]$stack.Children.Add($label);$box=New-Object Windows.Controls.TextBox;$fields[$item[0]]=$box;[void]$stack.Children.Add($box)}
 $browse=Button '选择文件…';$browse.HorizontalAlignment='Right';$browse.Margin='0,8,0,0';[void]$stack.Children.Add($browse)
 $label=Text '匹配范围' 12 '#637B8D';$label.Margin='0,12,0,6';[void]$stack.Children.Add($label);$match=New-Object Windows.Controls.ComboBox;foreach($v in @('仅这个程序（推荐）','这个程序及安装目录内的辅助程序','所有同名程序（高级）')){[void]$match.Items.Add($v)};$match.SelectedIndex=0;[void]$stack.Children.Add($match)
 $label=Text '联网方式' 12 '#637B8D';$label.Margin='0,12,0,6';[void]$stack.Children.Add($label);$route=New-Object Windows.Controls.ComboBox;foreach($v in @('不使用代理','使用代理','由 Clash 决定')){[void]$route.Items.Add($v)};$route.SelectedIndex=0;[void]$stack.Children.Add($route)
 $enabled=New-Object Windows.Controls.CheckBox;$enabled.Content='启用这个应用的分流规则';$enabled.IsChecked=$true;$enabled.Margin='0,14,0,8';[void]$stack.Children.Add($enabled)
 $hint=Text (Get-RouteDescription 'direct') 11 '#7B8C9E';$hint.TextWrapping='Wrap';[void]$stack.Children.Add($hint)
 $route.Tag=$hint;$route.Add_SelectionChanged({param($sender,$e) $sender.Tag.Text=Get-RouteDescription $script:routeKeys[$sender.SelectedIndex]})
 $save=Button '保存应用';$save.Background=Brush '#167D6B';$save.Foreground=Brush '#FFFFFF';$save.HorizontalAlignment='Right';$save.Margin='0,22,0,0';[void]$stack.Children.Add($save)
 if($existing){$fields.name.Text=$existing.name;$fields.path.Text=$existing.path;$match.SelectedIndex=[array]::IndexOf($script:matchKeys,$existing.match);$route.SelectedIndex=[array]::IndexOf($script:routeKeys,$existing.route);$enabled.IsChecked=$existing.enabled}elseif($initialPath){$fields.path.Text=$initialPath;$fields.name.Text=[IO.Path]::GetFileNameWithoutExtension($initialPath)}
 $browse.Tag=$fields;$browse.Add_Click({param($sender,$e) $f=New-Object Microsoft.Win32.OpenFileDialog;$f.Filter='应用程序 (*.exe)|*.exe';if($f.ShowDialog()){$sender.Tag.path.Text=$f.FileName;if(!$sender.Tag.name.Text){$sender.Tag.name.Text=[IO.Path]::GetFileNameWithoutExtension($f.FileName)}}})
 $save.Tag=@{dialog=$d;fields=$fields;match=$match;route=$route;enabled=$enabled;existing=$existing}
 $save.Add_Click({param($sender,$e) try{
  $ctx=$sender.Tag;$processName=if($ctx.fields.path.Text){[IO.Path]::GetFileName($ctx.fields.path.Text)}elseif($ctx.existing){$ctx.existing.processName}else{''}
  $a=Normalize-App @{id=$(if($ctx.existing){$ctx.existing.id}else{''});name=$ctx.fields.name.Text;path=$ctx.fields.path.Text;processName=$processName;match=$script:matchKeys[$ctx.match.SelectedIndex];route=$script:routeKeys[$ctx.route.SelectedIndex];enabled=[bool]$ctx.enabled.IsChecked}
  $candidate=$script:settings|ConvertTo-Json -Depth 10|ConvertFrom-Json;$candidate.apps=@($candidate.apps|Where-Object id -ne $a.id)+@($a);[void](Normalize-Settings $candidate);$ctx.dialog.Tag=$a;$ctx.dialog.DialogResult=$true
 }catch{[void][Windows.MessageBox]::Show($_.Exception.Message,'应用设置')}})
 if($AutoTest){
  $editTimer=New-Object Windows.Threading.DispatcherTimer;$editTimer.Interval=[timespan]::FromMilliseconds(100);$editTimer.Tag=@{dialog=$d;save=$save;fields=$fields;match=$match;route=$route}
  $editTimer.Add_Tick({param($sender,$e) $sender.Stop();$ctx=$sender.Tag;$ctx.dialog.UpdateLayout();$bottom=$ctx.save.TranslatePoint([Windows.Point]::new(0,$ctx.save.ActualHeight),$ctx.dialog).Y;if($bottom -gt $ctx.dialog.ActualHeight){$ctx.dialog.Tag='LAYOUT_FAILURE';$ctx.dialog.Close();return};$ctx.fields.name.Text='Editor test';$ctx.match.SelectedIndex=2;$ctx.route.SelectedIndex=1;$ctx.save.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))});$editTimer.Start()
 }
 [void]$d.ShowDialog();return $d.Tag
}
function Edit-App($id,$path=''){$existing=$script:settings.apps|Where-Object id -eq $id;$a=Show-AppEditor $existing $path;if($a){if($existing){$script:settings.apps=@($script:settings.apps|ForEach-Object {if($_.id -eq $id){$a}else{$_}})}else{$script:settings.apps=@($script:settings.apps)+@($a)};Save-Changes;Render-Apps}}
function Get-RunningAppChoices {
 $all=@(Get-Process -ErrorAction SilentlyContinue|Where-Object {$_.Path -and $_.Path -like '*.exe' -and $_.ProcessName -ne 'ProxyPanel'})
 return @(foreach($group in @($all|Group-Object Path)){
  $path=$group.Name;$proc=$group.Group[0];$name=$proc.ProcessName
  try{$info=[Diagnostics.FileVersionInfo]::GetVersionInfo($path);if($info.FileDescription){$name=$info.FileDescription}elseif($info.ProductName){$name=$info.ProductName}}catch{}
  if($name -match 'Windows.*Operating System'){$name=$proc.ProcessName}
  if($proc.ProcessName -eq 'SystemSettings'){$name='Windows 设置'}
  $known=$script:settings.apps|Where-Object {Test-AppOwner $_ @{name=$proc.ProcessName;path=$path}}|Select-Object -First 1
  if($known){$name=$known.name}
  $hostProcess=$proc.ProcessName -in @('ApplicationFrameHost','TextInputHost','ShellExperienceHost','SearchHost','StartMenuExperienceHost','RuntimeBroker','explorer')
  [pscustomobject]@{name=$name;path=$path;exe=[IO.Path]::GetFileName($path);hasWindow=(!$hostProcess -and @($group.Group|Where-Object {$_.MainWindowHandle -ne 0 -and $_.MainWindowTitle}).Count -gt 0);count=$group.Count;added=($null -ne $known);search=($name+' '+$proc.ProcessName+' '+$path)}
 })|Sort-Object name,path
}
function Update-PickerList($ctx){
 $needle=$ctx.filter.Text.Trim();$ctx.list.Items.Clear()
 $visible=@($ctx.items|Where-Object {($ctx.background.IsChecked -or $_.hasWindow) -and $_.search.IndexOf($needle,[StringComparison]::OrdinalIgnoreCase) -ge 0})
 foreach($app in $visible){
  $item=New-Object Windows.Controls.ListBoxItem;$item.Tag=$app;$item.Padding='12,10';$item.HorizontalContentAlignment='Stretch';$item.IsEnabled=!$app.added;$item.ToolTip=$app.path;$item.Opacity=if($app.added){0.55}else{1}
  $panel=New-Object Windows.Controls.StackPanel
  $name=Text ($app.name+$(if($app.added){'  ·  已添加'}else{''})) 14;$name.FontWeight='SemiBold';[void]$panel.Children.Add($name)
  $sub=Text ($app.exe+'  ·  '+$app.count+' 个运行进程') 11 '#7B8C9E';$sub.Margin='0,5,0,0';[void]$panel.Children.Add($sub)
  $item.Content=$panel;[void]$ctx.list.Items.Add($item)
 }
 $ctx.summary.Text=if($visible.Count){'共 '+$visible.Count+' 个应用 · 已合并同一程序的多个进程'}else{'没有找到应用。可显示后台程序，或直接选择程序文件。'}
 $ctx.select.IsEnabled=$false
}
function Show-ProcessPicker {
 $d=New-Dialog '选择已打开的应用' 700 610;$g=New-Object Windows.Controls.Grid;$g.Margin='24';$d.Content=$g
 foreach($h in @('Auto','Auto','Auto','*','Auto')){$r=New-Object Windows.Controls.RowDefinition;$r.Height=[Windows.GridLengthConverter]::new().ConvertFromString($h);$g.RowDefinitions.Add($r)}
 $intro=New-Object Windows.Controls.StackPanel
 [void]$intro.Children.Add((Text '选择一个应用' 23))
 $explain=Text '从正在运行的程序中识别应用。添加后，下次打开仍然适用。' 12 '#637B8D';$explain.Margin='0,8,0,16';$explain.TextWrapping='Wrap';[void]$intro.Children.Add($explain);[void]$g.Children.Add($intro)
 $filterPanel=New-Object Windows.Controls.DockPanel;[Windows.Controls.Grid]::SetRow($filterPanel,1)
 $searchLabel=Text '搜索应用' 12 '#637B8D';$searchLabel.VerticalAlignment='Center';$searchLabel.Margin='0,0,12,0';[void]$filterPanel.Children.Add($searchLabel)
 $filter=New-Object Windows.Controls.TextBox;$filter.ToolTip='输入应用名称、程序名或路径';[void]$filterPanel.Children.Add($filter);[void]$g.Children.Add($filterPanel)
 $options=New-Object Windows.Controls.StackPanel;$options.Margin='0,12,0,12';[Windows.Controls.Grid]::SetRow($options,2)
 $background=New-Object Windows.Controls.CheckBox;$background.Content='显示后台程序（高级）';$background.IsChecked=$false;[void]$options.Children.Add($background)
 $summary=Text '' 11 '#7B8C9E';$summary.Margin='0,8,0,0';$summary.TextWrapping='Wrap';[void]$options.Children.Add($summary);[void]$g.Children.Add($options)
 $list=New-Object Windows.Controls.ListBox;$list.BorderBrush=Brush '#DCE3EB';[Windows.Controls.ScrollViewer]::SetHorizontalScrollBarVisibility($list,'Disabled');[Windows.Controls.Grid]::SetRow($list,3);[void]$g.Children.Add($list)
 $footer=New-Object Windows.Controls.DockPanel;$footer.Margin='0,16,0,0';[Windows.Controls.Grid]::SetRow($footer,4);[void]$g.Children.Add($footer)
 $select=Button '选择此应用';$select.IsEnabled=$false;$select.Margin='0';[Windows.Controls.DockPanel]::SetDock($select,'Right');[void]$footer.Children.Add($select)
 $browse=Button '找不到？选择程序文件…';$browse.HorizontalAlignment='Left';[void]$footer.Children.Add($browse)
 $ctx=@{list=$list;filter=$filter;background=$background;summary=$summary;select=$select;dialog=$d;items=@(Get-RunningAppChoices)}
 $filter.Tag=$ctx;$background.Tag=$ctx;$list.Tag=$ctx;$select.Tag=$ctx;$browse.Tag=$ctx
 $filter.Add_TextChanged({param($sender,$e) Update-PickerList $sender.Tag})
 $background.Add_Checked({param($sender,$e) Update-PickerList $sender.Tag});$background.Add_Unchecked({param($sender,$e) Update-PickerList $sender.Tag})
 $list.Add_SelectionChanged({param($sender,$e) $sender.Tag.select.IsEnabled=($null -ne $sender.SelectedItem -and !$sender.SelectedItem.Tag.added)})
 $select.Add_Click({param($sender,$e) if($sender.Tag.list.SelectedItem -and !$sender.Tag.list.SelectedItem.Tag.added){$sender.Tag.dialog.Tag=$sender.Tag.list.SelectedItem.Tag.path;$sender.Tag.dialog.DialogResult=$true}})
 $browse.Add_Click({param($sender,$e) $f=New-Object Microsoft.Win32.OpenFileDialog;$f.Filter='应用程序 (*.exe)|*.exe';if($f.ShowDialog()){$sender.Tag.dialog.Tag=$f.FileName;$sender.Tag.dialog.DialogResult=$true}})
 Update-PickerList $ctx
 if($PickerTest){
  $timer=New-Object Windows.Threading.DispatcherTimer;$timer.Interval=[timespan]::FromMilliseconds(150);$timer.Tag=$ctx
  $timer.Add_Tick({param($sender,$e) $sender.Stop();$c=$sender.Tag
   try{
    if(@($c.list.Items|Where-Object {!$_.Tag.hasWindow}).Count){throw 'Background app leaked into default list'}
    $c.background.IsChecked=$true;if($c.list.Items.Count -ne $c.items.Count){throw 'Background toggle failed'}
    $c.filter.Text='__no_matching_app__';if($c.list.Items.Count){throw 'Picker search failed'}
    $c.filter.Text='';$c.background.IsChecked=$false
    $c.dialog.UpdateLayout();$bmp=New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$c.dialog.ActualWidth,[int]$c.dialog.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bmp.Render($c.dialog);$encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp));$f=[IO.File]::Create((Join-Path $PSScriptRoot 'test-results\picker-layout.png'));try{$encoder.Save($f)}finally{$f.Dispose()}
    $c.dialog.Tag='PICKER_TEST_PASS'
   }catch{$c.dialog.Tag='PICKER_TEST_FAIL: '+$_.Exception.Message}finally{$c.dialog.Close()}
  });$timer.Start()
 }
 [void]$d.ShowDialog()
 if($PickerTest){return $d.Tag}
 if($d.Tag){Edit-App '' $d.Tag}
}
function Show-SettingsDialog {
 $d=New-Dialog '设置与迁移' 680 390;$s=New-Object Windows.Controls.StackPanel;$s.Margin='25';$d.Content=$s
 $t=Text 'Clash Verge Rev 配置目录' 20;$t.Margin='0,0,0,16';[void]$s.Children.Add($t);$box=New-Object Windows.Controls.TextBox;$box.Text=$script:settings.configRoot;[void]$s.Children.Add($box)
 $buttons=New-Object Windows.Controls.StackPanel;$buttons.Orientation='Horizontal';$buttons.Margin='0,12,0,18';[void]$s.Children.Add($buttons)
 $detect=Button '自动检测';$detect.Tag=$box;$detect.Add_Click({param($sender,$e) $found=Find-ClashRoot;if($found){$sender.Tag.Text=$found}else{Show-Error '未找到标准配置目录，请手动选择。'}});[void]$buttons.Children.Add($detect)
 $choose=Button '选择目录…';$choose.Tag=$box;$choose.Add_Click({param($sender,$e) $f=New-Object Windows.Forms.FolderBrowserDialog;$f.Description='选择包含 config.yaml 和 profiles 文件夹的 Clash 配置目录';if($f.ShowDialog() -eq 'OK'){$sender.Tag.Text=$f.SelectedPath};$f.Dispose()});[void]$buttons.Children.Add($choose)
 $info=Text ('应用列表和加密备份保存在：'+(Get-DataDirectory)+"`n`n换电脑：导出应用列表 → 新电脑导入 → 修正失效路径。导出不包含 Clash 订阅或密钥。") 12 '#637B8D';$info.TextWrapping='Wrap';[void]$s.Children.Add($info)
 $save=Button '保存设置';$save.Margin='0,24,0,0';$save.HorizontalAlignment='Right';$save.Tag=@{box=$box;dialog=$d};$save.Add_Click({param($sender,$e) try{
  $root=$sender.Tag.box.Text.Trim();if(!(Test-Path -LiteralPath (Join-Path $root 'profiles\Script.js'))){throw '目录中没有 profiles\Script.js。'};$state=Read-ManagedState;if($state -and $state.root -ine $root){throw '请先撤销旧目录中的规则，再更换目录。'};$script:settings.configRoot=$root;Save-Changes;$sender.Tag.dialog.DialogResult=$true
 }catch{Show-Error $_.Exception.Message}});[void]$s.Children.Add($save);[void]$d.ShowDialog()
}
function Render-Apps {
 $script:rendering=$true;$ui.AppList.Children.Clear();$script:rows=@{}
 foreach($a in $script:settings.apps){
  $card=New-Object Windows.Controls.Border;$card.Background=Brush '#FFFFFF';$card.BorderBrush=Brush '#E1E7EE';$card.BorderThickness='1';$card.CornerRadius='10';$card.Padding='14';$card.Margin='0,0,0,8';$card.MinHeight=94
  $grid=New-Object Windows.Controls.Grid;foreach($w in @('34','*','155','170','54')){$c=New-Object Windows.Controls.ColumnDefinition;$c.Width=[Windows.GridLengthConverter]::new().ConvertFromString($w);$grid.ColumnDefinitions.Add($c)}
  $initial=Text ($a.name.Substring(0,1).ToUpper()) 22 '#167D6B';$initial.VerticalAlignment='Center';[void]$grid.Children.Add($initial)
  $nameArea=New-Object Windows.Controls.StackPanel;$nameArea.VerticalAlignment='Center';$nameArea.Margin='0,0,12,0';[Windows.Controls.Grid]::SetColumn($nameArea,1)
  $name=Text $a.name 15;$name.FontWeight='SemiBold';[void]$nameArea.Children.Add($name)
  $pathLabel=if($a.match -eq 'name'){$a.processName+' · 按进程名'}elseif($a.match -eq 'folder'){(Split-Path -Parent $a.path)+' · 含辅助进程'}else{$a.path};$pathText=Text $pathLabel 11 '#8A99A8';$pathText.Margin='0,7,0,0';$pathText.ToolTip=$pathLabel;[void]$nameArea.Children.Add($pathText);[void]$grid.Children.Add($nameArea)
  $choice=New-Object Windows.Controls.StackPanel;$choice.VerticalAlignment='Center';$choice.Margin='0,0,14,0';[Windows.Controls.Grid]::SetColumn($choice,2)
  $choiceTitle=Text '所选设置' 11 '#7B8C9E';$choiceTitle.Margin='0,0,0,6';[void]$choice.Children.Add($choiceTitle)
  $combo=New-Object Windows.Controls.ComboBox;foreach($v in @('不使用代理','使用代理','由 Clash 决定')){[void]$combo.Items.Add($v)};$combo.SelectedIndex=[array]::IndexOf($script:routeKeys,$a.route);$combo.Tag=$a.id;$combo.IsEnabled=$a.enabled;$combo.ToolTip=Get-RouteDescription $a.route
  $combo.Add_SelectionChanged({param($sender,$e) if(!$script:rendering){try{Set-AppRoute $sender.Tag $script:routeKeys[$sender.SelectedIndex]}catch{Show-Error $_.Exception.Message;Render-Apps}}});[void]$choice.Children.Add($combo)
  $status=Text '正在核实设置' 11 '#8798A9';$status.Margin='0,7,0,0';[void]$choice.Children.Add($status);[void]$grid.Children.Add($choice)
  $stats=New-Object Windows.Controls.StackPanel;$stats.VerticalAlignment='Center';[Windows.Controls.Grid]::SetColumn($stats,3)
  $currentTitle=Text '当前连接' 11 '#7B8C9E';$currentTitle.Margin='0,0,0,7';[void]$stats.Children.Add($currentTitle)
  $counts=Text '正在读取连接' 12;[void]$stats.Children.Add($counts)
  $activity=Text '' 11 '#8798A9';$activity.Margin='0,7,0,0';[void]$stats.Children.Add($activity);[void]$grid.Children.Add($stats)
  $ops=New-Object Windows.Controls.StackPanel;$ops.VerticalAlignment='Center';[Windows.Controls.Grid]::SetColumn($ops,4)
  $edit=Button '编辑';$edit.Padding='6,3';$edit.Margin='0,0,0,5';$edit.Tag=$a.id;$edit.Add_Click({param($sender,$e) try{Edit-App $sender.Tag}catch{Show-Error $_.Exception.Message}});[void]$ops.Children.Add($edit)
  $remove=Button '移除';$remove.Padding='6,3';$remove.Margin='0';$remove.Tag=$a.id;$remove.Add_Click({param($sender,$e) try{$script:settings.apps=@($script:settings.apps|Where-Object id -ne $sender.Tag);Save-Changes;Render-Apps}catch{Show-Error $_.Exception.Message}});[void]$ops.Children.Add($remove);[void]$grid.Children.Add($ops)
  $counts.Tag=$a.id;$counts.Cursor='Hand';$counts.ToolTip='点击查看连接详情';$counts.Add_MouseLeftButtonUp({param($sender,$e) if($script:rows[$sender.Tag].detail){[void][Windows.MessageBox]::Show($window,$script:rows[$sender.Tag].detail,'连接详情')}})
  $card.Child=$grid;[void]$ui.AppList.Children.Add($card);$script:rows[$a.id]=@{card=$card;counts=$counts;status=$status;activity=$activity;combo=$combo;detail='';search=($a.name+' '+$a.processName+' '+$a.path)}
 }
 $script:rendering=$false;$ui.Count.Text='我的应用  /  '+$script:settings.apps.Count;Filter-Apps
}
function Filter-Apps {$visible=0;foreach($row in $script:rows.Values){$show=$row.search.IndexOf($ui.Search.Text,[StringComparison]::OrdinalIgnoreCase) -ge 0;$row.card.Visibility=if($show){'Visible'}else{'Collapsed'};if($show){$visible++}};$ui.Empty.Visibility=if($visible){'Collapsed'}else{'Visible'};$ui.EmptyTitle.Text=if($script:settings.apps.Count){'没有匹配的应用'}else{'从第一个应用开始'}}
function Show-Snapshot($snapshot){
 $ui.ConnectionState.Text=if($snapshot.connected){'●  Clash 已连接'}else{'○  等待 Clash'};$ui.ConnectionState.Foreground=Brush $(if($snapshot.connected){'#167D6B'}else{'#A47635'})
 $modeLabel=switch($snapshot.mode){'rule'{'规则模式'}'global'{'全局模式'}'direct'{'直连模式'}default{'尚未连接'}};$ui.Mode.Text=$modeLabel+'  ·  TUN '+$(if($snapshot.tun -eq 'True'){'开启'}elseif($snapshot.tun -eq 'False'){'关闭'}else{'未知'})
 $ui.StateHint.Text=if($snapshot.warning){$snapshot.warning}elseif($snapshot.pending){'选择已保存，尚未应用。退出 Clash → 应用设置 → 重新打开 Clash。'}elseif($snapshot.rulesLoaded){'所选设置已生效。右侧显示当前连接，已有连接可能保留之前的路线。'}elseif(!$script:settings.apps.Count){'添加应用，选择联网方式，再应用设置。'}elseif(!@($script:settings.apps|Where-Object {$_.enabled -and $_.route -ne 'follow'}).Count){'这些应用交由 Clash 原有规则决定。右侧是观察到的实际连接。'}elseif(!$snapshot.managed){'当前仅观察已有连接；列表中的选择尚未通过本工具应用。已有连接可能来自旧配置。'}else{'设置已保存，等待 Clash 加载。请重新打开 Clash；若仍未生效，请核对配置目录。'}
 foreach($a in $snapshot.apps){
  $row=$script:rows[$a.id];if(!$row){continue}
  $row.counts.Text=if($a.connections){"直连 $($a.direct)   代理 $($a.proxied)"}else{'暂无活动连接'}
  $row.status.Text=$a.status;$row.status.ToolTip=$a.statusHint
  $selectedApp=$script:settings.apps|Where-Object id -eq $a.id
  $row.combo.ToolTip=(Get-RouteDescription $selectedApp.route)+$(if($selectedApp.route -eq 'global' -and $snapshot.globalSelected){"`nGLOBAL 当前选择："+$snapshot.globalSelected}else{''})
  $row.status.Foreground=Brush $(switch($a.statusTone){'success'{'#167D6B'}'warning'{'#A47635'}'pending'{'#A47635'}default{'#8798A9'}})
  $row.activity.Text=if($a.oldProxy){"含 $($a.oldProxy) 条旧代理连接"}elseif($a.blocked -or $a.unknown){"阻断 $($a.blocked) · 未知 $($a.unknown)"}elseif($a.connections){'点击数量查看详情'}elseif($a.running){'应用已打开，等待联网'}else{'应用未打开'}
  $row.detail=$a.detail
 }
 $ui.Updated.Text='更新于 '+$snapshot.time+' · 已识别 '+$snapshot.matched+' 条连接'
}
function Start-Refresh {
 if($script:pending){$script:refreshRequested=$true;return};$script:refreshRequested=$false;$script:readRevision=$script:revision;$ui.Refresh.IsEnabled=$false
 if(!$script:reader){$script:reader=[PowerShell]::Create();[void]$script:reader.AddScript('param($source,$json) . $source -LibraryOnly; Get-ApplicationSnapshot ($json|ConvertFrom-Json)').AddArgument((Join-Path $PSScriptRoot 'ProxyPanel.ps1')).AddArgument(($script:settings|ConvertTo-Json -Depth 10 -Compress))}else{$script:reader.Commands.Clear();$script:reader.Streams.Error.Clear();[void]$script:reader.AddScript('param($json) Get-ApplicationSnapshot ($json|ConvertFrom-Json)').AddArgument(($script:settings|ConvertTo-Json -Depth 10 -Compress))}
 $script:pending=$script:reader.BeginInvoke()
}
function Complete-Refresh {
 if($script:pending -and $script:pending.IsCompleted){try{$result=$script:reader.EndInvoke($script:pending);if($script:reader.HadErrors -or !$result.Count){throw '后台读取失败'};if($script:readRevision -eq $script:revision){Show-Snapshot $result[0]}}catch{$ui.Updated.Text='读取失败：'+$_.Exception.Message}finally{$script:pending=$null;$ui.Refresh.IsEnabled=$true;$script:lastRefresh=if($script:readRevision -eq $script:revision){Get-Date}else{[datetime]::MinValue}}}
}
$pulse=New-Object Windows.Threading.DispatcherTimer;$pulse.Interval=[timespan]::FromMilliseconds(250);$pulse.Add_Tick({Complete-Refresh;if(!$script:pending -and ($script:refreshRequested -or ($ui.AutoRefresh.IsChecked -and ((Get-Date)-$script:lastRefresh).TotalSeconds -ge 3))){Start-Refresh}})
$ui.Add.Add_Click({try{Edit-App ''}catch{Show-Error $_.Exception.Message}});$ui.Running.Add_Click({try{Show-ProcessPicker}catch{Show-Error $_.Exception.Message}});$ui.Settings.Add_Click({Show-SettingsDialog});$ui.Search.Add_TextChanged({Filter-Apps});$ui.Refresh.Add_Click({Start-Refresh})
$ui.Export.Add_Click({try{$d=New-Object Microsoft.Win32.SaveFileDialog;$d.Filter='应用列表 (*.json)|*.json';$d.FileName='ProxyPanel-apps.json';if($d.ShowDialog()){Export-AppList $script:settings $d.FileName;$ui.Notice.Text='已导出应用列表，可在新电脑导入。'}}catch{Show-Error $_.Exception.Message}})
$ui.Import.Add_Click({try{$d=New-Object Microsoft.Win32.OpenFileDialog;$d.Filter='应用列表 (*.json)|*.json';if($d.ShowDialog()){$candidate=Import-AppList $script:settings $d.FileName;if($script:settings.apps.Count -and [Windows.MessageBox]::Show($window,'用导入的应用列表替换当前列表？Clash 规则不会立即改变。','导入应用','YesNo','Question') -ne 'Yes'){return};$script:settings=$candidate;Save-Changes;Render-Apps}}catch{Show-Error $_.Exception.Message}})
$ui.Apply.Add_Click({try{$ui.Apply.IsEnabled=$false;$ui.Notice.Text=Update-ManagedRules $script:settings;$script:revision++;Start-Refresh}catch{Show-Error $_.Exception.Message}finally{$ui.Apply.IsEnabled=$true}})
$ui.Undo.Add_Click({try{$ui.Undo.IsEnabled=$false;$ui.Notice.Text=Update-ManagedRules $script:settings -Remove;$script:revision++;Start-Refresh}catch{Show-Error $_.Exception.Message}finally{$ui.Undo.IsEnabled=$true}})
$window.Add_SizeChanged({$ui.Sidebar.Visibility=if($window.ActualWidth -lt 1040){'Collapsed'}else{'Visible'};$ui.SidebarWidth.Width=if($window.ActualWidth -lt 1040){0}else{185}})
$window.Add_Closed({$pulse.Stop();if($script:reader){$script:reader.Stop();$script:reader.Dispose();$script:reader=$null}})
Render-Apps
if($LayoutTest){
 Show-Snapshot (Get-ApplicationSnapshot $script:settings);$window.Show();$results=@()
 foreach($size in @(@(1180,800),@(960,700),@(820,600))){$window.Width=$size[0];$window.Height=$size[1];$window.UpdateLayout();$bottom=$ui.Apply.TranslatePoint([Windows.Point]::new(0,$ui.Apply.ActualHeight),$ui.Root).Y;if($bottom -gt $ui.Root.ActualHeight -or $ui.Viewport.ActualHeight -lt 80){throw 'Layout does not fit'};$bmp=New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$ui.Root.ActualWidth,[int]$ui.Root.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bmp.Render($ui.Root);$encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp));$f=[IO.File]::Create((Join-Path $PSScriptRoot ("layout-$($size[0])x$($size[1]).png")));try{$encoder.Save($f)}finally{$f.Dispose()};$results+=@{width=$size[0];height=$size[1];footerVisible=$true;apps=$script:settings.apps.Count}}
 $window.Close();$results|ConvertTo-Json
}elseif($PickerTest){
 $window.Show();$result=Show-ProcessPicker;$window.Close();if($result -ne 'PICKER_TEST_PASS'){throw $result};Write-Output 'PASS: app grouping, background toggle and picker search.'
}elseif($InteractionTest){
 if(!$env:PROXYPANEL_DATA_DIR -or !$env:PROXYPANEL_DATA_DIR.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){throw 'UI tests require an isolated data directory under TEMP.'}
 $window.Show()
 $edited=Show-AppEditor $null (Join-Path $env:WINDIR 'System32\notepad.exe') -AutoTest
 if($edited.name -ne 'Editor test' -or $edited.match -ne 'name' -or $edited.route -ne 'global'){throw 'Editor save or layout failed'}
 $script:settings.apps=@($script:settings.apps)+@($edited);Save-Changes;Render-Apps
 $script:rows[$edited.id].combo.SelectedIndex=0
 if(($script:settings.apps|Where-Object id -eq $edited.id).route -ne 'direct'){throw 'Route selection did not persist'}
 $ui.AutoRefresh.IsChecked=$false;Start-Refresh;$script:revision++;$deadline=(Get-Date).AddSeconds(25)
 while($script:pending -and (Get-Date) -lt $deadline){Start-Sleep -Milliseconds 100;Complete-Refresh};if($ui.Updated.Text -ne '尚未刷新'){throw 'Stale snapshot was rendered'}
 Start-Refresh;while($script:pending -and (Get-Date) -lt $deadline){Start-Sleep -Milliseconds 100;Complete-Refresh};if($ui.Updated.Text -notlike '更新于*'){throw 'Persistent reader failed'}
 $ui.Search.Text='__no_such_app__';if($ui.Empty.Visibility -ne 'Visible'){throw 'Search filter failed'};$ui.Search.Text='';$window.Close();Write-Output 'PASS: editor save, dropdown persistence, stale read suppression, persistent refresh, and search.'
}else{$window.Add_ContentRendered({Start-Refresh;$pulse.Start()});[void]$window.ShowDialog()}
