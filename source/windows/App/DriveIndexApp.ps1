# DriveIndexApp.ps1 -- the AVM Drive Index window (Windows).
#
# Launched by "AVM Drive Index.cmd". Reads the index kept by DriveIndexer.ps1
# and presents it: drives in a sidebar (green = connected, grey = not), each
# drive's folders and files, who used it last, the connection history, and a
# search across everything ever indexed.
#
# NOTE: keep this file ASCII-only (see Common.ps1 for why).

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName Microsoft.VisualBasic

. (Join-Path $PSScriptRoot 'Common.ps1')

$ErrorActionPreference = 'Continue'
$script:TaskName = 'AVM Drive Indexer'
$script:ToolsRoot = Split-Path $PSScriptRoot -Parent

# ---------------------------------------------------------------- window

$xamlText = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="AVM Drive Index" Height="620" Width="960" MinHeight="480" MinWidth="820"
    Background="#131614" WindowStartupLocation="CenterScreen"
    TextOptions.TextFormattingMode="Display">
  <Window.Resources>
    <DrawingBrush x:Key="Scanlines" TileMode="Tile" Stretch="None"
                  Viewport="0,0,4,4" ViewportUnits="Absolute">
      <DrawingBrush.Drawing>
        <GeometryDrawing Brush="#0E000000">
          <GeometryDrawing.Geometry>
            <RectangleGeometry Rect="0,0,4,1"/>
          </GeometryDrawing.Geometry>
        </GeometryDrawing>
      </DrawingBrush.Drawing>
    </DrawingBrush>

    <Style x:Key="PipButton" TargetType="Button">
      <Setter Property="Foreground" Value="#4DE680"/>
      <Setter Property="Background" Value="#144DE680"/>
      <Setter Property="BorderBrush" Value="#734DE680"/>
      <Setter Property="FontFamily" Value="Consolas"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Padding" Value="10,5"/>
      <Setter Property="SnapsToDevicePixels" Value="True"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Shell" CornerRadius="5" BorderThickness="1"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}">
              <ContentPresenter Margin="{TemplateBinding Padding}"
                                HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Shell" Property="Background" Value="#264DE680"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Shell" Property="Background" Value="#4DE680"/>
                <Setter Property="Foreground" Value="#0A0F0B"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.45"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="TabButton" TargetType="Button" BasedOn="{StaticResource PipButton}">
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Foreground" Value="#8CFFFFFF"/>
      <Setter Property="Background" Value="#00000000"/>
      <Setter Property="BorderBrush" Value="#24FFFFFF"/>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid Name="RootContent">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <!-- header -->
      <Border Grid.Row="0" Background="#1C201D" BorderBrush="#24FFFFFF" BorderThickness="0,0,0,1">
        <Grid Margin="14,9">
          <TextBlock Text="AVM DRIVE INDEX" FontFamily="Consolas" FontSize="13"
                     FontWeight="Bold" Foreground="#4DE680" VerticalAlignment="Center"/>
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
            <Border Name="SearchShell" CornerRadius="5" BorderThickness="1"
                    BorderBrush="#24FFFFFF" Background="#131614"
                    Padding="8,4" Margin="0,0,10,0">
              <Grid>
                <TextBlock Name="SearchPlaceholder" Text="Search index..." FontFamily="Consolas"
                           FontSize="12" Foreground="#8CFFFFFF" IsHitTestVisible="False"
                           VerticalAlignment="Center"/>
                <TextBox Name="SearchInput" Width="210" Background="Transparent"
                         BorderThickness="0" Foreground="#E0FFFFFF" CaretBrush="#4DE680"
                         FontFamily="Consolas" FontSize="12" VerticalAlignment="Center"
                         SelectionBrush="#4DE680"/>
              </Grid>
            </Border>
            <Button Name="NewFolderButton" Content="+ Folder" Style="{StaticResource PipButton}"
                    Margin="0,0,8,0"/>
            <Button Name="RescanButton" Content="Rescan" Style="{StaticResource PipButton}"/>
          </StackPanel>
        </Grid>
      </Border>

      <!-- body -->
      <Grid Grid.Row="1">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="290"/>
          <ColumnDefinition Width="1"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <ScrollViewer Grid.Column="0" VerticalScrollBarVisibility="Auto"
                      HorizontalScrollBarVisibility="Disabled">
          <StackPanel Name="SidebarPanel" Margin="0,6,0,10"/>
        </ScrollViewer>
        <Rectangle Grid.Column="1" Fill="#24FFFFFF"/>

        <Grid Grid.Column="2">
          <!-- no selection -->
          <StackPanel Name="PlaceholderPane" VerticalAlignment="Center" HorizontalAlignment="Center"
                      MaxWidth="400">
            <TextBlock Name="PlaceholderTitle" Text="No drive selected" FontFamily="Consolas"
                       FontSize="14" FontWeight="SemiBold" Foreground="#E0FFFFFF"
                       TextAlignment="Center" Margin="0,0,0,8"/>
            <TextBlock Name="PlaceholderBody" FontSize="12" Foreground="#8CFFFFFF"
                       TextAlignment="Center" TextWrapping="Wrap"
                       Text="Every external drive ever connected to this PC is listed on the left, even ones that aren't plugged in right now."/>
          </StackPanel>

          <!-- drive detail -->
          <Grid Name="DetailPane" Visibility="Collapsed">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
            </Grid.RowDefinitions>

            <Grid Grid.Row="0" Margin="16,16,16,0">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <StackPanel Grid.Column="0" Orientation="Horizontal">
                <Border Name="DetailIndicator" Width="30" Height="21" CornerRadius="3"
                        Background="#4DE680" VerticalAlignment="Center" Margin="0,0,12,0"/>
                <StackPanel VerticalAlignment="Center">
                  <TextBlock Name="DetailName" FontFamily="Consolas" FontSize="20"
                             FontWeight="Bold" Foreground="#E0FFFFFF"/>
                  <StackPanel Orientation="Horizontal" Margin="0,4,0,0">
                    <Ellipse Name="DetailDot" Width="7" Height="7" Fill="#4DE680"
                             VerticalAlignment="Center" Margin="0,0,6,0"/>
                    <TextBlock Name="DetailStatus" FontSize="12" FontWeight="SemiBold"
                               Foreground="#4DE680" VerticalAlignment="Center"/>
                  </StackPanel>
                </StackPanel>
              </StackPanel>
              <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Top">
                <Button Name="OpenDriveButton" Content="Open Drive"
                        Style="{StaticResource PipButton}" Margin="0,0,8,0"/>
                <Button Name="CopyFilesButton" Content="Copy Files..."
                        Style="{StaticResource PipButton}" Margin="0,0,8,0"
                        ToolTip="Copy chosen files from here onto another drive"/>
                <Button Name="NewProjectButton" Content="New Project"
                        Style="{StaticResource PipButton}" Margin="0,0,8,0"
                        ToolTip="Create the standard project folder structure on this drive"/>
                <Button Name="EjectButton" Content="Eject" Style="{StaticResource PipButton}"/>
              </StackPanel>
            </Grid>

            <StackPanel Grid.Row="1" Margin="16,10,16,0">
              <TextBlock Name="StatSize" FontFamily="Consolas" FontSize="12" Foreground="#E0FFFFFF"/>
              <TextBlock Name="StatFree" FontFamily="Consolas" FontSize="12" Foreground="#E0FFFFFF"/>
              <TextBlock Name="StatFormat" FontFamily="Consolas" FontSize="12" Foreground="#E0FFFFFF"/>
              <TextBlock Name="StatLetter" FontFamily="Consolas" FontSize="12" Foreground="#E0FFFFFF"/>
              <TextBlock Name="StatLastConnected" FontFamily="Consolas" FontSize="12" Foreground="#E0FFFFFF"/>
              <TextBlock Name="StatLastUser" FontFamily="Consolas" FontSize="12" Foreground="#E0FFFFFF"/>
              <StackPanel Name="UsagePanel" Orientation="Horizontal" Margin="0,7,0,0"
                          Visibility="Collapsed">
                <Border Width="300" Height="7" CornerRadius="3" Background="#24FFFFFF">
                  <Grid Name="UsageBar">
                    <Grid.ColumnDefinitions>
                      <ColumnDefinition Width="0*"/>
                      <ColumnDefinition Width="100*"/>
                    </Grid.ColumnDefinitions>
                    <Border Name="UsageFill" Grid.Column="0" Background="#4DE680" CornerRadius="3"/>
                  </Grid>
                </Border>
                <TextBlock Name="UsageLabel" FontFamily="Consolas" FontSize="11"
                           Foreground="#8CFFFFFF" Margin="10,0,0,0" VerticalAlignment="Center"/>
              </StackPanel>
            </StackPanel>

            <Rectangle Grid.Row="2" Fill="#24FFFFFF" Height="1" Margin="0,14,0,0"/>

            <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="16,9,16,9">
              <Button Name="TabContents" Content="Contents" Style="{StaticResource TabButton}"
                      Margin="0,0,8,0"/>
              <Button Name="TabHistory" Content="History" Style="{StaticResource TabButton}"/>
            </StackPanel>

            <Grid Grid.Row="4">
              <Grid.RowDefinitions>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
              </Grid.RowDefinitions>
              <TreeView Name="ContentsTree" Grid.Row="0" Background="Transparent"
                        BorderThickness="0" Foreground="#E0FFFFFF" Margin="8,0,0,0">
                <TreeView.Resources>
                  <SolidColorBrush x:Key="{x:Static SystemColors.HighlightBrushKey}" Color="#334DE680"/>
                  <SolidColorBrush x:Key="{x:Static SystemColors.HighlightTextBrushKey}" Color="#FFFFFFFF"/>
                  <SolidColorBrush x:Key="{x:Static SystemColors.InactiveSelectionHighlightBrushKey}" Color="#1F4DE680"/>
                  <SolidColorBrush x:Key="{x:Static SystemColors.InactiveSelectionHighlightTextBrushKey}" Color="#FFFFFFFF"/>
                </TreeView.Resources>
              </TreeView>
              <ScrollViewer Name="HistoryScroll" Grid.Row="0" Visibility="Collapsed"
                            VerticalScrollBarVisibility="Auto">
                <StackPanel Name="HistoryPanel" Margin="16,0,16,8"/>
              </ScrollViewer>
              <TextBlock Name="TabPlaceholder" Grid.Row="0" Visibility="Collapsed"
                         HorizontalAlignment="Center" VerticalAlignment="Center"
                         TextAlignment="Center" TextWrapping="Wrap" MaxWidth="380"
                         FontSize="12" Foreground="#8CFFFFFF"/>
              <Border Grid.Row="1" Background="#1C201D" BorderBrush="#24FFFFFF"
                      BorderThickness="0,1,0,0" Padding="14,5">
                <TextBlock Name="ContentsNote" FontSize="11" Foreground="#8CFFFFFF"
                           TextWrapping="Wrap"/>
              </Border>
            </Grid>
          </Grid>

          <!-- search results -->
          <Grid Name="SearchPane" Visibility="Collapsed">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <TextBlock Name="SearchSummary" Grid.Row="0" Margin="16,10" FontFamily="Consolas"
                       FontSize="12" Foreground="#8CFFFFFF"/>
            <Rectangle Grid.Row="1" Fill="#24FFFFFF" Height="1"/>
            <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto">
              <StackPanel Name="SearchResultsPanel" Margin="8,6,8,10"/>
            </ScrollViewer>
          </Grid>
        </Grid>
      </Grid>

      <!-- watcher banner -->
      <Border Name="WatcherBanner" Grid.Row="2" Background="#1C201D" BorderBrush="#24FFFFFF"
              BorderThickness="0,1,0,0" Padding="12,10" Visibility="Collapsed">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <TextBlock Grid.Column="0" Text="!" FontFamily="Consolas" FontSize="16" FontWeight="Bold"
                     Foreground="#F5C542" VerticalAlignment="Center" Margin="4,0,12,0"/>
          <StackPanel Grid.Column="1" VerticalAlignment="Center">
            <TextBlock Text="Automatic indexing is turned off" FontSize="12" FontWeight="SemiBold"
                       Foreground="#E0FFFFFF"/>
            <TextBlock Text="Drives connected while this app is closed won't be recorded."
                       FontSize="11" Foreground="#8CFFFFFF"/>
          </StackPanel>
          <Button Name="TurnOnButton" Grid.Column="2" Content="Turn On"
                  Style="{StaticResource PipButton}" VerticalAlignment="Center"/>
        </Grid>
      </Border>
    </Grid>

    <!-- faint CRT texture over everything -->
    <Rectangle Fill="{StaticResource Scanlines}" IsHitTestVisible="False"/>
  </Grid>
</Window>
'@

try {
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xamlText)
    $window = [Windows.Markup.XamlReader]::Load($reader)
} catch {
    [System.Windows.MessageBox]::Show(
        "The window layout could not be loaded.`r`n`r`n$($_.Exception.Message)",
        'AVM Drive Index') | Out-Null
    exit 1
}

foreach ($name in @('SidebarPanel', 'SearchInput', 'SearchPlaceholder', 'SearchShell',
    'NewFolderButton', 'RescanButton', 'PlaceholderPane', 'PlaceholderTitle', 'PlaceholderBody',
    'DetailPane', 'DetailIndicator', 'DetailName', 'DetailDot', 'DetailStatus',
    'OpenDriveButton', 'CopyFilesButton', 'NewProjectButton', 'EjectButton', 'StatSize', 'StatFree',
    'StatFormat', 'StatLetter',
    'StatLastConnected', 'StatLastUser', 'UsagePanel', 'UsageBar', 'UsageFill', 'UsageLabel',
    'TabContents', 'TabHistory', 'ContentsTree',
    'HistoryScroll', 'HistoryPanel', 'TabPlaceholder', 'ContentsNote', 'SearchPane',
    'SearchSummary', 'SearchResultsPanel', 'WatcherBanner', 'TurnOnButton')) {
    Set-Variable -Name $name -Scope Script -Value $window.FindName($name)
}

$iconPath = Join-Path $PSScriptRoot 'AppIcon.ico'
if (Test-Path -LiteralPath $iconPath) {
    try { $window.Icon = New-Object System.Windows.Media.Imaging.BitmapImage ([uri]$iconPath) } catch { }
}

# ---------------------------------------------------------------- theme helpers

function New-Brush([string]$Hex) {
    $color = [System.Windows.Media.Color][System.Windows.Media.ColorConverter]::ConvertFromString($Hex)
    return (New-Object System.Windows.Media.SolidColorBrush $color)
}

$script:BrushGreen     = New-Brush '#4DE680'
$script:BrushAmber     = New-Brush '#FFBF40'   # nearly-full drives
$script:BrushRaised    = New-Brush '#1C201D'
$script:BrushGreenSoft = New-Brush '#D94DE680'
$script:BrushText      = New-Brush '#E0FFFFFF'
$script:BrushDim       = New-Brush '#8CFFFFFF'
$script:BrushFileText  = New-Brush '#B8FFFFFF'
$script:BrushFaint     = New-Brush '#24FFFFFF'
$script:BrushGrey      = New-Brush '#59FFFFFF'
$script:BrushSelected  = New-Brush '#294DE680'
$script:BrushSelBorder = New-Brush '#594DE680'
$script:BrushHover     = New-Brush '#14FFFFFF'
$script:BrushClear     = [System.Windows.Media.Brushes]::Transparent

function New-Text([string]$Content, [double]$Size, $Brush, [string]$Weight = 'Normal', [string]$Family = 'Segoe UI') {
    $block = New-Object System.Windows.Controls.TextBlock
    $block.Text = $Content
    $block.FontSize = $Size
    $block.Foreground = $Brush
    $block.FontFamily = New-Object System.Windows.Media.FontFamily $Family
    $block.FontWeight = switch ($Weight) {
        'Bold'     { [System.Windows.FontWeights]::Bold }
        'SemiBold' { [System.Windows.FontWeights]::SemiBold }
        'Medium'   { [System.Windows.FontWeights]::Medium }
        default    { [System.Windows.FontWeights]::Normal }
    }
    $block.VerticalAlignment = 'Center'
    $block.TextTrimming = 'CharacterEllipsis'
    return $block
}

# ---------------------------------------------------------------- state

$script:Records       = @()
$script:Cards         = @()
$script:CopyState     = $null
$script:CopyTimer     = $null
$script:CopySelection = $null
$script:CopyBoxes     = $null
$script:CopyRoots     = @()
$script:CopyRecord    = $null
$script:CopyDestination = $null
$script:CopyDestText  = $null
$script:CopyCountText = $null
$script:CopyPickerWindow = $null
$script:Org           = Get-Organization
$script:SelectedName  = $null
$script:ActiveTab     = 'contents'
$script:TreeCache     = @{}
$script:IndexStamp    = ''
$script:VolumeFingerprint = ''
$script:LastTreeKey   = $null
$script:EjectPending  = $null
$script:ScanProcess   = $null

function Get-RecordByName([string]$Name) {
    foreach ($record in $script:Records) {
        if ($record.IndexFolderName -eq $Name) { return $record }
    }
    foreach ($card in $script:Cards) {
        if ($card.IndexFolderName -eq $Name) { return $card }
    }
    return $null
}

function Get-SelectedRecord {
    if (-not $script:SelectedName) { return $null }
    return (Get-RecordByName $script:SelectedName)
}

function Get-IndexStamp {
    # Fingerprint of what the index *contains*, not when it was written. The
    # scanner rewrites these files on every pass even when nothing changed, so
    # keying on timestamps would reload the window (and collapse the folder tree
    # the user is browsing) every time the watcher runs.
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($dir in (Get-ChildItem -LiteralPath (Get-DrivesDir) -Directory -ErrorAction SilentlyContinue |
                      Sort-Object Name)) {
        foreach ($name in @($script:InfoName, $script:FileListName)) {
            $item = Get-Item -LiteralPath (Join-Path $dir.FullName $name) -ErrorAction SilentlyContinue
            $length = 0
            if ($item) { $length = $item.Length }
            $parts.Add("$($dir.Name)/$name=$length") | Out-Null
        }
    }
    return ($parts.ToArray() -join '|')
}

# ---------------------------------------------------------------- data loading

function Update-Records {
    $records = @(Get-AllDriveRecords)

    # Ask the system what is actually mounted right now, rather than trusting
    # anything cached -- this is what keeps "Connected" honest.
    $volumes = @()
    try { $volumes = @(Get-ExternalVolume) } catch { }

    foreach ($record in $records) {
        $match = $null
        foreach ($volume in $volumes) {
            if ($record.Serial -and $volume.Serial -and $record.Serial -ne 'none' -and
                $record.Serial -eq $volume.Serial) { $match = $volume; break }
        }
        if (-not $match) {
            foreach ($volume in $volumes) {
                if ($volume.Name -eq $record.Name) { $match = $volume; break }
            }
        }
        if ($match) {
            $record.IsConnected = $true
            $record.VolumePath  = $match.RootPath
            $record.Letter      = $match.Letter
            $record.IsRemovableMedia = $match.IsRemovableMedia
        }
    }

    $script:Records = @($records |
        Sort-Object `
            @{ Expression = { -not $_.IsConnected } }, `
            @{ Expression = { if ($_.LastConnected) { $_.LastConnected } else { [datetime]::MinValue } }
               Descending = $true })

    $script:Org = Get-Organization
    if (Sync-Organization $script:Org $script:Records) {
        Save-Organization $script:Org
    }

    if ($script:SelectedName -and -not (Get-RecordByName $script:SelectedName)) {
        $script:SelectedName = $null
    }
    if (-not $script:SelectedName -and $script:Records.Count -gt 0) {
        $script:SelectedName = $script:Records[0].IndexFolderName
    }
    # Memory cards are never catalogued, so they are found live and shown only
    # while they are plugged in.
    $cards = New-Object System.Collections.ArrayList
    try {
        foreach ($card in (Get-CardVolume)) {
            [void]$cards.Add([pscustomobject]@{
                IndexFolderName     = $card.Name
                Name                = $card.Name
                Letter              = $card.Letter
                Size                = Format-DriveSize $card.SizeBytes
                FreeSpace           = Format-FreeSpace $card.FreeBytes $card.SizeBytes
                UsedPercent         = Get-UsedPercent $card.FreeBytes $card.SizeBytes
                Format              = $card.FileSystem
                Serial              = ''
                LastConnectedString = ''
                LastConnected       = $null
                LastUser            = ''
                ContentsNote        = ''
                History             = @()
                FolderPath          = $card.RootPath
                VolumePath          = $card.RootPath
                IsConnected         = $true
                IsCard              = $true
                IsRemovableMedia    = $true
            })
        }
    } catch { }
    $script:Cards = $cards.ToArray()

    $script:IndexStamp = Get-IndexStamp
    $script:VolumeFingerprint = Get-VolumeFingerprint
}

# ---------------------------------------------------------------- sidebar

function New-SectionHeader([string]$Title) {
    $grid = New-Object System.Windows.Controls.Grid
    $grid.Margin = '10,8,10,4'
    $col1 = New-Object System.Windows.Controls.ColumnDefinition
    $col1.Width = 'Auto'
    $col2 = New-Object System.Windows.Controls.ColumnDefinition
    $grid.ColumnDefinitions.Add($col1)
    $grid.ColumnDefinitions.Add($col2)

    $label = New-Text $Title 11 $script:BrushDim 'SemiBold' 'Consolas'
    $label.Margin = '0,0,6,0'
    [System.Windows.Controls.Grid]::SetColumn($label, 0)
    $grid.Children.Add($label) | Out-Null

    $rule = New-Object System.Windows.Shapes.Rectangle
    $rule.Height = 1
    $rule.Fill = $script:BrushFaint
    $rule.VerticalAlignment = 'Center'
    [System.Windows.Controls.Grid]::SetColumn($rule, 1)
    $grid.Children.Add($rule) | Out-Null
    return $grid
}

function New-DriveRow($Record) {
    $selected = ($Record.IndexFolderName -eq $script:SelectedName)

    $border = New-Object System.Windows.Controls.Border
    $border.CornerRadius = 6
    $border.Padding = '8,5'
    $border.Margin = '8,2'
    $border.Cursor = 'Hand'
    $border.Tag = $Record.IndexFolderName
    if ($selected) {
        $border.Background = $script:BrushSelected
        $border.BorderBrush = $script:BrushSelBorder
        $border.BorderThickness = 1
    } else {
        $border.Background = $script:BrushClear
        $border.BorderThickness = 1
        $border.BorderBrush = $script:BrushClear
    }

    $grid = New-Object System.Windows.Controls.Grid
    foreach ($width in @('Auto', '*', 'Auto')) {
        $col = New-Object System.Windows.Controls.ColumnDefinition
        $col.Width = $width
        $grid.ColumnDefinitions.Add($col)
    }

    # Small drive "LED": green when connected, grey when not.
    $led = New-Object System.Windows.Controls.Border
    $led.Width = 15
    $led.Height = 11
    $led.CornerRadius = 2
    $led.VerticalAlignment = 'Center'
    $led.Margin = '0,0,9,0'
    if ($Record.IsConnected) {
        $led.Background = $script:BrushGreen
        $glow = New-Object System.Windows.Media.Effects.DropShadowEffect
        $glow.Color = [System.Windows.Media.Color][System.Windows.Media.ColorConverter]::ConvertFromString('#4DE680')
        $glow.BlurRadius = 8
        $glow.ShadowDepth = 0
        $glow.Opacity = 0.75
        $led.Effect = $glow
    } else {
        $led.Background = $script:BrushGrey
    }
    [System.Windows.Controls.Grid]::SetColumn($led, 0)
    $grid.Children.Add($led) | Out-Null

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.VerticalAlignment = 'Center'
    $name = New-Text $Record.IndexFolderName 12.5 $script:BrushText 'Medium'
    $stack.Children.Add($name) | Out-Null

    $parts = New-Object System.Collections.Generic.List[string]
    if ($Record.IsCard) {
        # A card carries no history, so say what it is and how big it is.
        $parts.Add('Card') | Out-Null
        if ($Record.Size) { $parts.Add($Record.Size) | Out-Null }
    } else {
        if ($Record.IsConnected) {
            $parts.Add('Connected') | Out-Null
        } elseif ($Record.LastConnected) {
            $parts.Add((Get-RelativeTimeText $Record.LastConnected)) | Out-Null
        }
        if ($Record.LastUser) { $parts.Add($Record.LastUser) | Out-Null }
    }
    $subtitleBrush = $script:BrushDim
    if ($Record.IsConnected) { $subtitleBrush = $script:BrushGreenSoft }
    $subtitle = New-Text ($parts -join '  |  ') 10.5 $subtitleBrush
    $stack.Children.Add($subtitle) | Out-Null
    [System.Windows.Controls.Grid]::SetColumn($stack, 1)
    $grid.Children.Add($stack) | Out-Null

    if ($Record.IsConnected) {
        $dot = New-Object System.Windows.Shapes.Ellipse
        $dot.Width = 7
        $dot.Height = 7
        $dot.Fill = $script:BrushGreen
        $dot.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($dot, 2)
        $grid.Children.Add($dot) | Out-Null
    }

    $border.Child = $grid
    $border.ContextMenu = New-DriveContextMenu $Record
    $border.add_MouseLeftButtonUp({ Select-Drive $this.Tag })
    $border.add_MouseEnter({
        if ($this.Tag -ne $script:SelectedName) { $this.Background = $script:BrushHover }
    })
    $border.add_MouseLeave({
        if ($this.Tag -ne $script:SelectedName) { $this.Background = $script:BrushClear }
    })
    return $border
}

function New-MenuItem([string]$Header, $Tag, [scriptblock]$OnClick) {
    $item = New-Object System.Windows.Controls.MenuItem
    $item.Header = $Header
    $item.Tag = $Tag
    if ($OnClick) { $item.add_Click($OnClick) }
    return $item
}

function New-DriveContextMenu($Record) {
    $menu = New-Object System.Windows.Controls.ContextMenu
    $driveName = $Record.IndexFolderName

    if ($Record.IsCard) {
        # A card is not catalogued, so folders and removal do not apply to it.
        $menu.Items.Add((New-MenuItem 'Copy Files...' $driveName { Copy-FilesFromVolume $this.Tag })) | Out-Null
        $menu.Items.Add((New-MenuItem 'Eject' $driveName { Invoke-Eject $this.Tag })) | Out-Null
        return $menu
    }

    if ($Record.IsConnected) {
        $menu.Items.Add((New-MenuItem 'Copy Files...' $driveName { Copy-FilesFromVolume $this.Tag })) | Out-Null
        $menu.Items.Add((New-MenuItem 'Eject' $driveName { Invoke-Eject $this.Tag })) | Out-Null
        $menu.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null
    }

    $moveMenu = New-Object System.Windows.Controls.MenuItem
    $moveMenu.Header = 'Move to Folder'
    $moveMenu.Items.Add((New-MenuItem '(No Folder)' `
        ([pscustomobject]@{ Drive = $driveName; GroupId = $null }) `
        { Move-DriveToGroup $this.Tag.Drive $this.Tag.GroupId })) | Out-Null
    if ($script:Org.groups.Count -gt 0) {
        $moveMenu.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null
        foreach ($group in $script:Org.groups) {
            $moveMenu.Items.Add((New-MenuItem $group.name `
                ([pscustomobject]@{ Drive = $driveName; GroupId = $group.id }) `
                { Move-DriveToGroup $this.Tag.Drive $this.Tag.GroupId })) | Out-Null
        }
    }
    $moveMenu.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null
    $moveMenu.Items.Add((New-MenuItem 'New Folder...' $driveName { New-DriveFolder $this.Tag })) | Out-Null
    $menu.Items.Add($moveMenu) | Out-Null

    $menu.Items.Add((New-MenuItem 'Move Up' $driveName { Move-DriveOrder $this.Tag -1 })) | Out-Null
    $menu.Items.Add((New-MenuItem 'Move Down' $driveName { Move-DriveOrder $this.Tag 1 })) | Out-Null
    $menu.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null
    $menu.Items.Add((New-MenuItem 'Remove from Index...' $driveName { Remove-DriveIndex $this.Tag })) | Out-Null
    return $menu
}

function New-GroupHeader($Group) {
    $header = New-SectionHeader $Group.name
    $menu = New-Object System.Windows.Controls.ContextMenu
    $menu.Items.Add((New-MenuItem 'Rename Folder...' $Group.id { Rename-DriveGroup $this.Tag })) | Out-Null
    $menu.Items.Add((New-MenuItem 'Move Folder Up' $Group.id { Move-GroupOrder $this.Tag -1 })) | Out-Null
    $menu.Items.Add((New-MenuItem 'Move Folder Down' $Group.id { Move-GroupOrder $this.Tag 1 })) | Out-Null
    $menu.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null
    $menu.Items.Add((New-MenuItem 'Delete Folder (Keep Drives)' $Group.id { Remove-DriveGroup $this.Tag })) | Out-Null
    $header.ContextMenu = $menu
    return $header
}

function Build-Sidebar {
    $script:SidebarPanel.Children.Clear()
    $script:SidebarPanel.Children.Add((New-SectionHeader 'Drives')) | Out-Null

    if ($script:Records.Count -eq 0) {
        $empty = New-Text 'No drives indexed yet.' 11.5 $script:BrushDim
        $empty.TextWrapping = 'Wrap'
        $empty.TextTrimming = 'None'
        $empty.Margin = '14,4,14,4'
        $script:SidebarPanel.Children.Add($empty) | Out-Null
        $hint = New-Text 'Connect an external drive and it will appear here.' 11 $script:BrushDim
        $hint.TextWrapping = 'Wrap'
        $hint.TextTrimming = 'None'
        $hint.Margin = '14,0,14,4'
        $script:SidebarPanel.Children.Add($hint) | Out-Null
        return
    }

    foreach ($name in $script:Org.ungrouped) {
        $record = Get-RecordByName $name
        if ($record) { $script:SidebarPanel.Children.Add((New-DriveRow $record)) | Out-Null }
    }

    if ($script:Cards.Count -gt 0) {
        $script:SidebarPanel.Children.Add((New-SectionHeader 'Cards')) | Out-Null
        foreach ($card in $script:Cards) {
            $script:SidebarPanel.Children.Add((New-DriveRow $card)) | Out-Null
        }
    }

    foreach ($group in $script:Org.groups) {
        $script:SidebarPanel.Children.Add((New-GroupHeader $group)) | Out-Null
        if ($group.driveNames.Count -eq 0) {
            $empty = New-Text '(empty)' 10.5 $script:BrushDim
            $empty.Margin = '18,2,0,4'
            $script:SidebarPanel.Children.Add($empty) | Out-Null
            continue
        }
        foreach ($name in $group.driveNames) {
            $record = Get-RecordByName $name
            if ($record) { $script:SidebarPanel.Children.Add((New-DriveRow $record)) | Out-Null }
        }
    }
}

# ---------------------------------------------------------------- detail pane

function Select-Drive([string]$Name) {
    $script:SelectedName = $Name
    # Take the search pane down first. Show-Detail deliberately does nothing
    # while a query is active, so without this the click would only move the
    # highlight and leave the old results on screen.
    if ($script:SearchInput.Text) { $script:SearchInput.Text = '' }
    Build-Sidebar
    Show-Detail
}

function Set-TabStyle {
    $activeBg = $script:BrushSelected
    $activeFg = $script:BrushGreen
    if ($script:ActiveTab -eq 'contents') {
        $script:TabContents.Background = $activeBg
        $script:TabContents.Foreground = $activeFg
        $script:TabContents.BorderBrush = $script:BrushSelBorder
        $script:TabHistory.Background = $script:BrushClear
        $script:TabHistory.Foreground = $script:BrushDim
        $script:TabHistory.BorderBrush = $script:BrushFaint
    } else {
        $script:TabHistory.Background = $activeBg
        $script:TabHistory.Foreground = $activeFg
        $script:TabHistory.BorderBrush = $script:BrushSelBorder
        $script:TabContents.Background = $script:BrushClear
        $script:TabContents.Foreground = $script:BrushDim
        $script:TabContents.BorderBrush = $script:BrushFaint
    }
}

function Show-Detail {
    if ($script:SearchInput.Text.Trim()) { return }   # search results own the pane

    $record = Get-SelectedRecord
    $script:SearchPane.Visibility = 'Collapsed'
    if (-not $record) {
        $script:DetailPane.Visibility = 'Collapsed'
        $script:PlaceholderPane.Visibility = 'Visible'
        return
    }
    $script:PlaceholderPane.Visibility = 'Collapsed'
    $script:DetailPane.Visibility = 'Visible'

    $script:DetailName.Text = $record.IndexFolderName
    if ($record.IsConnected) {
        $script:DetailIndicator.Background = $script:BrushGreen
        $script:DetailDot.Visibility = 'Visible'
        $script:DetailStatus.Text = 'Connected'
        $script:DetailStatus.Foreground = $script:BrushGreen
        $script:OpenDriveButton.Visibility = 'Visible'
        $script:EjectButton.Visibility = 'Visible'
        # Anything you offload from -- a card, a stick, a recorder -- gets Copy
        # up here. A fixed archive drive keeps it in the right-click menu, out
        # of the way of the job you usually came to do.
        if ($record.IsRemovableMedia) { $script:CopyFilesButton.Visibility = 'Visible' }
        else { $script:CopyFilesButton.Visibility = 'Collapsed' }
        if ($record.IsCard) { $script:NewProjectButton.Visibility = 'Collapsed' }
        else { $script:NewProjectButton.Visibility = 'Visible' }
    } else {
        $script:DetailIndicator.Background = $script:BrushGrey
        $script:DetailDot.Visibility = 'Collapsed'
        $script:DetailStatus.Text = 'Not connected'
        $script:DetailStatus.Foreground = $script:BrushDim
        $script:OpenDriveButton.Visibility = 'Collapsed'
        $script:CopyFilesButton.Visibility = 'Collapsed'
        $script:NewProjectButton.Visibility = 'Collapsed'
        $script:EjectButton.Visibility = 'Collapsed'
    }

    function Get-Value([string]$Text) {
        if ([string]::IsNullOrWhiteSpace($Text) -or $Text -eq 'unknown' -or $Text -eq 'none') { return '--' }
        return $Text
    }

    $lastConnected = '--'
    if ($record.LastConnectedString) {
        $lastConnected = $record.LastConnectedString
        if ($record.LastConnected) {
            $lastConnected = "$lastConnected  ($(Get-RelativeTimeText $record.LastConnected))"
        }
    }

    # Free space can only be measured while the drive is plugged in, so for
    # anything else this is the reading from its last connection.
    $freeText = Get-Value $record.FreeSpace
    if ($freeText -ne '--' -and -not $record.IsConnected) {
        $freeText = "$freeText  (at last connection)"
    }

    $script:StatSize.Text          = 'Size'.PadRight(16) + (Get-Value $record.Size)
    $script:StatFree.Text          = 'Free space'.PadRight(16) + $freeText
    $script:StatFormat.Text        = 'Format'.PadRight(16) + (Get-Value $record.Format)
    $script:StatLetter.Text        = 'Drive letter'.PadRight(16) + (Get-Value $record.Letter)
    if ($record.IsCard) {
        $script:StatLastConnected.Text = 'Kind'.PadRight(16) + 'Memory card -- not catalogued'
        $script:StatLastUser.Visibility = 'Collapsed'
        $script:TabHistory.Visibility = 'Collapsed'
        if ($script:ActiveTab -eq 'history') { $script:ActiveTab = 'contents' }
    } else {
        $script:StatLastConnected.Text = 'Last connected'.PadRight(16) + $lastConnected
        $script:StatLastUser.Text      = 'Last used by'.PadRight(16) + (Get-Value $record.LastUser)
        $script:StatLastUser.Visibility = 'Visible'
        $script:TabHistory.Visibility = 'Visible'
    }

    # Usage bar: two star-sized columns, so it scales with the window.
    $used = 0
    $haveUsed = [int]::TryParse([string]$record.UsedPercent, [ref]$used)
    if ($haveUsed -and $used -ge 0 -and $used -le 100) {
        $script:UsageBar.ColumnDefinitions[0].Width =
            New-Object System.Windows.GridLength ($used, 'Star')
        $script:UsageBar.ColumnDefinitions[1].Width =
            New-Object System.Windows.GridLength ((100 - $used), 'Star')
        # Amber past 90% so a nearly-full drive stands out.
        if ($used -ge 90) {
            $script:UsageFill.Background = $script:BrushAmber
            $script:UsageLabel.Foreground = $script:BrushAmber
        } else {
            $script:UsageFill.Background = $script:BrushGreen
            $script:UsageLabel.Foreground = $script:BrushDim
        }
        $script:UsageLabel.Text = "$used% used"
        $script:UsagePanel.Visibility = 'Visible'
    } else {
        $script:UsagePanel.Visibility = 'Collapsed'
    }

    $script:ContentsNote.Text = $record.ContentsNote
    $script:TabHistory.Content = "History ($($record.History.Count))"
    Set-TabStyle
    Show-Tab
}

function Show-Tab {
    $record = Get-SelectedRecord
    if (-not $record) { return }

    if ($script:ActiveTab -eq 'contents') {
        $script:HistoryScroll.Visibility = 'Collapsed'
        Build-ContentsTree $record
    } else {
        $script:ContentsTree.Visibility = 'Collapsed'
        Build-History $record
    }
}

function Build-ContentsTree($Record) {
    # A cache hit for the drive already on screen means the data has not
    # changed (the cache is emptied whenever the index does), so leave the tree
    # alone -- rebuilding it would throw away whatever the user had expanded.
    if ($script:LastTreeKey -eq $Record.FolderPath -and
        $script:ContentsTree.Items.Count -gt 0 -and
        $script:TreeCache.ContainsKey($Record.FolderPath)) {
        $script:TabPlaceholder.Visibility = 'Collapsed'
        $script:ContentsTree.Visibility = 'Visible'
        return
    }

    $script:ContentsTree.Items.Clear()
    $script:LastTreeKey = $null
    $tree = $null
    if ($script:TreeCache.ContainsKey($Record.FolderPath)) {
        $tree = $script:TreeCache[$Record.FolderPath]
    } else {
        $previousCursor = $window.Cursor
        $window.Cursor = [System.Windows.Input.Cursors]::Wait
        try {
            if ($Record.IsCard) { $tree = Get-LiveContentTree $Record.VolumePath }
            else { $tree = Get-DriveContentTree $Record.FolderPath }
            $script:TreeCache[$Record.FolderPath] = $tree
        } finally {
            $window.Cursor = $previousCursor
        }
    }

    if (-not $tree -or $tree.Children.Count -eq 0) {
        $script:ContentsTree.Visibility = 'Collapsed'
        $script:TabPlaceholder.Visibility = 'Visible'
        $script:TabPlaceholder.Text = "Nothing indexed yet. Either this drive is empty, or it hasn't been scanned since files were added. Connect it and press Rescan."
        return
    }

    $script:TabPlaceholder.Visibility = 'Collapsed'
    $script:ContentsTree.Visibility = 'Visible'
    foreach ($node in $tree.Children) {
        $script:ContentsTree.Items.Add((New-ContentTreeItem $node)) | Out-Null
    }
    $script:LastTreeKey = $Record.FolderPath
}

function New-ContentTreeItem($Node) {
    $item = New-Object System.Windows.Controls.TreeViewItem
    $item.Tag = $Node

    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'
    $nameBrush = $script:BrushText
    if ($Node.IsFile) { $nameBrush = $script:BrushFileText }
    $label = New-Text $Node.Name 12 $nameBrush 'Normal' 'Consolas'
    $label.TextTrimming = 'None'
    $row.Children.Add($label) | Out-Null
    if ($Node.SizeLabel) {
        $size = New-Text $Node.SizeLabel 11 $script:BrushDim 'Normal' 'Consolas'
        $size.Margin = '14,0,0,0'
        $row.Children.Add($size) | Out-Null
    }
    $item.Header = $row

    if ($Node.Children.Count -gt 0) {
        # Fill children only when opened -- a drive can hold thousands of files.
        $item.Items.Add('...') | Out-Null
        $item.add_Expanded({ Expand-ContentTreeItem $this })
    }
    return $item
}

function Expand-ContentTreeItem($Item) {
    if ($Item.Items.Count -eq 1 -and $Item.Items[0] -is [string]) {
        $Item.Items.Clear()
        foreach ($child in $Item.Tag.Children) {
            $Item.Items.Add((New-ContentTreeItem $child)) | Out-Null
        }
    }
}

function Build-History($Record) {
    $script:HistoryPanel.Children.Clear()
    if ($Record.History.Count -eq 0) {
        $script:HistoryScroll.Visibility = 'Collapsed'
        $script:TabPlaceholder.Visibility = 'Visible'
        $script:TabPlaceholder.Text = 'No history yet. Each time this drive is connected, the date and the user signed in at the time are recorded here.'
        return
    }
    $script:TabPlaceholder.Visibility = 'Collapsed'
    $script:HistoryScroll.Visibility = 'Visible'

    $index = 0
    foreach ($entry in $Record.History) {
        $grid = New-Object System.Windows.Controls.Grid
        $grid.Margin = '0,3,0,3'
        foreach ($width in @('Auto', 'Auto', '*', 'Auto')) {
            $col = New-Object System.Windows.Controls.ColumnDefinition
            $col.Width = $width
            $grid.ColumnDefinitions.Add($col)
        }
        $stamp = New-Text $entry.DateString 12 $script:BrushDim 'Normal' 'Consolas'
        [System.Windows.Controls.Grid]::SetColumn($stamp, 0)
        $grid.Children.Add($stamp) | Out-Null

        $user = New-Text $entry.User 12 $script:BrushText 'Medium' 'Consolas'
        $user.Margin = '14,0,0,0'
        [System.Windows.Controls.Grid]::SetColumn($user, 1)
        $grid.Children.Add($user) | Out-Null

        $noteText = ''
        $noteBrush = $script:BrushDim
        if ($index -eq 0) {
            $noteText = 'latest'
            $noteBrush = $script:BrushGreenSoft
        } elseif ($entry.Date) {
            $noteText = Get-RelativeTimeText $entry.Date
        }
        if ($noteText) {
            $note = New-Text $noteText 11 $noteBrush
            [System.Windows.Controls.Grid]::SetColumn($note, 3)
            $grid.Children.Add($note) | Out-Null
        }
        $script:HistoryPanel.Children.Add($grid) | Out-Null
        $index++
    }
}

# ---------------------------------------------------------------- search

# Get-CachedFileList and Find-IndexMatch live in Common.ps1 so the search can
# be tested without opening a window.

function New-SearchRow($Hit) {
    $border = New-Object System.Windows.Controls.Border
    $border.CornerRadius = 5
    $border.Padding = '9,5'
    $border.Margin = '0,1'
    $border.Cursor = 'Hand'
    $border.Background = $script:BrushClear
    $border.Tag = $Hit.DriveName
    $border.add_MouseEnter({ $this.Background = $script:BrushHover })
    $border.add_MouseLeave({ $this.Background = $script:BrushClear })
    $border.add_MouseLeftButtonUp({
        $script:SearchInput.Text = ''
        Select-Drive $this.Tag
    })

    $grid = New-Object System.Windows.Controls.Grid
    foreach ($width in @('Auto', '*', 'Auto', 'Auto')) {
        $col = New-Object System.Windows.Controls.ColumnDefinition
        $col.Width = $width
        $grid.ColumnDefinitions.Add($col)
    }

    $marker = New-Object System.Windows.Controls.Border
    $marker.Width = 13
    $marker.Height = 10
    $marker.CornerRadius = 2
    $marker.VerticalAlignment = 'Center'
    $marker.Margin = '0,0,10,0'
    if ($Hit.Kind -eq 'drive') { $marker.Background = $script:BrushGreen }
    elseif ($Hit.Kind -eq 'folder') { $marker.Background = $script:BrushGrey }
    else {
        $marker.Background = $script:BrushClear
        $marker.BorderBrush = $script:BrushGrey
        $marker.BorderThickness = 1
    }
    [System.Windows.Controls.Grid]::SetColumn($marker, 0)
    $grid.Children.Add($marker) | Out-Null

    $stack = New-Object System.Windows.Controls.StackPanel
    $stack.VerticalAlignment = 'Center'
    $stack.Children.Add((New-Text $Hit.Name 12 $script:BrushText 'Medium')) | Out-Null
    if ($Hit.Path) {
        $pathText = New-Text ($Hit.Path -replace '\\', '  >  ') 10.5 $script:BrushDim 'Normal' 'Consolas'
        $stack.Children.Add($pathText) | Out-Null
    }
    [System.Windows.Controls.Grid]::SetColumn($stack, 1)
    $grid.Children.Add($stack) | Out-Null

    if ($Hit.SizeLabel) {
        $size = New-Text $Hit.SizeLabel 11 $script:BrushDim 'Normal' 'Consolas'
        $size.Margin = '10,0,12,0'
        [System.Windows.Controls.Grid]::SetColumn($size, 2)
        $grid.Children.Add($size) | Out-Null
    }

    $tag = New-Object System.Windows.Controls.Border
    $tag.CornerRadius = 4
    $tag.Padding = '6,2'
    $tag.Background = New-Brush '#1A4DE680'
    $tag.VerticalAlignment = 'Center'
    $tag.Child = (New-Text $Hit.DriveName 10.5 $script:BrushGreenSoft 'Normal' 'Consolas')
    [System.Windows.Controls.Grid]::SetColumn($tag, 3)
    $grid.Children.Add($tag) | Out-Null

    $border.Child = $grid
    return $border
}

function Update-SearchResults {
    $query = $script:SearchInput.Text.Trim()
    $script:SearchPlaceholder.Visibility = 'Collapsed'
    if (-not $script:SearchInput.Text) { $script:SearchPlaceholder.Visibility = 'Visible' }

    if (-not $query) {
        $script:SearchPane.Visibility = 'Collapsed'
        Show-Detail
        return
    }

    $script:DetailPane.Visibility = 'Collapsed'
    $script:PlaceholderPane.Visibility = 'Collapsed'
    $script:SearchPane.Visibility = 'Visible'
    $script:SearchResultsPanel.Children.Clear()

    $previousCursor = $window.Cursor
    $window.Cursor = [System.Windows.Input.Cursors]::Wait
    try {
        # @() so a single match (or none) still behaves like a collection.
        $hits = @(Find-IndexMatch $script:Records $query)
    } finally {
        $window.Cursor = $previousCursor
    }

    if ($hits.Count -eq 0) {
        $script:SearchSummary.Text = "No matches for `"$query`""
        $empty = New-Text 'Search covers drive names, folders and files on every drive ever indexed.' 12 $script:BrushDim
        $empty.TextWrapping = 'Wrap'
        $empty.TextTrimming = 'None'
        $empty.Margin = '10,14,10,0'
        $script:SearchResultsPanel.Children.Add($empty) | Out-Null
        return
    }

    $count = "$($hits.Count)"
    if ($hits.Count -ge 400) { $count = '400+' }
    $plural = 's'
    if ($hits.Count -eq 1) { $plural = '' }
    $script:SearchSummary.Text = "$count result$plural -- click one to open its drive"
    foreach ($hit in $hits) {
        $script:SearchResultsPanel.Children.Add((New-SearchRow $hit)) | Out-Null
    }
}

# ---------------------------------------------------------------- actions

function Invoke-Eject([string]$Name) {
    if ($script:EjectPending) { return }
    $record = Get-RecordByName $Name
    if (-not $record -or -not $record.IsConnected) { return }
    $letter = $record.Letter
    if (-not $letter) { return }

    $failure = $null
    try {
        $shell = New-Object -ComObject Shell.Application
        $item = $shell.NameSpace(17).ParseName($letter)
        if ($item) { $item.InvokeVerb('Eject') }
        else { $failure = "Windows did not report a drive at $letter." }
    } catch {
        $failure = $_.Exception.Message
    }
    if ($failure) {
        Show-EjectFailure $record.IndexFolderName $failure
        Invoke-Reload
        return
    }

    # Windows drops the volume a moment later. Wait for it on a timer instead of
    # sleeping here: sleeping would block the dispatcher and freeze the window.
    $script:EjectPending = [pscustomobject]@{ Name = $Name; Letter = $letter; Attempts = 0 }
    # Only touch the button if it actually belongs to this drive -- eject is
    # also reachable from the context menu of a drive that isn't selected.
    if ($Name -eq $script:SelectedName) {
        $script:EjectButton.Content = 'Ejecting...'
        $script:EjectButton.IsEnabled = $false
    }
    $script:EjectTimer.Start()
}

function Show-EjectFailure([string]$DriveName, [string]$Detail) {
    $message = "$DriveName could not be ejected."
    if ($Detail) { $message = "$message`r`n`r`n$Detail" }
    $message = "$message`r`n`r`nA file on the drive may still be open in another program. Close it and try again, or use the Safely Remove Hardware icon in the taskbar."
    [System.Windows.MessageBox]::Show($message, 'AVM Drive Index',
        [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
}

function Complete-Eject([bool]$Ejected) {
    $pending = $script:EjectPending
    $script:EjectTimer.Stop()
    $script:EjectPending = $null
    if ($pending -and $pending.Name -eq $script:SelectedName) {
        $script:EjectButton.Content = 'Eject'
        $script:EjectButton.IsEnabled = $true
    }
    if ($pending -and -not $Ejected) { Show-EjectFailure $pending.Name $null }
    Invoke-Reload
}

function Remove-DriveIndex([string]$Name) {
    $record = Get-RecordByName $Name
    if (-not $record) { return }

    $message = "Remove `"$($record.IndexFolderName)`" from the index?`r`n`r`nIts folder list and connection history will be moved to the Recycle Bin."
    if ($record.IsConnected) {
        $message = "$message`r`n`r`nNote: this drive is still connected, so it will be indexed again right away. Eject it first if you want it off the list."
    } else {
        $message = "$message`r`n`r`nIf the drive is ever connected again, a fresh record will be started."
    }
    $answer = [System.Windows.MessageBox]::Show($message, 'AVM Drive Index',
        [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
    if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }

    try {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
            $record.FolderPath,
            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
    } catch {
        [System.Windows.MessageBox]::Show(
            "That drive's index folder could not be removed.`r`n`r`n$($_.Exception.Message)",
            'AVM Drive Index') | Out-Null
        return
    }

    $script:TreeCache.Remove($record.FolderPath) | Out-Null
    Clear-FileListCache $record.FolderPath
    if ($script:SelectedName -eq $Name) { $script:SelectedName = $null }
    Invoke-Reload
    Invoke-Rescan
}

function Move-DriveToGroup([string]$Name, $GroupId) {
    Remove-FromList $script:Org.ungrouped $Name
    foreach ($group in $script:Org.groups) {
        Remove-FromList $group.driveNames $Name
    }
    $target = $null
    if ($GroupId) {
        foreach ($group in $script:Org.groups) {
            if ($group.id -eq $GroupId) { $target = $group; break }
        }
    }
    if ($target) { $target.driveNames.Add($Name) | Out-Null }
    else { $script:Org.ungrouped.Add($Name) | Out-Null }
    Save-Organization $script:Org
    Build-Sidebar
}

function Move-DriveOrder([string]$Name, [int]$Delta) {
    # Collect the lists themselves -- @($list) would unroll them into strings.
    $lists = New-Object System.Collections.Generic.List[object]
    $lists.Add($script:Org.ungrouped) | Out-Null
    foreach ($group in $script:Org.groups) { $lists.Add($group.driveNames) | Out-Null }

    foreach ($list in $lists) {
        $index = $list.IndexOf($Name)
        if ($index -lt 0) { continue }
        $target = $index + $Delta
        if ($target -lt 0 -or $target -ge $list.Count) { return }
        $list.RemoveAt($index)
        $list.Insert($target, $Name)
        Save-Organization $script:Org
        Build-Sidebar
        return
    }
}

function New-DriveFolder([string]$DriveToMove) {
    $name = [Microsoft.VisualBasic.Interaction]::InputBox(
        'Name for the new folder:', 'AVM Drive Index', '')
    if (-not $name -or -not $name.Trim()) { return }
    $group = [pscustomobject]@{
        id         = [guid]::NewGuid().ToString()
        name       = $name.Trim()
        driveNames = (New-Object System.Collections.Generic.List[object])
    }
    $script:Org.groups.Add($group) | Out-Null
    Save-Organization $script:Org
    if ($DriveToMove) { Move-DriveToGroup $DriveToMove $group.id } else { Build-Sidebar }
}

function Rename-DriveGroup([string]$GroupId) {
    foreach ($group in $script:Org.groups) {
        if ($group.id -ne $GroupId) { continue }
        $name = [Microsoft.VisualBasic.Interaction]::InputBox(
            'New name for this folder:', 'AVM Drive Index', $group.name)
        if (-not $name -or -not $name.Trim()) { return }
        $group.name = $name.Trim()
        Save-Organization $script:Org
        Build-Sidebar
        return
    }
}

function Move-GroupOrder([string]$GroupId, [int]$Delta) {
    $groups = $script:Org.groups
    for ($i = 0; $i -lt $groups.Count; $i++) {
        if ($groups[$i].id -ne $GroupId) { continue }
        $target = $i + $Delta
        if ($target -lt 0 -or $target -ge $groups.Count) { return }
        $moving = $groups[$i]
        $groups.RemoveAt($i)
        $groups.Insert($target, $moving)
        Save-Organization $script:Org
        Build-Sidebar
        return
    }
}

function Remove-DriveGroup([string]$GroupId) {
    $groups = $script:Org.groups
    for ($i = 0; $i -lt $groups.Count; $i++) {
        if ($groups[$i].id -ne $GroupId) { continue }
        foreach ($name in $groups[$i].driveNames) {
            $script:Org.ungrouped.Add($name) | Out-Null
        }
        $groups.RemoveAt($i)
        Save-Organization $script:Org
        Build-Sidebar
        return
    }
}

function Invoke-Reload {
    Update-Records
    Build-Sidebar
    if ($script:SearchInput.Text.Trim()) { Update-SearchResults } else { Show-Detail }
}

function Invoke-Rescan {
    if ($script:ScanProcess -and -not $script:ScanProcess.HasExited) { return }
    $indexer = Join-Path $PSScriptRoot 'DriveIndexer.ps1'
    if (-not (Test-Path -LiteralPath $indexer)) { return }
    try {
        $script:ScanProcess = Start-Process -FilePath (Get-HostExecutable) -ArgumentList @(
            '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
            '-WindowStyle', 'Hidden', '-File', "`"$indexer`""
        ) -WindowStyle Hidden -PassThru -ErrorAction Stop
        $script:RescanButton.Content = 'Scanning...'
        $script:RescanButton.IsEnabled = $false
    } catch {
        [System.Windows.MessageBox]::Show(
            "The scan could not be started.`r`n`r`n$($_.Exception.Message)",
            'AVM Drive Index') | Out-Null
    }
}

function Copy-FilesFromVolume([string]$Name) {
    if ($script:CopyState) { return }        # one copy at a time
    $record = $null
    if ($Name) { $record = Get-RecordByName $Name } else { $record = Get-SelectedRecord }
    if (-not $record -or -not $record.VolumePath) { return }

    try {
        Show-CopyPicker $record
    } catch {
        # If the picker cannot be built for any reason, fall back to Windows'
        # own file dialog so copying still works.
        [System.Windows.MessageBox]::Show(
            "The file browser could not be shown, so Windows' file picker will be used instead.`r`n`r`n$($_.Exception.Message)",
            'Copy Files') | Out-Null
        Copy-FilesWithNativePicker $record
    }
}

function Get-CopyDestination($Record) {
    # Start the folder picker on another drive that is plugged in.
    $suggested = $Record.VolumePath
    foreach ($other in $script:Records) {
        if ($other.VolumePath -and $other.IndexFolderName -ne $Record.IndexFolderName) {
            $suggested = $other.VolumePath; break
        }
    }
    try {
        $shell = New-Object -ComObject Shell.Application
        $chosen = $shell.BrowseForFolder(0, 'Where should these files go?', 0, $suggested)
        if (-not $chosen) { return $null }
        return $chosen.Self.Path
    } catch {
        [System.Windows.MessageBox]::Show(
            "A folder could not be chosen.`r`n`r`n$($_.Exception.Message)", 'Copy Files') | Out-Null
        return $null
    }
}

function Show-CopyPicker($Record) {
    # A tree of the volume's folders and files. Tick a whole folder or open it
    # and tick single files.
    $tree = Get-CopyTree $Record.VolumePath
    if ($tree.Children.Count -eq 0) {
        [System.Windows.MessageBox]::Show(
            "No readable files were found on $($Record.IndexFolderName).", 'Copy Files') | Out-Null
        return
    }
    $script:CopySelection = New-Object System.Collections.Generic.HashSet[string]
    $script:CopyBoxes = New-Object System.Collections.ArrayList
    $script:CopyRoots = $tree.Children
    $script:CopyDestination = $null

    $picker = New-Object System.Windows.Window
    $picker.Title = "Copy from $($Record.IndexFolderName)"
    $picker.Width = 640
    $picker.Height = 560
    $picker.WindowStartupLocation = 'CenterOwner'
    try { $picker.Owner = $window } catch { }
    $picker.Background = $script:BrushRaised

    $layout = New-Object System.Windows.Controls.Grid
    $layout.Margin = '18'
    foreach ($h in @('Auto', 'Auto', '*', 'Auto', 'Auto')) {
        $row = New-Object System.Windows.Controls.RowDefinition
        $row.Height = $h
        $layout.RowDefinitions.Add($row)
    }

    $title = New-Text "Copy from $($Record.IndexFolderName)" 15 $script:BrushText 'Bold' 'Consolas'
    [System.Windows.Controls.Grid]::SetRow($title, 0)
    $layout.Children.Add($title) | Out-Null

    $tools = New-Object System.Windows.Controls.StackPanel
    $tools.Orientation = 'Horizontal'
    $tools.Margin = '0,10,0,8'
    $selectAll = New-Object System.Windows.Controls.Button
    $selectAll.Content = 'Select all'
    try { $selectAll.Style = $window.FindResource('PipButton') } catch { }
    $selectAll.add_Click({
        foreach ($node in $script:CopyRoots) {
            foreach ($file in (Get-CopyNodeFiles $node)) { [void]$script:CopySelection.Add($file.Id) }
        }
        Update-CopyBoxes
    })
    $none = New-Object System.Windows.Controls.Button
    $none.Content = 'None'
    $none.Margin = '8,0,0,0'
    try { $none.Style = $window.FindResource('PipButton') } catch { }
    $none.add_Click({ $script:CopySelection.Clear(); Update-CopyBoxes })
    $tools.Children.Add($selectAll) | Out-Null
    $tools.Children.Add($none) | Out-Null
    [System.Windows.Controls.Grid]::SetRow($tools, 1)
    $layout.Children.Add($tools) | Out-Null

    $treeView = New-Object System.Windows.Controls.TreeView
    $treeView.Background = $script:BrushClear
    $treeView.BorderThickness = 1
    $treeView.BorderBrush = $script:BrushFaint
    foreach ($node in $tree.Children) {
        $treeView.Items.Add((New-CopyTreeItem $node)) | Out-Null
    }
    [System.Windows.Controls.Grid]::SetRow($treeView, 2)
    $layout.Children.Add($treeView) | Out-Null

    $destPanel = New-Object System.Windows.Controls.StackPanel
    $destPanel.Margin = '0,12,0,0'
    $destPanel.Children.Add((New-Text 'Copy into' 11 $script:BrushDim)) | Out-Null
    $destRow = New-Object System.Windows.Controls.Grid
    $destRow.Margin = '0,4,0,0'
    foreach ($w in @('*', 'Auto')) {
        $col = New-Object System.Windows.Controls.ColumnDefinition
        $col.Width = $w
        $destRow.ColumnDefinitions.Add($col)
    }
    $script:CopyDestText = New-Text 'Choose a folder on another drive...' 11.5 $script:BrushDim 'Normal' 'Consolas'
    [System.Windows.Controls.Grid]::SetColumn($script:CopyDestText, 0)
    $destRow.Children.Add($script:CopyDestText) | Out-Null
    $choose = New-Object System.Windows.Controls.Button
    $choose.Content = 'Choose...'
    try { $choose.Style = $window.FindResource('PipButton') } catch { }
    $choose.add_Click({
        $picked = Get-CopyDestination $script:CopyRecord
        if ($picked) {
            $script:CopyDestination = $picked
            $script:CopyDestText.Text = $picked
            $script:CopyDestText.Foreground = $script:BrushText
        }
    })
    [System.Windows.Controls.Grid]::SetColumn($choose, 1)
    $destRow.Children.Add($choose) | Out-Null
    $destPanel.Children.Add($destRow) | Out-Null
    [System.Windows.Controls.Grid]::SetRow($destPanel, 3)
    $layout.Children.Add($destPanel) | Out-Null

    $footer = New-Object System.Windows.Controls.Grid
    $footer.Margin = '0,14,0,0'
    foreach ($w in @('*', 'Auto')) {
        $col = New-Object System.Windows.Controls.ColumnDefinition
        $col.Width = $w
        $footer.ColumnDefinitions.Add($col)
    }
    $script:CopyCountText = New-Text 'Nothing selected' 11 $script:BrushDim 'Normal' 'Consolas'
    [System.Windows.Controls.Grid]::SetColumn($script:CopyCountText, 0)
    $footer.Children.Add($script:CopyCountText) | Out-Null
    $buttons = New-Object System.Windows.Controls.StackPanel
    $buttons.Orientation = 'Horizontal'
    $cancel = New-Object System.Windows.Controls.Button
    $cancel.Content = 'Cancel'
    try { $cancel.Style = $window.FindResource('PipButton') } catch { }
    $cancel.add_Click({ $script:CopyPickerWindow.Close() })
    $copy = New-Object System.Windows.Controls.Button
    $copy.Content = 'Copy'
    $copy.Margin = '8,0,0,0'
    try { $copy.Style = $window.FindResource('PipButton') } catch { }
    $copy.add_Click({
        if (-not $script:CopyDestination) {
            [System.Windows.MessageBox]::Show('Choose a folder to copy into first.', 'Copy Files') | Out-Null
            return
        }
        $items = @(Get-CopyItems $script:CopyRoots $script:CopySelection)
        if ($items.Count -eq 0) {
            [System.Windows.MessageBox]::Show('Nothing is selected.', 'Copy Files') | Out-Null
            return
        }
        $destination = $script:CopyDestination
        $sourceName = $script:CopyRecord.IndexFolderName
        $script:CopyPickerWindow.Close()
        Start-CopyJob $items $destination $sourceName
    })
    $buttons.Children.Add($cancel) | Out-Null
    $buttons.Children.Add($copy) | Out-Null
    [System.Windows.Controls.Grid]::SetColumn($buttons, 1)
    $footer.Children.Add($buttons) | Out-Null
    [System.Windows.Controls.Grid]::SetRow($footer, 4)
    $layout.Children.Add($footer) | Out-Null

    $picker.Content = $layout
    $script:CopyPickerWindow = $picker
    $script:CopyRecord = $Record
    Update-CopyBoxes
    $picker.ShowDialog() | Out-Null
    $script:CopyBoxes = $null
    $script:CopyPickerWindow = $null
}

function New-CopyTreeItem($Node) {
    $item = New-Object System.Windows.Controls.TreeViewItem
    $item.Tag = $Node

    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'
    $box = New-Object System.Windows.Controls.CheckBox
    $box.IsThreeState = $true
    $box.VerticalAlignment = 'Center'
    $box.Margin = '0,0,7,0'
    $box.Tag = $Node
    # Click, not Checked: setting IsChecked in code must not loop back here.
    $box.add_Click({
        Set-CopyTick $this.Tag $script:CopySelection
        Update-CopyBoxes
    })
    $row.Children.Add($box) | Out-Null

    $label = New-Text $Node.Name 12 $script:BrushText 'Normal' 'Consolas'
    if ($Node.IsFile) { $label.Foreground = $script:BrushFileText }
    $row.Children.Add($label) | Out-Null

    $detail = if ($Node.IsFile) { Format-DriveSize $Node.Size }
              else { "$((Get-CopyNodeFiles $Node).Count) files" }
    $note = New-Text $detail 10.5 $script:BrushDim 'Normal' 'Consolas'
    $note.Margin = '12,0,0,0'
    $row.Children.Add($note) | Out-Null

    $item.Header = $row
    [void]$script:CopyBoxes.Add([pscustomobject]@{ Node = $Node; Box = $box })

    if (-not $Node.IsFile -and $Node.Children.Count -gt 0) {
        $item.Items.Add('...') | Out-Null      # filled in when opened
        $item.add_Expanded({ Expand-CopyTreeItem $this })
    }
    return $item
}

function Expand-CopyTreeItem($Item) {
    if ($Item.Items.Count -eq 1 -and $Item.Items[0] -is [string]) {
        $Item.Items.Clear()
        foreach ($child in $Item.Tag.Children) {
            $Item.Items.Add((New-CopyTreeItem $child)) | Out-Null
        }
        Update-CopyBoxes
    }
}

function Update-CopyBoxes {
    if (-not $script:CopyBoxes) { return }
    foreach ($entry in $script:CopyBoxes) {
        $state = Get-CopyTickState $entry.Node $script:CopySelection
        if ($state -eq 'all') { $entry.Box.IsChecked = $true }
        elseif ($state -eq 'none') { $entry.Box.IsChecked = $false }
        else { $entry.Box.IsChecked = $null }
    }
    if ($script:CopyCountText) {
        $items = @(Get-CopyItems $script:CopyRoots $script:CopySelection)
        $bytes = 0
        foreach ($item in $items) { $bytes += $item.Size }
        if ($items.Count -eq 0) { $script:CopyCountText.Text = 'Nothing selected' }
        else { $script:CopyCountText.Text = "$($items.Count) selected  |  $(Format-DriveSize $bytes)" }
    }
}

function Copy-FilesWithNativePicker($Record) {
    $dialog = New-Object Microsoft.Win32.OpenFileDialog
    $dialog.Multiselect = $true
    $dialog.Title = "Choose files to copy from $($Record.IndexFolderName)"
    $start = $Record.VolumePath
    $dcim = Join-Path $Record.VolumePath 'DCIM'
    if (Test-Path -LiteralPath $dcim) { $start = $dcim }
    $dialog.InitialDirectory = $start
    if ($dialog.ShowDialog() -ne $true) { return }
    $chosen = @($dialog.FileNames)
    if ($chosen.Count -eq 0) { return }
    $destination = Get-CopyDestination $Record
    if (-not $destination) { return }
    $items = New-Object System.Collections.ArrayList
    foreach ($path in $chosen) {
        $size = 0
        try { $size = (Get-Item -LiteralPath $path).Length } catch { }
        [void]$items.Add([pscustomobject]@{
            Source = $path; RelativePath = (Split-Path $path -Leaf); Size = $size })
    }
    Start-CopyJob $items.ToArray() $destination $Record.IndexFolderName
}

function Start-CopyJob($Items, [string]$Destination, [string]$SourceName) {
    # Files are copied one per timer tick rather than in a tight loop, so the
    # window keeps painting and Stop stays responsive.
    $progress = New-Object System.Windows.Window
    $progress.Title = 'Copying'
    $progress.Width = 500
    $progress.SizeToContent = 'Height'
    $progress.ResizeMode = 'NoResize'
    $progress.WindowStartupLocation = 'CenterOwner'
    try { $progress.Owner = $window } catch { }
    $progress.Background = $script:BrushRaised

    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Margin = '18'
    $panel.Children.Add((New-Text "Copying from $SourceName" 14 $script:BrushText 'Bold' 'Consolas')) | Out-Null
    $status = New-Text '' 11.5 $script:BrushDim
    $status.Margin = '0,10,0,8'
    $panel.Children.Add($status) | Out-Null
    $bar = New-Object System.Windows.Controls.ProgressBar
    $bar.Height = 8
    $bar.Minimum = 0
    $bar.Maximum = $Items.Count
    $bar.Foreground = $script:BrushGreen
    $bar.Background = $script:BrushFaint
    $panel.Children.Add($bar) | Out-Null
    $stop = New-Object System.Windows.Controls.Button
    $stop.Content = 'Stop'
    $stop.HorizontalAlignment = 'Right'
    $stop.Margin = '0,14,0,0'
    try { $stop.Style = $window.FindResource('PipButton') } catch { }
    $stop.add_Click({ if ($script:CopyState) { $script:CopyState.Cancelled = $true } })
    $panel.Children.Add($stop) | Out-Null
    $progress.Content = $panel

    $script:CopyState = [pscustomobject]@{
        Items = $Items; Destination = $Destination; SourceName = $SourceName
        Index = 0; Copied = 0; Skipped = 0
        Failed = (New-Object System.Collections.ArrayList)
        Bar = $bar; Status = $status; Window = $progress; Cancelled = $false
    }
    $script:CopyTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:CopyTimer.Interval = [TimeSpan]::FromMilliseconds(1)
    $script:CopyTimer.add_Tick({ Step-CopyJob })
    $script:CopyTimer.Start()
    $progress.ShowDialog() | Out-Null      # the timer keeps ticking inside this
}

function Step-CopyJob {
    $state = $script:CopyState
    if (-not $state) { $script:CopyTimer.Stop(); return }
    if ($state.Cancelled -or $state.Index -ge $state.Items.Count) {
        $script:CopyTimer.Stop()
        Complete-CopyJob
        return
    }
    $item = $state.Items[$state.Index]
    $state.Index = $state.Index + 1
    $name = $item.RelativePath
    $state.Status.Text = "$name   ($($state.Index) of $($state.Items.Count))"
    $state.Bar.Value = $state.Index

    $result = Copy-OneItem $item $state.Destination
    if ($result.Status -eq 'copied') { $state.Copied = $state.Copied + 1 }
    elseif ($result.Status -eq 'skipped') { $state.Skipped = $state.Skipped + 1 }
    else { [void]$state.Failed.Add("$name -- $($result.Error)") }
}

function Complete-CopyJob {
    $state = $script:CopyState
    if (-not $state) { return }
    $script:CopyState = $null
    try { $state.Window.Close() } catch { }

    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add("$($state.Copied) copied into $($state.Destination)")
    if ($state.Skipped -gt 0) {
        [void]$lines.Add("$($state.Skipped) skipped -- a file of that name was already there")
    }
    if ($state.Failed.Count -gt 0) {
        [void]$lines.Add("$($state.Failed.Count) failed:")
        foreach ($failure in $state.Failed) { [void]$lines.Add("  $failure") }
    }
    if ($state.Cancelled) { [void]$lines.Add('Stopped before the end.') }
    [void]$lines.Add("Nothing was removed from $($state.SourceName).")
    [System.Windows.MessageBox]::Show(($lines.ToArray() -join "`r`n"), 'Copy Files') | Out-Null
    Invoke-Rescan
}

function New-DriveProject {
    $record = Get-SelectedRecord
    if (-not $record -or -not $record.VolumePath) { return }

    $name = [Microsoft.VisualBasic.Interaction]::InputBox(
        'Name for the new project:', 'New Project', 'My Project')
    if (-not $name) { return }
    $rejection = Get-ProjectNameRejection $name
    if ($rejection) {
        [System.Windows.MessageBox]::Show($rejection, 'New Project') | Out-Null
        return
    }

    # Where to put it -- the drive's root to start with.
    $parent = $record.VolumePath
    try {
        $shell = New-Object -ComObject Shell.Application
        $chosen = $shell.BrowseForFolder(0, 'Where should the project folder go?', 0, $parent)
        if (-not $chosen) { return }        # cancelled
        $parent = $chosen.Self.Path
    } catch {
        # No picker available: fall back to the drive root.
    }

    $result = New-ProjectFolders $name $parent
    if (-not $result.Ok) {
        [System.Windows.MessageBox]::Show($result.Error, 'New Project',
            [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }
    Start-Process -FilePath 'explorer.exe' -ArgumentList $result.Path
    Invoke-Rescan
}

function Test-WatcherInstalled {
    # The installer registers a scheduled task, or falls back to a Startup
    # shortcut when task registration is blocked. Either counts as installed.
    try {
        $task = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction Stop
        if ($task) { return $true }
    } catch { }
    $startupLink = Join-Path ([Environment]::GetFolderPath('Startup')) 'AVM Drive Indexer.lnk'
    return (Test-Path -LiteralPath $startupLink)
}

function Update-WatcherBanner {
    if (Test-WatcherInstalled) {
        $script:WatcherBanner.Visibility = 'Collapsed'
    } else {
        $script:WatcherBanner.Visibility = 'Visible'
    }
}

# ---------------------------------------------------------------- wiring

$script:RescanButton.add_Click({ Invoke-Rescan })

$script:NewFolderButton.add_Click({ New-DriveFolder $null })

$script:CopyFilesButton.add_Click({ Copy-FilesFromVolume $null })

$script:NewProjectButton.add_Click({ New-DriveProject })

$script:OpenDriveButton.add_Click({
    $record = Get-SelectedRecord
    if ($record -and $record.VolumePath) {
        Start-Process -FilePath 'explorer.exe' -ArgumentList $record.VolumePath
    }
})

$script:EjectButton.add_Click({
    $record = Get-SelectedRecord
    if ($record) { Invoke-Eject $record.IndexFolderName }
})

$script:TabContents.add_Click({
    $script:ActiveTab = 'contents'
    $script:TabPlaceholder.Visibility = 'Collapsed'
    Set-TabStyle
    Show-Tab
})

$script:TabHistory.add_Click({
    $script:ActiveTab = 'history'
    $script:TabPlaceholder.Visibility = 'Collapsed'
    Set-TabStyle
    Show-Tab
})

$script:TurnOnButton.add_Click({
    $installer = Join-Path $script:ToolsRoot 'Install Drive Indexer.cmd'
    if (Test-Path -LiteralPath $installer) {
        Start-Process -FilePath $installer
    } else {
        [System.Windows.MessageBox]::Show(
            "Couldn't find `"Install Drive Indexer.cmd`" next to the app.", 'AVM Drive Index') | Out-Null
    }
})

# Polls for the volume actually going away after an eject.
$script:EjectTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:EjectTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$script:EjectTimer.add_Tick({
    $pending = $script:EjectPending
    if (-not $pending) { $script:EjectTimer.Stop(); return }
    $pending.Attempts = $pending.Attempts + 1
    if (-not (Test-Path -LiteralPath ($pending.Letter + '\'))) { Complete-Eject $true }
    elseif ($pending.Attempts -ge 8) { Complete-Eject $false }
})

# Search is debounced so typing stays responsive on big indexes.
$script:SearchTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:SearchTimer.Interval = [TimeSpan]::FromMilliseconds(300)
$script:SearchTimer.add_Tick({
    $script:SearchTimer.Stop()
    Update-SearchResults
})

$script:SearchInput.add_TextChanged({
    $script:SearchPlaceholder.Visibility = 'Collapsed'
    if (-not $script:SearchInput.Text) { $script:SearchPlaceholder.Visibility = 'Visible' }
    $script:SearchTimer.Stop()
    $script:SearchTimer.Start()
})

$script:SearchInput.add_KeyDown({
    if ($_.Key -eq [System.Windows.Input.Key]::Escape) {
        $script:SearchInput.Text = ''
    }
})

$window.add_PreviewKeyDown({
    if ($_.Key -eq [System.Windows.Input.Key]::F -and
        ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
        $script:SearchInput.Focus() | Out-Null
        $script:SearchInput.SelectAll()
        $_.Handled = $true
    }
})

# Keeps the window in step with the background helper.
$script:RefreshTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:RefreshTimer.Interval = [TimeSpan]::FromSeconds(3)
$script:RefreshTimer.add_Tick({
    if ($script:ScanProcess -and $script:ScanProcess.HasExited) {
        $script:ScanProcess = $null
        $script:RescanButton.Content = 'Rescan'
        $script:RescanButton.IsEnabled = $true
        $script:TreeCache.Clear()
    }
    $stamp = Get-IndexStamp
    if ($stamp -ne $script:IndexStamp) {
        $script:TreeCache.Clear()
        Invoke-Reload
    } else {
        # A drive can be plugged in or ejected before the index is rewritten.
        # Get-VolumeFingerprint is cheap, so this can run on a timer; a full
        # reload (which does query WMI) only happens when it actually changes.
        $fingerprint = Get-VolumeFingerprint
        if ($fingerprint -ne $script:VolumeFingerprint) {
            $script:VolumeFingerprint = $fingerprint
            Invoke-Reload
        }
    }
})

$window.add_Loaded({
    Update-WatcherBanner
    Invoke-Reload
    $script:RefreshTimer.Start()
})

$window.add_Closed({
    $script:RefreshTimer.Stop()
    $script:SearchTimer.Stop()
    $script:EjectTimer.Stop()
})

$window.ShowDialog() | Out-Null
