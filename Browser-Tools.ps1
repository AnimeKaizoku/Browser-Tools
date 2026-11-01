# Browser Tools: turn off AI features, telemetry and clutter in Chrome, Edge, Firefox, Zen, Vivaldi, Brave and Helium using Windows policies.
# Run it: right-click this file > Run with PowerShell, or paste into PowerShell:
#   irm https://raw.githubusercontent.com/AnimeKaizoku/Browser-Tools/main/Browser-Tools.ps1 | iex

param([switch]$Elevated)

$url = 'https://raw.githubusercontent.com/AnimeKaizoku/Browser-Tools/main/Browser-Tools.ps1'
$title = 'Browser Tools'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
# the elevated copy runs hidden, so errors have to surface as message boxes
trap {
    [void][Windows.Forms.MessageBox]::Show("$title stopped because of an error:`n`n$_", $title, 'OK', 'Error')
    break
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if ($Elevated) {
        [void][Windows.Forms.MessageBox]::Show('Could not get administrator rights, which are needed to set browser policies.', $title, 'OK', 'Error')
        return
    }
    # a script block literal remembers the file it came from; under "irm | iex" it has none
    $self = {}.File
    $run = if ($self) { "-File `"$self`" -Elevated" } else { "-Command `"& ([scriptblock]::Create((irm '$url'))) -Elevated`"" }
    try { Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden $run" }
    catch { [void][Windows.Forms.MessageBox]::Show('Administrator rights are needed to set browser policies.', $title, 'OK', 'Warning') }
    return
}

Add-Type -Namespace Native -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr w, IntPtr l);
[DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] public static extern int SetWindowTheme(IntPtr hWnd, string app, string idList);
[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hWnd, int attr, ref int value, int size);
'@
[void][Native.Win]::SetProcessDPIAware()
[Windows.Forms.Application]::EnableVisualStyles()

$users = "$env:SystemDrive\Users\*"
$pf = $env:ProgramFiles
$pf86 = ${env:ProgramFiles(x86)}

# Models: on-device AI model folders that "Delete AI model files" removes. Firefox and Zen have none
# because they delete their own models once their AI features are blocked.
# Uses: the settings list a browser shares with another one (Zen runs Firefox's policy engine).
$browsers = @(
    [pscustomobject]@{
        Name    = 'Chrome'
        Key     = 'HKLM:\SOFTWARE\Policies\Google\Chrome'
        Process = 'chrome'
        Exes    = @("$pf\Google\Chrome\Application\chrome.exe", "$pf86\Google\Chrome\Application\chrome.exe", "$users\AppData\Local\Google\Chrome\Application\chrome.exe")
        # Gemini Nano weights, several GB, for every user and every Chrome channel
        Models  = @("$users\AppData\Local\Google\Chrome*\User Data\OptGuideOnDeviceModel")
    }
    [pscustomobject]@{
        Name    = 'Edge'
        Key     = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
        Process = 'msedge'
        Exes    = @("$pf86\Microsoft\Edge\Application\msedge.exe", "$pf\Microsoft\Edge\Application\msedge.exe")
        # Phi on-device model, several GB
        Models  = @("$users\AppData\Local\Microsoft\Edge*\User Data\EdgeLLMOnDeviceModel")
    }
    [pscustomobject]@{
        Name    = 'Firefox'
        Key     = 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox'
        Process = 'firefox'
        Exes    = @("$pf\Mozilla Firefox\firefox.exe", "$pf86\Mozilla Firefox\firefox.exe", "$pf\Firefox Developer Edition\firefox.exe", "$pf\Firefox Nightly\firefox.exe", "$users\AppData\Local\Mozilla Firefox\firefox.exe")
    }
    [pscustomobject]@{
        Name    = 'Zen'
        Key     = 'HKLM:\SOFTWARE\Policies\Mozilla\Zen'
        Process = 'zen'
        Exes    = @("$pf\Zen Browser\zen.exe", "$pf\Zen Twilight\zen.exe", "$users\AppData\Local\Zen Browser\zen.exe")
        Uses    = 'Firefox'
    }
    [pscustomobject]@{
        Name    = 'Vivaldi'
        Key     = 'HKLM:\SOFTWARE\Policies\Vivaldi'
        Process = 'vivaldi'
        Exes    = @("$pf\Vivaldi\Application\vivaldi.exe", "$users\AppData\Local\Vivaldi\Application\vivaldi.exe")
        Models  = @("$users\AppData\Local\Vivaldi\User Data\OptGuideOnDeviceModel")
    }
    [pscustomobject]@{
        Name    = 'Brave'
        Key     = 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave'
        Process = 'brave'
        # Brave-Browser* also finds Beta and Nightly, which read the same policy key
        Exes    = @("$pf\BraveSoftware\Brave-Browser*\Application\brave.exe", "$pf86\BraveSoftware\Brave-Browser*\Application\brave.exe", "$users\AppData\Local\BraveSoftware\Brave-Browser*\Application\brave.exe")
        Models  = @("$users\AppData\Local\BraveSoftware\Brave-Browser*\User Data\OptGuideOnDeviceModel")
    }
    [pscustomobject]@{
        Name    = 'Helium'
        Key     = 'HKLM:\SOFTWARE\Policies\Helium'
        # Helium keeps Chromium's chrome.exe name; Brand is its file description, which Get-Running uses to tell it apart from Chrome
        Process = 'chrome'
        Brand   = 'Helium'
        Exes    = @("$pf\imput\Helium\Application\chrome.exe", "$users\AppData\Local\imput\Helium\Application\chrome.exe")
        Models  = @("$users\AppData\Local\imput\Helium\User Data\OptGuideOnDeviceModel")
    }
)

# "Subkey\ValueName" (or just "ValueName") -> Id, Sub, Prop
function Split-Id($id) {
    $cut = $id.LastIndexOf('\')
    [pscustomobject]@{ Id = $id; Sub = $(if ($cut -ge 0) { $id.Substring(0, $cut) } else { '' }); Prop = $id.Substring($cut + 1) }
}

$settings = New-Object Collections.ArrayList
# $set maps "ValueName" or "Subkey\ValueName" to the value that turns the feature off (int = DWORD, string = REG_SZ).
# $prefs maps Firefox pref names to locked values written into the Preferences policy.
# $legacy lists old value names this setting replaces; they are removed on apply and restore.
function S($browser, $group, $name, $desc, $set, $prefs, $default = $true, $legacy = @()) {
    $values = foreach ($id in $set.Keys) {
        Split-Id $id |
            Add-Member -NotePropertyName Value -NotePropertyValue $set[$id] -PassThru |
            Add-Member -NotePropertyName Type -NotePropertyValue $(if ($set[$id] -is [string]) { 'String' } else { 'DWord' }) -PassThru
    }
    $prefList = if ($prefs) { foreach ($p in $prefs.Keys) { [pscustomobject]@{ Name = $p; Value = $prefs[$p] } } }
    [void]$settings.Add([pscustomobject]@{
            Browser = $browser; Group = $group; Name = $name; Desc = $desc; Default = $default
            Values  = @($values); Prefs = @($prefList); Legacy = @($legacy)
        })
}

# Firefox (and Zen) settings. Every policy subkey also gets Locked = 1 so users cannot change it in Settings.
function F($group, $name, $desc, $set, $prefs, $default = $true) {
    $all = $set.Clone()
    foreach ($id in $set.Keys) {
        $sub = (Split-Id $id).Sub
        if ($sub) { $all["$sub\Locked"] = 1 }
    }
    S Firefox $group $name $desc $all $prefs $default
}

# Values the browsers themselves report as obsolete, deprecated or overridden by a newer policy.
# "Clean up old policies" offers to remove the ones it finds. Never list a value a setting above writes.
$chromiumOld = [ordered]@{
    PrivacySandboxPromptEnabled         = 'Deprecated: Chrome no longer shows the Privacy Sandbox prompt.'
    PrivacySandboxAdTopicsEnabled       = 'Deprecated in Chrome 144 together with the Topics API.'
    PrivacySandboxSiteEnabledAdsEnabled = 'Deprecated in Chrome 144 together with the Protected Audience API.'
    PrivacySandboxAdMeasurementEnabled  = 'Deprecated in Chrome 144 together with the Attribution Reporting API.'
    PromotionalTabsEnabled              = 'Deprecated: replaced by PromotionsEnabled ("Promotions").'
    LensOverlaySettings                 = 'Deprecated: replaced by "Ask Google about this page and Lens".'
    LensRegionSearchEnabled             = 'Deprecated: replaced by "Ask Google about this page and Lens".'
    LensDesktopNTPSearchEnabled         = 'Deprecated: replaced by "Ask Google about this page and Lens".'
}
$oldPolicies = @{
    Chrome  = $chromiumOld
    Vivaldi = $chromiumOld
    Brave   = $chromiumOld
    Helium  = $chromiumOld
    Edge    = [ordered]@{
        MetricsReportingEnabled    = 'Obsolete: Edge ignores it. "Diagnostic data" replaces it.'
        WebWidgetAllowed           = 'Deprecated: replaced by "Desktop search bar" (SearchbarAllowed).'
        DiscoverPageContextEnabled = 'Obsolete: Edge ignores it.'
        CopilotCDPPageContext      = 'Obsolete: Edge ignores it.'
        EdgeCollectionsEnabled     = 'Obsolete: Collections was removed from Edge.'
        EdgeFollowEnabled          = 'Obsolete: Edge ignores it.'
        AutomaticHttpsDefault      = 'Obsolete: Edge ignores it.'
        NewPDFReaderEnabled        = 'Deprecated.'
        EdgeWalletCheckoutEnabled  = 'Deprecated: Wallet checkout was retired.'
        WalletDonationEnabled      = 'Deprecated: Wallet donations were retired.'
        AllowGamesMenu             = 'Deprecated: the games menu was retired.'
    }
    Firefox = [ordered]@{
        'UserMessaging\WhatsNew' = 'Deprecated: the What''s New icon no longer exists.'
        'FirefoxHome\Snippets'   = 'Deprecated: snippets were removed in Firefox 122.'
    }
}

# ---------------- Chrome ----------------
S Chrome AI 'Ask Google about this page and Lens' 'Hides "Ask Google about this page" and Google Lens, and stops sharing page content with AI Mode and Lens.' @{ SearchContentSharingSettings = 1 } -legacy @('LensOverlaySettings', 'LensRegionSearchEnabled', 'LensDesktopNTPSearchEnabled')
S Chrome AI 'AI Mode' 'Removes AI Mode from the address bar and the New Tab search box.' @{ AIModeSettings = 1 }
S Chrome AI 'Third-party AI chat' 'Blocks other companies'' AI chat in the address bar and New Tab search box.' @{ ThirdPartyAiChatSettings = 1 }
S Chrome AI 'Gemini in Chrome' 'Turns off the Gemini assistant built into Chrome.' @{ GeminiSettings = 1 }
S Chrome AI 'Gemini acting on pages' 'Stops Gemini from clicking and typing on web pages for you.' @{ GeminiActOnWebSettings = 1 }
S Chrome AI 'Gemini Spark' 'Stops Gemini Spark connecting to Chrome and browsing automatically.' @{ GeminiSparkSettings = 1 }
S Chrome AI 'Gemini file uploads' 'Blocks uploading files to Gemini in Chrome.' @{ GeminiChromeFileUploadSettings = 1 }
S Chrome AI 'On-device AI model' 'Stops Chrome downloading its on-device AI model and deletes it if already downloaded.' @{ GenAILocalFoundationalModelSettings = 1 }
S Chrome AI 'Built-in AI for websites' 'Stops websites using Chrome''s built-in AI (summarizer, prompt APIs).' @{ BuiltInAIAPIsEnabled = 0 }
S Chrome AI 'Help me write' 'Removes the AI writing helper from text boxes.' @{ HelpMeWriteSettings = 2 }
S Chrome AI 'Tab compare' 'Turns off AI comparison of products across tabs.' @{ TabCompareSettings = 2 }
S Chrome AI 'AI in Autofill' 'Turns off generative AI features in Autofill.' @{ AutofillGenAiSettings = 2 }
S Chrome AI 'AI in DevTools' 'Turns off AI assistance in Chrome DevTools.' @{ DevToolsGenAiSettings = 2 }
S Chrome AI 'Search this page side panel' 'Removes the Google "Search this page" side panel.' @{ GoogleSearchSidePanelEnabled = 0 }
S Chrome AI 'AI history search (old)' 'AI-powered history search. Only matters on Chrome 156 and older.' @{ HistorySearchSettings = 2 }
S Chrome AI 'Enhanced autofill (old)' 'Older AI autofill switch. Only matters on Chrome 156 and older.' @{ AutofillPredictionSettings = 2 }
S Chrome AI 'Default for all AI features' 'Blocks AI features by default. Only works on cloud-managed browsers.' @{ GenAiDefaultSettings = 2 }
S Chrome Telemetry 'Usage and crash reports' 'Stops usage and crash reports. Chrome only obeys this on work-managed PCs; at home, also untick it in Chrome settings.' @{ MetricsReportingEnabled = 0 }
S Chrome Telemetry 'Make searches and browsing better' 'Stops sending the URLs you visit to Google.' @{ UrlKeyedAnonymizedDataCollectionEnabled = 0 }
S Chrome Telemetry 'Feedback surveys' 'Stops Chrome showing feedback surveys.' @{ FeedbackSurveysEnabled = 0 }
S Chrome Telemetry 'Send feedback' 'Removes the "Send feedback" option.' @{ UserFeedbackAllowed = 0 }
S Chrome Telemetry 'Safe Browsing surveys' 'Stops Safe Browsing surveys.' @{ SafeBrowsingSurveysEnabled = 0 }
S Chrome Telemetry 'Enhanced spell check' 'Stops sending typed text to Google for spell check. Basic spell check still works.' @{ SpellCheckServiceEnabled = 0 }
S Chrome Privacy 'Keep encrypted DNS on' 'Chrome turns off its automatic encrypted DNS once any policy is set. This turns it back on.' @{ DnsOverHttpsMode = 'automatic' }
S Chrome Privacy 'Saved card checks' 'Stops websites checking whether you have saved payment cards.' @{ PaymentMethodQueryEnabled = 0 }
S Chrome Clutter 'Promotions' 'Hides Google promotional content.' @{ PromotionsEnabled = 0 }
S Chrome Clutter 'Shopping features' 'Turns off price tracking and the shopping list.' @{ ShoppingListEnabled = 0 }
S Chrome Clutter 'New Tab page cards' 'Hides the cards on the New Tab page.' @{ NTPCardsVisible = 0 }
S Chrome Clutter 'Default browser nag' 'Stops Chrome asking to be the default browser. It can no longer set itself as default.' @{ DefaultBrowserSettingEnabled = 0 }
S Chrome Clutter 'Run in background' 'Chrome fully exits when its last window is closed.' @{ BackgroundModeEnabled = 0 }
S Chrome Clutter 'Separate profile bubble' 'Stops the "continue in a separate profile?" bubble when you sign in to a Google account on the web.' @{ SigninInterceptionEnabled = 0 }
S Chrome Optional 'Address bar suggestions' 'Stops sending what you type in the address bar to Google, and removes Google''s list of your recent searches when you click it. You lose search suggestions.' @{ SearchSuggestEnabled = 0 } -default $false
S Chrome Optional 'Experiments' 'Stops Chrome downloading feature experiments. Critical fixes still arrive.' @{ ChromeVariations = 1 } -default $false
S Chrome Optional 'Memory Saver' 'Frees memory from tabs you are not using. They reload when you go back to them.' @{ HighEfficiencyModeEnabled = 1; MemorySaverModeSavings = 1 } -default $false
S Chrome Optional 'Background timer throttling' 'Slows timers in background tabs to once a minute after 5 minutes, saving CPU and battery. Alerts from web apps in background tabs can arrive late.' @{ IntensiveWakeUpThrottlingEnabled = 1 } -default $false
S Chrome Optional 'Hide local IP from WebRTC' 'Stops calls and WebRTC sites seeing your local network address. Call quality may drop on some networks.' @{ WebRtcIPHandling = 'default_public_interface_only' } -default $false
S Chrome Optional 'HTTPS warning' 'Warns before opening a site that cannot use a secure HTTPS connection.' @{ HttpsOnlyMode = 'force_balanced_enabled' } -default $false
S Chrome Optional 'Device access prompts' 'Stops websites asking for USB, HID, serial or Bluetooth devices. Web tools that flash or configure devices stop working.' @{ DefaultWebUsbGuardSetting = 2; DefaultWebHidGuardSetting = 2; DefaultSerialGuardSetting = 2; DefaultWebBluetoothGuardSetting = 2 } -default $false
S Chrome Optional 'Block dangerous downloads' 'Blocks downloads that Safe Browsing flags as malicious, with no way to keep them.' @{ DownloadRestrictions = 4 } -default $false
S Chrome Optional 'Notification prompts' 'Blocks website notifications and the prompts asking to show them.' @{ DefaultNotificationsSetting = 2 } -default $false
S Chrome Optional 'Location prompts' 'Blocks websites from asking for your location.' @{ DefaultGeolocationSetting = 2 } -default $false
S Chrome Optional 'Password manager' 'Turns off the built-in password manager, for people who use a separate one.' @{ PasswordManagerEnabled = 0 } -default $false
S Chrome Optional 'Saved card autofill' 'Stops saving and filling in payment cards.' @{ AutofillSettings = '[{"url_pattern":"*","blocked_types":["payments"]}]' } -default $false

# ---------------- Edge ----------------
S Edge AI 'Sidebar' 'Hides the sidebar. Edge has no policy to remove the Copilot button for personal accounts.' @{ HubsSidebarEnabled = 0 }
S Edge AI 'Standalone sidebar' 'Blocks the detached sidebar that can sit on the desktop.' @{ StandaloneHubsSidebarEnabled = 0 }
S Edge AI 'Copilot in address bar' 'Removes Copilot chat suggestions from the address bar.' @{ CopilotAddressBarSuggestionsEnabled = 0 }
S Edge AI 'Copilot acting for you' 'Stops Copilot taking actions on web pages for you.' @{ CopilotCoworkToolActionsEnabled = 0 }
S Edge AI 'Copilot on New Tab page' 'Removes the Copilot entry points from the New Tab page.' @{ NewTabPageBingChatEnabled = 0 }
S Edge AI 'On-device AI model' 'Stops Edge downloading its on-device AI model and deletes it if already downloaded.' @{ GenAILocalFoundationalModelSettings = 1 }
S Edge AI 'Built-in AI for websites' 'Stops websites using Edge''s built-in AI (prompt, summarizer, writer APIs).' @{ BuiltInAIAPIsEnabled = 0 }
S Edge AI 'AI history search' 'History search only matches exact words.' @{ EdgeHistoryAISearchEnabled = 0 }
S Edge AI 'AI tab grouping' 'Stops sending tab data to Microsoft for tab group suggestions.' @{ TabServicesEnabled = 0 }
S Edge AI 'AI-generated themes' 'Turns off AI-generated browser themes.' @{ AIGenThemesEnabled = 0 }
S Edge AI 'Remix' 'Removes the Copilot Remix feature from the toolbar.' @{ RemixAvailability = 0 }
S Edge AI 'AI autofill' 'Turns off cloud machine-learning autofill suggestions. Normal autofill still works.' @{ EdgeAutofillMlEnabled = 0 }
S Edge AI 'Copilot icon (work accounts)' 'Removes the Microsoft 365 Copilot Chat icon. Only applies to work or school profiles.' @{ Microsoft365CopilotChatIconEnabled = 0 }
S Edge AI 'Copilot reading pages (work accounts)' 'Stops Copilot reading page content, history and video transcripts. Only applies to work or school profiles.' @{ CopilotPageContext = 0; EdgeEntraCopilotPageContext = 0 }
S Edge AI 'Copilot New Tab page (work accounts)' 'Turns off the Copilot New Tab page. Only applies to work or school profiles.' @{ CopilotNewTabPageEnabled = 0 }
S Edge AI 'Browsing with Copilot (work accounts)' 'Turns off Copilot agent browsing. Only applies to work or school profiles.' @{ AllowBrowsingWithCopilot = 0 }
S Edge AI 'Rewrite and Compose (work accounts)' 'Turns off AI writing help. Only applies to work or school profiles.' @{ ComposeInlineEnabled = 0 }
S Edge Telemetry 'Diagnostic data' 'Stops sending diagnostic data to Microsoft.' @{ DiagnosticData = 0 }
S Edge Telemetry 'URLs in diagnostic data' 'Stops including visited URLs in diagnostic data.' @{ UrlDiagnosticDataEnabled = 0 }
S Edge Telemetry 'Personalization reporting' 'Stops sending browsing data to personalize ads, news and search.' @{ PersonalizationReportingEnabled = 0 }
S Edge Telemetry 'Send feedback' 'Removes the Send feedback tool.' @{ UserFeedbackAllowed = 0 }
S Edge Telemetry 'Search page telemetry' 'Stops telemetry on other search engines'' result pages.' @{ Edge3PSerpTelemetryEnabled = 0 }
S Edge Telemetry 'Experiments' 'Stops Edge downloading feature experiments. Configuration fixes still arrive.' @{ ExperimentationAndConfigurationServiceControl = 1 }
S Edge Privacy 'Keep encrypted DNS on' 'Edge turns off its automatic encrypted DNS once any policy is set. This turns it back on.' @{ DnsOverHttpsMode = 'automatic' }
S Edge Privacy 'Saved card checks' 'Stops websites checking whether you have saved payment cards.' @{ PaymentMethodQueryEnabled = 0 }
S Edge Clutter 'New Tab news feed' 'Removes the MSN news feed from the New Tab page.' @{ NewTabPageContentEnabled = 0 }
S Edge Clutter 'Sponsored New Tab tiles' 'Hides the default sponsored tiles on the New Tab page.' @{ NewTabPageHideDefaultTopSites = 1 }
S Edge Clutter 'Microsoft 365 app launcher' 'Hides the app launcher on the New Tab page.' @{ NewTabPageAppLauncherEnabled = 0 }
S Edge Clutter 'Bing image of the day' 'Turns off the daily Bing background on the New Tab page.' @{ NewTabPageAllowedBackgroundTypes = 1 }
S Edge Clutter 'Trending searches' 'Removes Bing trending searches from the address bar.' @{ AddressBarTrendingSuggestEnabled = 0 }
S Edge Clutter 'Microsoft Rewards' 'Hides Microsoft Rewards and its notifications.' @{ ShowMicrosoftRewards = 0 }
S Edge Clutter 'Spotlight and tips' 'Turns off Spotlight backgrounds, tips and suggestions.' @{ SpotlightExperiencesAndRecommendationsEnabled = 0 }
S Edge Clutter 'Recommendations' 'Stops feature recommendations and browser assistance pop-ups.' @{ ShowRecommendationsEnabled = 0 }
S Edge Clutter 'Shopping' 'Turns off price comparison, coupon and cashback pop-ups.' @{ EdgeShoppingAssistantEnabled = 0 }
S Edge Clutter 'Startup boost' 'Stops Edge preloading when Windows starts.' @{ StartupBoostEnabled = 0 }
S Edge Clutter 'Run in background' 'Edge fully exits when its last window is closed.' @{ BackgroundModeEnabled = 0 }
S Edge Clutter 'Open at Windows startup' 'Stops Edge opening by itself when Windows starts.' @{ LaunchEdgeOnWindowsStartupEnabled = 0 }
S Edge Clutter 'Default browser nag' 'Stops Edge asking to be the default browser. It can no longer set itself as default.' @{ DefaultBrowserSettingEnabled = 0 }
S Edge Clutter 'Default browser and Bing prompts' 'Stops campaigns asking to make Edge the default browser or Bing the default search.' @{ DefaultBrowserSettingsCampaignEnabled = 0 }
S Edge Clutter 'Default PDF reader prompts' 'Stops prompts to make Edge the default PDF reader.' @{ ShowPDFDefaultRecommendationsEnabled = 0 }
S Edge Clutter 'Pin to taskbar prompt' 'Stops the wizard asking to pin Edge to the taskbar.' @{ PinningWizardAllowed = 0 }
S Edge Clutter 'First-run screens' 'Skips the first-run welcome screens.' @{ HideFirstRunExperience = 1 }
S Edge Clutter 'Insider promotion' 'Hides the Edge Insider promotion on the About page.' @{ MicrosoftEdgeInsiderPromotionEnabled = 0 }
S Edge Clutter 'Adobe Acrobat button' 'Hides the Acrobat subscription button in the PDF viewer.' @{ ShowAcrobatSubscriptionButton = 0 }
S Edge Clutter 'Surf game' 'Turns off the edge://surf game.' @{ AllowSurfGame = 0 }
S Edge Clutter 'Desktop search bar' 'Turns off the Edge search bar on the desktop.' @{ SearchbarAllowed = 0 }
S Edge Clutter 'Text selection menu' 'Stops the mini menu popping up when you select text.' @{ QuickSearchShowMiniMenu = 0 }
S Edge Clutter 'Visual search' 'Removes Bing visual search from images.' @{ VisualSearchEnabled = 0 }
S Edge Clutter 'Search in sidebar' 'Stops search results opening in the sidebar.' @{ SearchInSidebarEnabled = 2 }
S Edge Clutter 'Promotional tabs (old)' 'Stops full-tab promotions. Only matters on older Edge versions.' @{ PromotionalTabsEnabled = 0 }
S Edge Clutter 'Sign in to Edge prompt' 'Stops the "sign in to Edge" prompt after you sign in on a Microsoft website.' @{ WebToBrowserSignInEnabled = 0 }
S Edge Clutter 'Browser essentials button' 'Unpins the Browser essentials button. It still appears when there is an alert.' @{ PinBrowserEssentialsToolbarButton = 0 }
S Edge Optional 'Address bar suggestions' 'Stops sending what you type in the address bar to Bing. You lose search suggestions.' @{ SearchSuggestEnabled = 0 } -default $false
S Edge Optional 'Microsoft Editor spell check' 'Spell check runs on your PC only. You lose grammar suggestions.' @{ MicrosoftEditorProofingEnabled = 0 } -default $false
S Edge Optional 'Share with Windows Search' 'Stops sharing browsing data with Windows Search.' @{ LocalBrowserDataShareEnabled = 0 } -default $false
S Edge Optional 'Online error help' 'Network errors and missing pages are handled without asking Microsoft.' @{ ResolveNavigationErrorsUseWebService = 0; AlternateErrorPagesEnabled = 0 } -default $false
S Edge Optional 'New Tab quick links' 'Hides all quick links on the New Tab page, including your own.' @{ NewTabPageQuickLinksEnabled = 0 } -default $false
S Edge Optional 'Live video translation' 'Turns off on-device live video translation.' @{ LiveVideoTranslationEnabled = 0 } -default $false
S Edge Optional 'Drop' 'Turns off Drop file and note sharing between your devices.' @{ EdgeEDropEnabled = 0 } -default $false
S Edge Optional 'Sleeping tabs after 5 minutes' 'Puts tabs you have not used for 5 minutes to sleep to save memory.' @{ SleepingTabsEnabled = 1; SleepingTabsTimeout = 300 } -default $false
S Edge Optional 'Background timer throttling' 'Slows timers in background tabs to once a minute after 5 minutes, saving CPU and battery. Alerts from web apps in background tabs can arrive late.' @{ IntensiveWakeUpThrottlingEnabled = 1 } -default $false
S Edge Optional 'Hide local IP from WebRTC' 'Stops calls and WebRTC sites seeing your local network address. Call quality may drop on some networks.' @{ WebRtcLocalhostIpHandling = 'default_public_interface_only' } -default $false
S Edge Optional 'Strict tracking prevention' 'Blocks most trackers across sites. Some sites may not work properly.' @{ TrackingPrevention = 3 } -default $false
S Edge Optional 'Automatic Microsoft sign-in' 'Stops Edge silently signing you in to Bing, MSN and Copilot. You sign in yourself when you want to.' @{ ProactiveAuthWorkflowEnabled = 0 } -default $false
S Edge Optional 'HTTPS warning' 'Warns before opening a site that cannot use a secure HTTPS connection.' @{ HttpsOnlyMode = 'force_balanced_enabled' } -default $false
S Edge Optional 'Device access prompts' 'Stops websites asking for USB, HID, serial or Bluetooth devices. Web tools that flash or configure devices stop working.' @{ DefaultWebUsbGuardSetting = 2; DefaultWebHidGuardSetting = 2; DefaultSerialGuardSetting = 2; DefaultWebBluetoothGuardSetting = 2 } -default $false
S Edge Optional 'Block dangerous downloads' 'Blocks downloads that Safe Browsing flags as malicious, with no way to keep them.' @{ DownloadRestrictions = 4 } -default $false
S Edge Optional 'Notification prompts' 'Blocks website notifications and the prompts asking to show them.' @{ DefaultNotificationsSetting = 2 } -default $false
S Edge Optional 'Location prompts' 'Blocks websites from asking for your location.' @{ DefaultGeolocationSetting = 2 } -default $false
S Edge Optional 'Password manager' 'Turns off the built-in password manager, for people who use a separate one.' @{ PasswordManagerEnabled = 0 } -default $false
S Edge Optional 'Saved card autofill' 'Stops saving and filling in payment cards.' @{ AutofillCreditCardEnabled = 0 } -default $false

# ---------------- Vivaldi ----------------
# Vivaldi reads Chromium policies from its own key, but only officially supports them from 8.3
S Vivaldi Telemetry 'Make searches and browsing better' 'Stops sending the URLs you visit to improve browsing.' @{ UrlKeyedAnonymizedDataCollectionEnabled = 0 }
S Vivaldi Telemetry 'Enhanced spell check' 'Uses only the local spell checker, not the web spelling service.' @{ SpellCheckServiceEnabled = 0 }
S Vivaldi Clutter 'Direct Match' 'Turns off sponsored Direct Match suggestions in the address bar.' @{ VivaldiDirectMatchEnabled = 0 }
S Vivaldi Clutter 'Promotions' 'Hides promotional content.' @{ PromotionsEnabled = 0 }
S Vivaldi Optional 'Built-in VPN' 'Hides the built-in Proton VPN.' @{ VivaldiVPNEnabled = 0 } -default $false
S Vivaldi Optional 'Online error help' 'Stops using a web service to suggest pages when a site fails to load.' @{ AlternateErrorPagesEnabled = 0 } -default $false
S Vivaldi Optional 'Hide local IP from WebRTC' 'Stops calls and WebRTC sites seeing your local network address. Call quality may drop on some networks.' @{ WebRtcIPHandling = 'default_public_interface_only' } -default $false
S Vivaldi Optional 'HTTPS warning' 'Warns before opening a site that cannot use a secure HTTPS connection.' @{ HttpsOnlyMode = 'force_balanced_enabled' } -default $false
S Vivaldi Optional 'Password manager' 'Turns off the built-in password manager, for people who use a separate one.' @{ PasswordManagerEnabled = 0 } -default $false

# ---------------- Helium ----------------
# Helium is built on ungoogled-chromium, which already strips Google AI, telemetry and sign-in.
# It reads Chromium policies from its own key. It already hides the local IP from WebRTC and has no password manager.
S Helium Optional 'Memory Saver' 'Frees memory from tabs you are not using. They reload when you go back to them.' @{ HighEfficiencyModeEnabled = 1; MemorySaverModeSavings = 1 } -default $false
S Helium Optional 'HTTPS warning' 'Warns before opening a site that cannot use a secure HTTPS connection.' @{ HttpsOnlyMode = 'force_balanced_enabled' } -default $false

# ---------------- Brave ----------------
S Brave AI 'Leo AI assistant' 'Turns off Leo, Brave''s AI chat in the sidebar, address bar and right-click menu.' @{ BraveAIChatEnabled = 0 }
S Brave AI 'Local AI' 'Turns off Brave''s on-device AI features, such as AI history search.' @{ BraveLocalAIEnabled = 0 }
S Brave Telemetry 'Product analytics (P3A)' 'Stops sending Brave anonymous usage statistics.' @{ BraveP3AEnabled = 0 }
S Brave Telemetry 'Usage ping' 'Stops the daily ping Brave uses to count active users.' @{ BraveStatsPingEnabled = 0 }
S Brave Telemetry 'Web Discovery' 'Stops contributing browsing data to Brave Search''s index. It is off unless you opted in; this keeps it off.' @{ BraveWebDiscoveryEnabled = 0 }
S Brave Telemetry 'Crash reports' 'Stops sending crash reports to Brave.' @{ MetricsReportingEnabled = 0 }
S Brave Clutter 'Rewards and Brave Ads' 'Turns off Brave Rewards, its ads and the BAT counter in the toolbar.' @{ BraveRewardsDisabled = 1 }
S Brave Clutter 'Crypto wallet' 'Turns off the built-in crypto wallet and its prompts on web3 sites.' @{ BraveWalletDisabled = 1 }
S Brave Clutter 'Brave News' 'Removes the news feed from the New Tab page.' @{ BraveNewsDisabled = 1 }
S Brave Clutter 'Brave Talk' 'Removes the Brave Talk video calls entry from the New Tab page.' @{ BraveTalkDisabled = 1 }
S Brave Optional 'Built-in VPN' 'Removes the paid Brave VPN button and its prompts.' @{ BraveVPNDisabled = 1 } -default $false
S Brave Optional 'Tor windows' 'Removes private windows with Tor.' @{ TorDisabled = 1 } -default $false
S Brave Optional 'Playlist' 'Turns off Playlist, which saves videos to watch later.' @{ BravePlaylistEnabled = 0 } -default $false
S Brave Optional 'Speedreader' 'Turns off the reader view for articles.' @{ BraveSpeedreaderEnabled = 0 } -default $false
S Brave Optional 'Wayback Machine' 'Stops offering archived copies of pages that fail to load.' @{ BraveWaybackMachineEnabled = 0 } -default $false
S Brave Optional 'Email aliases' 'Turns off creating email aliases for sign-up forms.' @{ EmailAliasesEnabled = 0 } -default $false
S Brave Optional 'Memory Saver' 'Frees memory from tabs you are not using. They reload when you go back to them.' @{ HighEfficiencyModeEnabled = 1; MemorySaverModeSavings = 1 } -default $false
S Brave Optional 'Hide local IP from WebRTC' 'Stops calls and WebRTC sites seeing your local network address. Call quality may drop on some networks.' @{ WebRtcIPHandling = 'default_public_interface_only' } -default $false
S Brave Optional 'Password manager' 'Turns off the built-in password manager, for people who use a separate one.' @{ PasswordManagerEnabled = 0 } -default $false

# ---------------- Shared by Vivaldi, Brave and Helium ----------------
# Plain Chromium policies; the sections above only list what is specific to each browser
foreach ($n in 'Vivaldi', 'Brave', 'Helium') {
    S $n AI 'On-device AI model' "Makes sure $n never downloads Chromium's on-device AI model, and deletes it if already downloaded." @{ GenAILocalFoundationalModelSettings = 1 }
    S $n AI 'Built-in AI for websites' 'Stops websites using the browser''s built-in AI APIs.' @{ BuiltInAIAPIsEnabled = 0 }
    S $n Privacy 'Keep encrypted DNS on' 'Chromium browsers turn off their automatic encrypted DNS once any policy is set. This keeps it on.' @{ DnsOverHttpsMode = 'automatic' }
    S $n Privacy 'Saved card checks' 'Stops websites checking whether you have saved payment cards.' @{ PaymentMethodQueryEnabled = 0 }
    S $n Clutter 'Default browser nag' "Stops $n asking to be the default browser. It can no longer set itself as default." @{ DefaultBrowserSettingEnabled = 0 }
    S $n Clutter 'Run in background' "$n fully exits when its last window is closed." @{ BackgroundModeEnabled = 0 }
    S $n Optional 'Address bar suggestions' 'Stops sending what you type in the address bar to your search engine. You lose search suggestions.' @{ SearchSuggestEnabled = 0 } -default $false
    S $n Optional 'Preloading' 'Turns off preloading pages. Pages may load a little slower.' @{ NetworkPredictionOptions = 2 } -default $false
    S $n Optional 'Background timer throttling' 'Slows timers in background tabs to once a minute after 5 minutes, saving CPU and battery. Alerts from web apps in background tabs can arrive late.' @{ IntensiveWakeUpThrottlingEnabled = 1 } -default $false
    S $n Optional 'Device access prompts' 'Stops websites asking for USB, HID, serial or Bluetooth devices. Web tools that flash or configure devices stop working.' @{ DefaultWebUsbGuardSetting = 2; DefaultWebHidGuardSetting = 2; DefaultSerialGuardSetting = 2; DefaultWebBluetoothGuardSetting = 2 } -default $false
    S $n Optional 'Notification prompts' 'Blocks website notifications and the prompts asking to show them.' @{ DefaultNotificationsSetting = 2 } -default $false
    S $n Optional 'Location prompts' 'Blocks websites from asking for your location.' @{ DefaultGeolocationSetting = 2 } -default $false
    # AutofillSettings replaces AutofillCreditCardEnabled in newer Chromium; each browser ignores the one it does not know
    S $n Optional 'Saved card autofill' 'Stops saving and filling in payment cards.' @{ AutofillSettings = '[{"url_pattern":"*","blocked_types":["payments"]}]'; AutofillCreditCardEnabled = 0 } -default $false
}

# ---------------- Firefox and Zen ----------------
# AIControls is Firefox 149 and newer, GenerativeAI covers 144 to 149
F AI 'AI chatbot' 'Removes the AI chatbot sidebar, menu and shortcuts.' @{ 'AIControls\SidebarChatbot\Value' = 'blocked'; 'GenerativeAI\Chatbot' = 0 } @{ 'browser.ml.chat.enabled' = $false; 'browser.ml.chat.menu' = $false; 'browser.ml.chat.shortcuts' = $false; 'browser.ml.chat.sidebar' = $false }
F AI 'Link previews' 'Turns off AI link previews and key points.' @{ 'AIControls\LinkPreviewKeyPoints\Value' = 'blocked'; 'GenerativeAI\LinkPreviews' = 0 }
F AI 'Smart tab groups' 'Turns off AI tab grouping and group name suggestions.' @{ 'AIControls\SmartTabGroups\Value' = 'blocked'; 'GenerativeAI\TabGroups' = 0 } @{ 'browser.tabs.groups.smart.enabled' = $false }
F AI 'Smart Window' 'Turns off the AI Smart Window.' @{ 'AIControls\SmartWindow\Value' = 'blocked'; 'GenerativeAI\SmartWindow' = 0 } @{ 'browser.smartwindow.enabled' = $false }
F AI 'PDF alt text' 'Stops generating image descriptions in PDFs and downloading the model for it.' @{ 'AIControls\PDFAltText\Value' = 'blocked' } @{ 'pdfjs.enableAltTextModelDownload' = $false; 'pdfjs.enableGuessAltText' = $false }
F AI 'Speech recognition' 'Turns off on-device AI speech recognition.' @{ 'AIControls\SpeechRecognition\Value' = 'blocked' }
F AI 'AI engine' 'Turns off the on-device machine learning engine that the AI features use.' @{ 'GenerativeAI\Enabled' = 0 } @{ 'browser.ml.enable' = $false }
F AI 'AI for extensions' 'Stops extensions using Firefox''s AI and downloading models.' @{} @{ 'extensions.ml.enabled' = $false }
F AI 'AI history search' 'Turns off AI search of your history.' @{} @{ 'places.semanticHistory.featureGate' = $false }
F Telemetry 'Telemetry' 'Stops sending usage and technical data to Mozilla.' @{ DisableTelemetry = 1 }
F Telemetry 'Studies' 'Stops Mozilla running studies and experiments in your browser.' @{ DisableFirefoxStudies = 1 }
F Telemetry 'Address bar data' 'Stops sending what you type in the address bar to Mozilla.' @{ 'FirefoxSuggest\ImproveSuggest' = 0; 'FirefoxSuggest\OnlineEnabled' = 0 }
F Telemetry 'Default browser agent' 'Stops the background task that reports default browser info.' @{ DisableDefaultBrowserAgent = 1 }
F Telemetry 'New Tab telemetry' 'Stops sending New Tab page usage data.' @{} @{ 'browser.newtabpage.activity-stream.telemetry' = $false; 'browser.newtabpage.activity-stream.feeds.telemetry' = $false }
F Telemetry 'Personalized recommendations' 'Stops personalized extension recommendations.' @{} @{ 'browser.discovery.enabled' = $false }
F Telemetry 'Feedback commands' 'Removes the Submit Feedback and Report Deceptive Site menu items.' @{ DisableFeedbackCommands = 1 }
F Privacy 'Global Privacy Control' 'Tells every website not to sell or share your data.' @{} @{ 'privacy.globalprivacycontrol.enabled' = $true }
F Clutter 'Sponsored shortcuts' 'Removes sponsored shortcuts from the New Tab page.' @{ 'FirefoxHome\SponsoredTopSites' = 0 }
F Clutter 'Sponsored stories' 'Removes sponsored stories from the New Tab page.' @{ 'FirefoxHome\SponsoredStories' = 0; 'FirefoxHome\SponsoredPocket' = 0 }
F Clutter 'Sponsored suggestions' 'Removes sponsored suggestions from the address bar.' @{ 'FirefoxSuggest\SponsoredSuggestions' = 0 }
F Clutter 'Extension recommendations' 'Stops recommending extensions while you browse.' @{ 'UserMessaging\ExtensionRecommendations' = 0 }
F Clutter 'Feature recommendations' 'Stops feature recommendation pop-ups.' @{ 'UserMessaging\FeatureRecommendations' = 0 }
F Clutter 'Address bar tips' 'Stops Firefox tips in the address bar.' @{ 'UserMessaging\UrlbarInterventions' = 0 }
F Clutter 'Onboarding' 'Skips the onboarding screens.' @{ 'UserMessaging\SkipOnboarding' = 1 }
F Clutter 'More from Mozilla' 'Hides "More from Mozilla" in Settings.' @{ 'UserMessaging\MoreFromMozilla' = 0 }
F Clutter 'Product promotions' 'Hides VPN and other Mozilla product promotions.' @{} @{ 'browser.vpn_promo.enabled' = $false; 'identity.fxaccounts.toolbar.pxiToolbarEnabled' = $false }
F Clutter 'Built-in VPN' 'Removes the built-in VPN feature and its prompts.' @{ IPProtectionAvailable = 0 }
F Clutter 'Default browser nag' 'Stops asking to be the default browser.' @{ DontCheckDefaultBrowser = 1 }
F Clutter 'Terms of Use pop-up' 'Skips the Terms of Use pop-up at startup.' @{ SkipTermsOfUse = 1 }
F Clutter 'Visual search' 'Removes visual image search from the right-click menu.' @{ VisualSearchEnabled = 0 }
F Clutter 'Pocket (old)' 'Turns off Pocket. Only matters on older versions.' @{ DisablePocket = 1 }
F Clutter 'What''s New tab' 'Stops the What''s New tab opening after updates.' @{ OverridePostUpdatePage = '' }
F Clutter 'Translation pop-up' 'Stops the translation pop-up. The translate button in the address bar stays.' @{} @{ 'browser.translations.automaticallyPopup' = $false }
F Optional 'Translations' 'Turns off page translation. It runs on your PC and sends nothing to Mozilla.' @{ 'AIControls\Translations\Value' = 'blocked'; TranslateEnabled = 0 } -default $false
F Optional 'Block all other AI' 'Blocks every AI feature without its own switch, including future ones and Translations.' @{ 'AIControls\Default\Value' = 'blocked' } -default $false
F Optional 'Address bar suggestions' 'Stops sending what you type in the address bar to your search engine. You lose search suggestions.' @{ SearchSuggestEnabled = 0 } -default $false
F Optional 'Firefox Suggest' 'Turns off Firefox Suggest completely.' @{ 'FirefoxSuggest\WebSuggestions' = 0 } -default $false
F Optional 'Trending searches' 'Removes trending searches from the address bar.' @{} @{ 'browser.urlbar.trending.featureGate' = $false } -default $false
F Optional 'New Tab stories' 'Removes all stories from the New Tab page.' @{ 'FirefoxHome\Stories' = 0; 'FirefoxHome\Pocket' = 0 } -default $false
F Optional 'New Tab weather' 'Removes the weather widget from the New Tab page.' @{ 'FirefoxHome\Weather' = 0 } -default $false
F Optional 'Preloading' 'Turns off DNS prefetch and preconnect. Pages may load a little slower.' @{ NetworkPrediction = 0 } -default $false
F Optional 'Firefox Labs' 'Hides Firefox Labs in Settings.' @{ 'UserMessaging\FirefoxLabs' = 0 } -default $false
F Optional 'Remote feature rollouts' 'Stops Mozilla turning features on between updates. This can also delay some fixes.' @{ DisableRemoteImprovements = 1 } -default $false
F Optional 'Strict tracking protection' 'Forces Strict Enhanced Tracking Protection. Some sites may not work properly.' @{ 'EnableTrackingProtection\Category' = 'strict' } -default $false
F Optional 'HTTPS warning' 'Warns before opening a site that cannot use a secure HTTPS connection.' @{ HttpsOnlyMode = 'enabled' } -default $false
F Optional 'Device access prompts' 'Stops websites asking for serial devices. Web tools that flash or configure devices stop working.' @{ DefaultSerialGuardSetting = 2 } -default $false
F Optional 'Notification prompts' 'Blocks websites from asking to show notifications.' @{ 'Permissions\Notifications\BlockNewRequests' = 1 } -default $false
F Optional 'Location prompts' 'Blocks websites from asking for your location.' @{ 'Permissions\Location\BlockNewRequests' = 1 } -default $false
F Optional 'Downloads panel' 'Stops the downloads panel popping open for every download.' @{} @{ 'browser.download.alwaysOpenPanel' = $false } -default $false
F Optional 'Password manager' 'Turns off the built-in password manager, for people who use a separate one.' @{ PasswordManagerEnabled = 0 } -default $false
F Optional 'Saved card autofill' 'Stops saving and filling in payment cards.' @{ AutofillCreditCardEnabled = 0 } -default $false

$groupTitles = [ordered]@{ AI = 'AI features'; Telemetry = 'Telemetry'; Privacy = 'Privacy'; Clutter = 'Clutter'; Optional = 'Optional (not ticked by default)' }

# ---------------- Registry ----------------
function PathOf($b, $v) { if ($v.Sub) { "$($b.Key)\$($v.Sub)" } else { $b.Key } }

# .NET reads are far cheaper than the registry provider, especially for keys that do not exist
function Read-Key($path) {
    $k = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($path.Substring('HKLM:\'.Length))
    $values = @{}
    if ($k) {
        foreach ($n in $k.GetValueNames()) { $values[$n] = $k.GetValue($n) }
        $k.Close()
    }
    $values
}

# Reads the browser's policies once; subkeys are cached as they are first asked for.
# Prefs is $null when the existing Preferences policy is not valid JSON.
function Read-Policies($b) {
    $root = Read-Key $b.Key
    $prefs = [ordered]@{}
    if ($root.Preferences) {
        try { foreach ($p in (($root.Preferences -join "`n") | ConvertFrom-Json -ErrorAction Stop).PSObject.Properties) { $prefs[$p.Name] = $p.Value } }
        catch { $prefs = $null }
    }
    @{ Cache = @{ $b.Key = $root }; Prefs = $prefs }
}

function Set-Prefs($b, $prefs) {
    if ($prefs.Count) {
        if (-not (Test-Path $b.Key)) { New-Item -Path $b.Key -Force | Out-Null }
        $json = $prefs | ConvertTo-Json -Compress -Depth 5
        New-ItemProperty -Path $b.Key -Name Preferences -PropertyType MultiString -Value @($json) -Force | Out-Null
    }
    else { Remove-ItemProperty -Path $b.Key -Name Preferences -ErrorAction SilentlyContinue }
}

function Get-Status($b, $s, $state) {
    $hits = 0
    $misses = 0
    foreach ($v in $s.Values) {
        # Locked only locks a policy group that several settings share, so it says nothing about this one
        if ($v.Prop -eq 'Locked') { continue }
        $path = PathOf $b $v
        if (-not $state.Cache.Contains($path)) { $state.Cache[$path] = Read-Key $path }
        $values = $state.Cache[$path]
        if ($values.Contains($v.Prop) -and "$($values[$v.Prop])" -eq "$($v.Value)") { $hits++ } else { $misses++ }
    }
    foreach ($p in $s.Prefs) {
        $e = if ($state.Prefs) { $state.Prefs[$p.Name] }
        if ($e -and "$($e.Value)" -eq "$($p.Value)" -and $e.Status -eq 'locked') { $hits++ } else { $misses++ }
    }
    if (-not $misses) { 'Turned off' } elseif ($hits) { 'Partly set' } else { 'Not set' }
}

function Remove-EmptyKeys($b, $path) {
    while ($path -ne $b.Key) {
        $k = Get-Item $path -ErrorAction SilentlyContinue
        if (-not $k -or $k.ValueCount -or $k.SubKeyCount) { break }
        Remove-Item $path
        $path = Split-Path $path
    }
}

# ---------------- UI ----------------
$scale = [Drawing.Graphics]::FromHwnd([IntPtr]::Zero).DpiX / 96
function Px($n) { [int]($n * $scale) }

$form = New-Object Windows.Forms.Form
$form.Text = $title
$form.Font = New-Object Drawing.Font('Segoe UI', 9)
$form.Size = New-Object Drawing.Size((Px 1120), (Px 800))
$form.StartPosition = 'CenterScreen'

function Msg($text, $buttons = 'OK', $icon = 'Information') {
    [Windows.Forms.MessageBox]::Show($form, $text, $title, $buttons, $icon)
}

$info = New-Object Windows.Forms.Label
$info.Text = "Ticked features get turned off for everyone on this PC. Buttons act on the tab you are on. Hover a row to see the policies it sets.`nThe Firefox tab covers Firefox, Developer Edition, ESR and Nightly. Vivaldi only officially supports policies from version 8.3."
$info.Dock = 'Top'
$info.Height = Px 46
$info.Padding = New-Object Windows.Forms.Padding((Px 8), 0, 0, 0)
$info.TextAlign = 'MiddleLeft'

# A row of flat buttons instead of a TabControl, whose tab strip cannot be themed dark
$tabBar = New-Object Windows.Forms.FlowLayoutPanel
$tabBar.Dock = 'Top'
$tabBar.AutoSize = $true
$tabBar.Padding = New-Object Windows.Forms.Padding((Px 6), 0, 0, 0)
$body = New-Object Windows.Forms.Panel
$body.Dock = 'Fill'
$body.Padding = New-Object Windows.Forms.Padding((Px 8), (Px 4), (Px 8), 0)

function Current { $script:current }

function Show-Browser($b) {
    $script:current = $b
    foreach ($x in $browsers) {
        $x.List.Visible = $x -eq $b
        $x.Tab.Checked = $x -eq $b
    }
    Set-TabColors
}

foreach ($b in $browsers) {
    $installed = [bool]($b.Exes | Where-Object { Test-Path $_ })
    $tab = New-Object Windows.Forms.RadioButton
    $tab.Appearance = 'Button'
    $tab.AutoSize = $true
    $tab.FlatStyle = 'Flat'
    $tab.FlatAppearance.BorderSize = 0
    $tab.Padding = New-Object Windows.Forms.Padding((Px 10), (Px 3), (Px 10), (Px 3))
    $tab.Margin = New-Object Windows.Forms.Padding(0, 0, (Px 2), 0)
    $tab.Text = if ($installed) { $b.Name } else { "$($b.Name) (not installed)" }
    $tab.Tag = $b
    $tab.Add_Click({ Show-Browser $this.Tag })
    $tabBar.Controls.Add($tab)

    $list = New-Object Windows.Forms.ListView
    $list.View = 'Details'
    $list.CheckBoxes = $true
    $list.FullRowSelect = $true
    $list.ShowItemToolTips = $true
    $list.Dock = 'Fill'
    [void]$list.Columns.Add('Feature', (Px 260))
    [void]$list.Columns.Add('What turning it off does', (Px 610))
    [void]$list.Columns.Add('Status on this PC', (Px 150))
    # Windows draws rows and group headings; column headings are drawn here so they stay readable in dark mode
    $list.OwnerDraw = $true
    $list.Add_DrawColumnHeader({ param($sender, $e) Draw-Header $e })
    $list.Add_DrawItem({ param($sender, $e) $e.DrawDefault = $true })
    $list.Add_DrawSubItem({ param($sender, $e) $e.DrawDefault = $true })

    $groups = @{}
    foreach ($g in $groupTitles.Keys) {
        $groups[$g] = New-Object Windows.Forms.ListViewGroup($g, $groupTitles[$g])
        [void]$list.Groups.Add($groups[$g])
    }
    $uses = if ($b.Uses) { $b.Uses } else { $b.Name }
    foreach ($s in $settings | Where-Object Browser -eq $uses) {
        $item = New-Object Windows.Forms.ListViewItem($s.Name)
        [void]$item.SubItems.Add($s.Desc)
        [void]$item.SubItems.Add('')
        $item.Group = $groups[$s.Group]
        $item.Checked = $s.Default
        $item.ToolTipText = (@($s.Values | ForEach-Object { "$($_.Id) = $($_.Value)" }) + @($s.Prefs | ForEach-Object { "Preferences: $($_.Name) = $($_.Value)" })) -join "`n"
        $item.Tag = $s
        [void]$list.Items.Add($item)
    }
    $b | Add-Member -NotePropertyName List -NotePropertyValue $list -Force
    $b | Add-Member -NotePropertyName Tab -NotePropertyValue $tab -Force
    $body.Controls.Add($list)
}

function Update-Status($b) {
    $state = Read-Policies $b
    foreach ($item in $b.List.Items) { $item.SubItems[2].Text = Get-Status $b $item.Tag $state }
}

# Turns off ($restore = $false) or restores the ticked settings of the current tab
function Set-Ticked($restore) {
    $b = Current
    $ticked = @($b.List.CheckedItems | ForEach-Object { $_.Tag })
    if (-not $ticked) { return }
    $backupNote = Backup-Policies $b
    $state = Read-Policies $b
    $prefs = $state.Prefs
    # on restore, keep values that another, still applied setting shares (for example GenerativeAI\Locked)
    $keep = @{}
    if ($restore) {
        foreach ($item in $b.List.Items) {
            if ($item.Checked -or (Get-Status $b $item.Tag $state) -eq 'Not set') { continue }
            foreach ($v in $item.Tag.Values) { $keep[$v.Id] = $true }
            foreach ($p in $item.Tag.Prefs) { $keep[$p.Name] = $true }
        }
    }
    $handled = @{}
    $exists = @{}
    $prefsChanged = $false
    $skipped = @()
    foreach ($s in $ticked) {
        foreach ($v in $s.Values) {
            if ($handled[$v.Id] -or $keep[$v.Id]) { continue }
            $handled[$v.Id] = $true
            $path = PathOf $b $v
            if (-not $exists.Contains($path)) { $exists[$path] = Test-Path $path }
            if ($restore) {
                if ($exists[$path]) { Remove-ItemProperty -Path $path -Name $v.Prop -ErrorAction SilentlyContinue }
                continue
            }
            if (-not $exists[$path]) { New-Item -Path $path -Force | Out-Null; $exists[$path] = $true }
            New-ItemProperty -Path $path -Name $v.Prop -Value $v.Value -PropertyType $v.Type -Force | Out-Null
        }
        foreach ($name in $s.Legacy) { Remove-ItemProperty -Path $b.Key -Name $name -ErrorAction SilentlyContinue }
        if (-not $s.Prefs) { continue }
        if ($null -eq $prefs) { $skipped += $s.Name; continue }
        foreach ($p in $s.Prefs) {
            if (-not $restore) { $prefs[$p.Name] = [pscustomobject]@{ Value = $p.Value; Status = 'locked' } }
            elseif ($keep[$p.Name] -or -not $prefs.Contains($p.Name)) { continue }
            else { $prefs.Remove($p.Name) }
            $prefsChanged = $true
        }
    }
    if ($restore) { foreach ($path in @($exists.Keys)) { if ($exists[$path]) { Remove-EmptyKeys $b $path } } }
    if ($prefsChanged) { Set-Prefs $b $prefs }
    Update-Status $b
    $n = $ticked.Count - $skipped.Count
    $did = if ($restore) { "restored $n feature(s) to the browser's default" } else { "turned off $n feature(s)" }
    $note = if ($skipped) { "`n`nThe existing Firefox ""Preferences"" policy is not valid JSON, so it was left untouched and these settings were skipped: $($skipped -join ', ')." }
    [void](Msg "$($b.Name): $did.$note$backupNote`n`nRestart the browser to apply. Chromium browsers can also reload policies from their policy page, such as chrome://policy, edge://policy or brave://policy.")
}

# Saves the browser's policy key to a .reg file before it changes, when the backup box is ticked,
# and returns a note for the confirmation message. The file deletes the key before writing the saved values,
# so importing it also undoes policies added later.
function Backup-Policies($b) {
    if (-not $backup.Checked) { return }
    $dir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "$title backups"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $file = Join-Path $dir ('{0} {1:yyyy-MM-dd HHmmss fff}.reg' -f $b.Name, (Get-Date))
    $key = 'HKEY_LOCAL_MACHINE\' + $b.Key.Substring('HKLM:\'.Length)
    $header = 'Windows Registry Editor Version 5.00'
    $text = if (Test-Path $b.Key) {
        $out = & reg.exe export $key $file /y 2>&1
        if ($LASTEXITCODE) { throw "Could not back up $key, so nothing was changed:`n`n$out" }
        Get-Content $file -Raw
    }
    else { $header }
    Set-Content $file -Encoding Unicode -Value $text.Replace($header, "$header`r`n`r`n[-$key]")
    "`n`nThe policies from before this change were saved to:`n$file`nDouble-click it to go back to them."
}

function Get-ModelDirs($b) { @(Get-ChildItem $b.Models -Directory -Force -ErrorAction SilentlyContinue) }

# Chrome and Helium both run as chrome.exe. A browser with a Brand owns the processes with that file description,
# wherever they were installed; the rest (Chrome, Beta, Canary) belong to the browser without one.
function Get-Running($b) {
    $brands = @($browsers | Where-Object { $_.Process -eq $b.Process -and $_.Brand } | ForEach-Object Brand)
    Get-Process $b.Process -ErrorAction SilentlyContinue | Where-Object {
        if ($b.Brand) { $_.Description -eq $b.Brand } else { $brands -notcontains $_.Description }
    }
}

function Close-Browser($b) {
    for ($i = 0; $i -lt 20; $i++) {
        $running = Get-Running $b
        if (-not $running) { return }
        $running | ForEach-Object { [void]$_.CloseMainWindow() }
        Start-Sleep -Milliseconds 500
    }
    Get-Running $b | Stop-Process -Force
    # a forced exit releases its files in the background
    Start-Sleep -Seconds 1
}

# Old policies (see $oldPolicies) that are set on this PC, skipping any value a setting on the tab writes
function Find-OldPolicies($b) {
    $old = $oldPolicies[$(if ($b.Uses) { $b.Uses } else { $b.Name })]
    if (-not $old) { return }
    $managed = @{}
    foreach ($item in $b.List.Items) { foreach ($v in $item.Tag.Values) { $managed[$v.Id] = $true } }
    foreach ($id in $old.Keys) {
        if ($managed[$id]) { continue }
        $v = Split-Id $id
        $path = PathOf $b $v
        $cur = (Read-Key $path)[$v.Prop]
        if ($null -eq $cur) { continue }
        $v | Add-Member -NotePropertyMembers @{ Path = $path; Current = (@($cur) -join ';'); Why = $old[$id] } -PassThru
    }
}

# A preset is the ticked setting names of every tab, saved as JSON
function Export-Preset($path) {
    $ticks = [ordered]@{}
    foreach ($b in $browsers) { $ticks[$b.Name] = @($b.List.CheckedItems | ForEach-Object { $_.Text }) }
    [ordered]@{ tool = $title; browsers = $ticks } | ConvertTo-Json -Depth 4 | Set-Content -Path $path -Encoding UTF8
}

# Sets the ticks from a preset and returns the browser tabs it covered
function Import-Preset($path) {
    $preset = Get-Content -Path $path -Raw | ConvertFrom-Json
    $loaded = foreach ($b in $browsers) {
        $names = $preset.browsers.($b.Name)
        if ($null -eq $names) { continue }
        foreach ($item in $b.List.Items) { $item.Checked = @($names) -contains $item.Text }
        $b.Name
    }
    if (-not $loaded) { throw "$path is not a $title preset." }
    @($loaded)
}

$presetFilter = "$title preset (*.json)|*.json"

$panel = New-Object Windows.Forms.FlowLayoutPanel
$panel.Dock = 'Bottom'
$panel.AutoSize = $true
$panel.Padding = New-Object Windows.Forms.Padding((Px 6))

function Add-Button($text, $onClick) {
    $btn = New-Object Windows.Forms.Button
    $btn.Text = $text
    $btn.AutoSize = $true
    $btn.Padding = New-Object Windows.Forms.Padding((Px 6), (Px 2), (Px 6), (Px 2))
    $btn.FlatStyle = 'Flat'
    $btn.Add_Click({
            try { & $onClick }
            catch { [void](Msg $_.Exception.Message 'OK' 'Error') }
        }.GetNewClosure())
    $panel.Controls.Add($btn)
}

Add-Button 'Turn off ticked' { Set-Ticked $false }
Add-Button 'Restore ticked to default' { Set-Ticked $true }

Add-Button 'Delete AI model files' {
    $b = Current
    if (-not $b.Models) {
        [void](Msg "$($b.Name) deletes its downloaded AI models by itself once the AI features on this tab are turned off and the browser restarts.")
        return
    }
    $dirs = Get-ModelDirs $b
    if (-not $dirs) {
        [void](Msg "No downloaded $($b.Name) AI model found on this PC. Nothing to delete.")
        return
    }
    $size = '{0:N2} GB' -f ((Get-ChildItem $dirs.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1GB)
    if ((Msg "$($b.Name)'s on-device AI model takes ${size}:`n`n$($dirs.FullName -join "`n")`n`nDelete it?" 'YesNo' 'Question') -ne 'Yes') { return }
    if (Get-Running $b) {
        if ((Msg "$($b.Name) has to be closed first. Close it now?`n`nUnsaved work in open tabs will be lost." 'OKCancel' 'Warning') -ne 'OK') { return }
        Close-Browser $b
    }
    foreach ($d in $dirs) { Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    $left = Get-ModelDirs $b
    $done = if ($left) { "Could not delete:`n`n$($left.FullName -join "`n")" } else { 'Deleted.' }
    $model = $settings | Where-Object { $_.Browser -eq $b.Name -and $_.Name -eq 'On-device AI model' }
    if ((Get-Status $b $model (Read-Policies $b)) -ne 'Turned off') {
        $done += "`n`n$($b.Name) will download it again unless ""$($model.Name)"" is turned off on this tab."
    }
    [void](Msg $done)
}

Add-Button 'Clean up old policies' {
    $b = Current
    $old = @(Find-OldPolicies $b)
    if (-not $old) {
        [void](Msg "No old $($b.Name) policies found. Nothing to clean up.")
        return
    }
    $list = ($old | ForEach-Object { "$($_.Id) = $($_.Current)`n      $($_.Why)" }) -join "`n"
    if ((Msg "Found $($old.Count) old $($b.Name) policies that the browser no longer uses or that newer policies replace:`n`n$list`n`nRemove them?" 'YesNo' 'Question') -ne 'Yes') { return }
    $backupNote = Backup-Policies $b
    foreach ($v in $old) {
        Remove-ItemProperty -Path $v.Path -Name $v.Prop -ErrorAction SilentlyContinue
        Remove-EmptyKeys $b $v.Path
    }
    [void](Msg "$($b.Name): removed $($old.Count) old policies.$backupNote`n`nRestart the browser to apply.")
}

Add-Button 'Tick recommended' { foreach ($i in (Current).List.Items) { $i.Checked = $i.Tag.Default } }
Add-Button 'Tick all' { foreach ($i in (Current).List.Items) { $i.Checked = $true } }
Add-Button 'Untick all' { foreach ($i in (Current).List.Items) { $i.Checked = $false } }

Add-Button 'Save ticks...' {
    $dialog = New-Object Windows.Forms.SaveFileDialog
    $dialog.Filter = $presetFilter
    $dialog.FileName = 'browser-tools-preset.json'
    if ($dialog.ShowDialog($form) -ne 'OK') { return }
    Export-Preset $dialog.FileName
    [void](Msg "Saved the ticks of every tab to:`n`n$($dialog.FileName)`n`nLoad it with ""Load ticks..."" on any PC.")
}

Add-Button 'Load ticks...' {
    $dialog = New-Object Windows.Forms.OpenFileDialog
    $dialog.Filter = $presetFilter
    if ($dialog.ShowDialog($form) -ne 'OK') { return }
    $loaded = Import-Preset $dialog.FileName
    [void](Msg "Loaded ticks for: $($loaded -join ', ').`n`nNothing is changed yet. Check each tab, then click ""Turn off ticked"" on it.")
}

$backup = New-Object Windows.Forms.CheckBox
$backup.Text = 'Back up policies before changes'
$backup.Checked = $true
$backup.AutoSize = $true
$backup.FlatStyle = 'Flat'
$backup.Margin = New-Object Windows.Forms.Padding((Px 10), (Px 7), 0, 0)
$panel.Controls.Add($backup)
$tips = New-Object Windows.Forms.ToolTip
$tips.SetToolTip($backup, "Saves the tab's current policies to Documents\$title backups as a .reg file before every change.")

# ---------------- Theme: follows the Windows light/dark app mode, checked every 2 seconds ----------------
$palettes = @{
    Dark  = @{ Back = '#202020'; List = '#2b2b2b'; Fore = '#f0f0f0'; Muted = '#b4b4b4'; Button = '#333333'; Border = '#4a4a4a' }
    Light = @{ Back = '#f3f3f3'; List = '#ffffff'; Fore = '#1a1a1a'; Muted = '#505050'; Button = '#ffffff'; Border = '#c8c8c8' }
}
function C($hex) { [Drawing.ColorTranslator]::FromHtml($hex) }
$null_ = [Management.Automation.Language.NullString]::Value

function Draw-Header($e) {
    if (-not $script:dark) { $e.DrawDefault = $true; return }
    $p = $script:palette
    $g = $e.Graphics
    $r = $e.Bounds
    $g.FillRectangle((New-Object Drawing.SolidBrush (C $p.List)), $r)
    $g.DrawLine((New-Object Drawing.Pen (C $p.Border)), ($r.Right - 1), $r.Top, ($r.Right - 1), ($r.Bottom - 1))
    $text = New-Object Drawing.Rectangle(($r.X + (Px 6)), $r.Y, ($r.Width - (Px 8)), $r.Height)
    [Windows.Forms.TextRenderer]::DrawText($g, $e.Header.Text, $e.Font, $text, (C $p.Muted), [Windows.Forms.TextFormatFlags]'VerticalCenter, Left, EndEllipsis')
}

function Test-DarkMode {
    (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction SilentlyContinue).AppsUseLightTheme -eq 0
}

function Set-TabColors {
    $p = $script:palette
    if (-not $p) { return }
    foreach ($x in $browsers) {
        $selected = $x -eq $script:current
        $x.Tab.BackColor = C $(if ($selected) { $p.List } else { $p.Back })
        $x.Tab.ForeColor = C $(if ($selected) { $p.Fore } else { $p.Muted })
        $x.Tab.FlatAppearance.CheckedBackColor = $x.Tab.BackColor
        $x.Tab.FlatAppearance.MouseOverBackColor = C $p.Button
    }
}

function Set-Theme($dark) {
    $script:dark = $dark
    $p = $script:palette = $palettes[$(if ($dark) { 'Dark' } else { 'Light' })]
    $form.BackColor = C $p.Back
    $form.ForeColor = C $p.Fore
    $info.ForeColor = C $p.Muted
    foreach ($btn in $panel.Controls) {
        $btn.BackColor = C $(if ($btn -eq $backup) { $p.Back } else { $p.Button })
        $btn.ForeColor = C $p.Fore
        $btn.FlatAppearance.BorderColor = C $p.Border
    }
    foreach ($x in $browsers) {
        $x.List.BackColor = C $p.List
        $x.List.ForeColor = C $p.Fore
        # scroll bars, group headings and checkboxes take File Explorer's dark theme
        [void][Native.Win]::SetWindowTheme($x.List.Handle, $(if ($dark) { 'DarkMode_ItemsView' } else { 'Explorer' }), $null_)
        $header = [Native.Win]::SendMessage($x.List.Handle, 0x101F, [IntPtr]::Zero, [IntPtr]::Zero) # LVM_GETHEADER
        [void][Native.Win]::SetWindowTheme($header, $(if ($dark) { 'DarkMode_ItemsView' } else { $null_ }), $null_)
        $x.List.Invalidate($true)
    }
    Set-TabColors
    # dark title bar: DWMWA_USE_IMMERSIVE_DARK_MODE is 20, or 19 on Windows 10 before 20H1
    $on = [int][bool]$dark
    if ([Native.Win]::DwmSetWindowAttribute($form.Handle, 20, [ref]$on, 4) -ne 0) { [void][Native.Win]::DwmSetWindowAttribute($form.Handle, 19, [ref]$on, 4) }
    # Windows 10 only repaints the caption when it is activated again (WM_NCACTIVATE off, then on)
    [void][Native.Win]::SendMessage($form.Handle, 0x86, [IntPtr]::Zero, [IntPtr]::Zero)
    [void][Native.Win]::SendMessage($form.Handle, 0x86, [IntPtr]1, [IntPtr]::Zero)
    $form.Refresh()
}

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 2000
$timer.Add_Tick({ $dark = Test-DarkMode; if ($dark -ne $script:dark) { Set-Theme $dark } })
$form.Add_Shown({ Set-Theme (Test-DarkMode); $timer.Start() })

$form.Controls.Add($body)
$form.Controls.Add($panel)
$form.Controls.Add($tabBar)
$form.Controls.Add($info)
foreach ($b in $browsers) { Update-Status $b }
Show-Browser $browsers[0]
[void]$form.ShowDialog()
