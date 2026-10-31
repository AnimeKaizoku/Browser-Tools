<# : batch launcher, the PowerShell part starts after the closing comment tag
@echo off
REM fltmc needs admin and, unlike "net session", works with the Server service disabled
fltmc >nul 2>&1
if errorlevel 1 (
    if "%~1"=="elevated" (
        echo ERROR: could not get administrator rights.
        pause
        exit /b 1
    )
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList 'elevated' -Verb RunAs"
    exit /b
)
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "iex ([IO.File]::ReadAllText('%~f0'))"
exit /b
#>

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Namespace Native -Name Dpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
[void][Native.Dpi]::SetProcessDPIAware()
[Windows.Forms.Application]::EnableVisualStyles()

$key = 'HKLM:\SOFTWARE\Policies\Google\Chrome'

function S($group, $policy, $value, $name, $desc, $default = $true) {
    [pscustomobject]@{ Group = $group; Policy = $policy; Value = $value; Name = $name; Desc = $desc; Default = $default }
}

$settings = @(
    S 'AI' 'SearchContentSharingSettings' 1 'Ask Google about this page' 'Hides "Ask Google about this page" and stops sharing page content with AI Mode and Lens.'
    S 'AI' 'AIModeSettings' 1 'AI Mode' 'Removes AI Mode from the address bar and the New Tab search box.'
    S 'AI' 'ThirdPartyAiChatSettings' 1 'Third-party AI chat' 'Blocks other companies'' AI chat in the address bar and New Tab search box.'
    S 'AI' 'GeminiSettings' 1 'Gemini in Chrome' 'Turns off the Gemini assistant built into Chrome.'
    S 'AI' 'GeminiActOnWebSettings' 1 'Gemini acting on pages' 'Stops Gemini from clicking and typing on web pages for you.'
    S 'AI' 'GeminiSparkSettings' 1 'Gemini Spark' 'Stops Gemini Spark connecting to Chrome and browsing automatically.'
    S 'AI' 'GeminiChromeFileUploadSettings' 1 'Gemini file uploads' 'Blocks uploading files to Gemini in Chrome.'
    S 'AI' 'GenAILocalFoundationalModelSettings' 1 'On-device AI model' 'Stops Chrome downloading its on-device AI model.'
    S 'AI' 'BuiltInAIAPIsEnabled' 0 'Built-in AI for websites' 'Stops websites using Chrome''s built-in AI (summarizer, prompt APIs).'
    S 'AI' 'HelpMeWriteSettings' 2 'Help me write' 'Removes the AI writing helper from text boxes.'
    S 'AI' 'TabCompareSettings' 2 'Tab compare' 'Turns off AI comparison of products across tabs.'
    S 'AI' 'AutofillGenAiSettings' 2 'AI in Autofill' 'Turns off generative AI features in Autofill.'
    S 'AI' 'DevToolsGenAiSettings' 2 'AI in DevTools' 'Turns off AI assistance in Chrome DevTools.'
    S 'AI' 'LensRegionSearchEnabled' 0 'Search with Google Lens' 'Removes "Search with Google Lens" from the right-click menu.'
    S 'AI' 'LensDesktopNTPSearchEnabled' 0 'Lens on New Tab page' 'Removes the Lens button from the New Tab search box.'
    S 'AI' 'GoogleSearchSidePanelEnabled' 0 'Search this page side panel' 'Removes the Google "Search this page" side panel.'
    S 'AI' 'HistorySearchSettings' 2 'AI history search (old)' 'AI-powered history search. Only matters on Chrome 156 and older.'
    S 'AI' 'AutofillPredictionSettings' 2 'Enhanced autofill (old)' 'Older AI autofill switch. Only matters on Chrome 156 and older.'
    S 'AI' 'LensOverlaySettings' 1 'Lens overlay (old)' 'Older switch for Lens and Ask Google. Only matters on Chrome 146 and older.'
    S 'AI' 'GenAiDefaultSettings' 2 'Default for all AI features' 'Blocks AI features by default. Only works on cloud-managed browsers.'
    S 'Telemetry' 'MetricsReportingEnabled' 0 'Usage and crash reports' 'Stops sending usage statistics and crash reports to Google.'
    S 'Telemetry' 'UrlKeyedAnonymizedDataCollectionEnabled' 0 'Make searches and browsing better' 'Stops sending the URLs you visit to Google.'
    S 'Telemetry' 'FeedbackSurveysEnabled' 0 'Feedback surveys' 'Stops Chrome showing feedback surveys.'
    S 'Telemetry' 'UserFeedbackAllowed' 0 'Send feedback' 'Removes the "Send feedback" option.'
    S 'Telemetry' 'SafeBrowsingSurveysEnabled' 0 'Safe Browsing surveys' 'Stops Safe Browsing surveys.'
    S 'Telemetry' 'SpellCheckServiceEnabled' 0 'Enhanced spell check' 'Stops sending typed text to Google for spell check. Basic spell check still works.'
    S 'Clutter' 'PromotionsEnabled' 0 'Promotions' 'Hides Google promotional content.'
    S 'Clutter' 'ShoppingListEnabled' 0 'Shopping features' 'Turns off price tracking and the shopping list.'
    S 'Clutter' 'NTPCardsVisible' 0 'New Tab page cards' 'Hides the cards on the New Tab page.'
    S 'Clutter' 'DefaultBrowserSettingEnabled' 0 'Default browser nag' 'Stops Chrome asking to be the default browser. It can no longer set itself as default.'
    S 'Clutter' 'BackgroundModeEnabled' 0 'Run in background' 'Chrome fully exits when its last window is closed.'
    S 'Optional' 'SearchSuggestEnabled' 0 'Address bar suggestions' 'Stops sending what you type in the address bar to Google. You lose search suggestions.' $false
)

$scale = [Drawing.Graphics]::FromHwnd([IntPtr]::Zero).DpiX / 96
function Px($n) { [int]($n * $scale) }

$form = New-Object Windows.Forms.Form
$form.Text = 'Chrome Policy Tool'
$form.Font = New-Object Drawing.Font('Segoe UI', 9)
$form.Size = New-Object Drawing.Size((Px 1080), (Px 760))
$form.StartPosition = 'CenterScreen'

$info = New-Object Windows.Forms.Label
$info.Text = 'Ticked features get turned off in Google Chrome for everyone on this PC. Hover a row to see its policy name.'
$info.Dock = 'Top'
$info.Height = Px 36
$info.Padding = New-Object Windows.Forms.Padding((Px 8), 0, 0, 0)
$info.TextAlign = 'MiddleLeft'

$list = New-Object Windows.Forms.ListView
$list.View = 'Details'
$list.CheckBoxes = $true
$list.FullRowSelect = $true
$list.ShowItemToolTips = $true
$list.Dock = 'Fill'
[void]$list.Columns.Add('Feature', (Px 240))
[void]$list.Columns.Add('What turning it off does', (Px 600))
[void]$list.Columns.Add('Status on this PC', (Px 160))

$groups = @{}
foreach ($g in @(
        @('AI', 'AI features'),
        @('Telemetry', 'Telemetry'),
        @('Clutter', 'Clutter'),
        @('Optional', 'Optional (not ticked by default)'))) {
    $groups[$g[0]] = New-Object Windows.Forms.ListViewGroup($g[0], $g[1])
    [void]$list.Groups.Add($groups[$g[0]])
}

foreach ($s in $settings) {
    $item = New-Object Windows.Forms.ListViewItem($s.Name)
    [void]$item.SubItems.Add($s.Desc)
    [void]$item.SubItems.Add('')
    $item.Group = $groups[$s.Group]
    $item.Checked = $s.Default
    $item.ToolTipText = "Policy: $($s.Policy) = $($s.Value)"
    $item.Tag = $s
    [void]$list.Items.Add($item)
}

function Update-Status {
    $vals = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
    foreach ($item in $list.Items) {
        $s = $item.Tag
        $v = if ($vals) { $vals.($s.Policy) } else { $null }
        $item.SubItems[2].Text = if ($null -eq $v) { 'Not set' } elseif ($v -eq $s.Value) { 'Turned off' } else { "Set to $v" }
    }
}

function Get-Ticked { @($list.CheckedItems | ForEach-Object { $_.Tag }) }

function Msg($text, $buttons = 'OK', $icon = 'Information') {
    [Windows.Forms.MessageBox]::Show($form, $text, $form.Text, $buttons, $icon)
}

# Gemini Nano weights, several GB, for every user and every Chrome channel
function Get-ModelDirs($root = "$env:SystemDrive\Users") {
    @(Get-ChildItem "$root\*\AppData\Local\Google\Chrome*\User Data\OptGuideOnDeviceModel" -Directory -Force -ErrorAction SilentlyContinue)
}

function Get-Size($dirs) {
    $sum = ($dirs | ForEach-Object { Get-ChildItem $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue } | Measure-Object Length -Sum).Sum
    '{0:N2} GB' -f ($sum / 1GB)
}

function Close-Chrome {
    for ($i = 0; $i -lt 20 -and (Get-Process chrome -ErrorAction SilentlyContinue); $i++) {
        Get-Process chrome -ErrorAction SilentlyContinue | ForEach-Object { [void]$_.CloseMainWindow() }
        Start-Sleep -Milliseconds 500
    }
    Get-Process chrome -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 1
}

$panel = New-Object Windows.Forms.FlowLayoutPanel
$panel.Dock = 'Bottom'
$panel.AutoSize = $true
$panel.Padding = New-Object Windows.Forms.Padding((Px 6))

function Add-Button($text, $onClick) {
    $b = New-Object Windows.Forms.Button
    $b.Text = $text
    $b.AutoSize = $true
    $b.Padding = New-Object Windows.Forms.Padding((Px 6), (Px 2), (Px 6), (Px 2))
    $b.Add_Click({
            try { & $onClick }
            catch { [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Error', 'OK', 'Error') }
        }.GetNewClosure())
    $panel.Controls.Add($b)
}

Add-Button 'Turn off ticked' {
    $ticked = Get-Ticked
    if (-not $ticked) { return }
    if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
    foreach ($s in $ticked) {
        New-ItemProperty -Path $key -Name $s.Policy -Value $s.Value -PropertyType DWord -Force | Out-Null
    }
    Update-Status
    [void](Msg "Turned off $($ticked.Count) feature(s).`n`nRestart Chrome, or open chrome://policy and click Reload policies.")
}
Add-Button 'Restore ticked to Chrome default' {
    $ticked = Get-Ticked
    if (-not $ticked) { return }
    foreach ($s in $ticked) { Remove-ItemProperty -Path $key -Name $s.Policy -ErrorAction SilentlyContinue }
    Update-Status
    [void](Msg "Restored $($ticked.Count) feature(s) to Chrome's default.`n`nRestart Chrome, or open chrome://policy and click Reload policies.")
}
Add-Button 'Delete AI model files' {
    $dirs = Get-ModelDirs
    if (-not $dirs) {
        [void](Msg 'No downloaded Chrome AI model found on this PC. Nothing to delete.')
        return
    }
    $found = "Chrome's on-device AI model takes $(Get-Size $dirs):`n`n" + (($dirs | ForEach-Object FullName) -join "`n")
    if ((Msg "$found`n`nDelete it?" 'YesNo' 'Question') -ne 'Yes') { return }
    if (Get-Process chrome -ErrorAction SilentlyContinue) {
        if ((Msg "Chrome has to be closed first. Close it now?`n`nUnsaved work in open tabs will be lost." 'OKCancel' 'Warning') -ne 'OK') { return }
        Close-Chrome
    }
    foreach ($d in $dirs) { Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    $left = Get-ModelDirs
    $done = if ($left) { "Could not delete:`n`n" + (($left | ForEach-Object FullName) -join "`n") } else { 'Deleted.' }
    if ((Get-ItemProperty -Path $key -ErrorAction SilentlyContinue).GenAILocalFoundationalModelSettings -ne 1) {
        $done += "`n`nChrome will download it again unless ""On-device AI model"" is turned off above."
    }
    [void](Msg $done)
}
Add-Button 'Tick all' { foreach ($i in $list.Items) { $i.Checked = $true } }
Add-Button 'Untick all' { foreach ($i in $list.Items) { $i.Checked = $false } }

$form.Controls.Add($list)
$form.Controls.Add($panel)
$form.Controls.Add($info)
Update-Status
[void]$form.ShowDialog()
