# Browser Tools: turn off AI features, telemetry and clutter in Chrome, Edge, Firefox, Zen and Vivaldi using Windows policies.
# Run it: right-click this file > Run with PowerShell, or paste into PowerShell:
#   irm https://raw.githubusercontent.com/AnimeKaizoku/Browser-Tools/main/Browser-Tools.ps1 | iex

$url = 'https://raw.githubusercontent.com/AnimeKaizoku/Browser-Tools/main/Browser-Tools.ps1'
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $run = if ($PSCommandPath) { "-File `"$PSCommandPath`"" } else { "-Command `"irm $url | iex`"" }
    try { Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden $run" }
    catch { Write-Host 'Administrator rights are needed to set browser policies.' -ForegroundColor Red }
    return
}

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -Namespace Native -Name Dpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
[void][Native.Dpi]::SetProcessDPIAware()
[Windows.Forms.Application]::EnableVisualStyles()

$users = "$env:SystemDrive\Users\*"
$pf = $env:ProgramFiles
$pf86 = ${env:ProgramFiles(x86)}
$firefoxModelNote = 'Firefox deletes its downloaded AI models by itself once the AI features on this tab are turned off and the browser restarts.'

$browsers = @(
    [pscustomobject]@{
        Name      = 'Chrome'
        Key       = 'HKLM:\SOFTWARE\Policies\Google\Chrome'
        Processes = @('chrome')
        Exes      = @("$pf\Google\Chrome\Application\chrome.exe", "$pf86\Google\Chrome\Application\chrome.exe", "$users\AppData\Local\Google\Chrome\Application\chrome.exe")
        # Gemini Nano weights, several GB, for every user and every Chrome channel
        Models    = @("$users\AppData\Local\Google\Chrome*\User Data\OptGuideOnDeviceModel")
        ModelNote = ''
    }
    [pscustomobject]@{
        Name      = 'Edge'
        Key       = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
        Processes = @('msedge')
        Exes      = @("$pf86\Microsoft\Edge\Application\msedge.exe", "$pf\Microsoft\Edge\Application\msedge.exe")
        # Phi on-device model, several GB
        Models    = @("$users\AppData\Local\Microsoft\Edge*\User Data\EdgeLLMOnDeviceModel")
        ModelNote = ''
    }
    [pscustomobject]@{
        Name      = 'Firefox'
        Key       = 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox'
        Processes = @('firefox')
        Exes      = @("$pf\Mozilla Firefox\firefox.exe", "$pf86\Mozilla Firefox\firefox.exe", "$pf\Firefox Developer Edition\firefox.exe", "$pf\Firefox Nightly\firefox.exe", "$users\AppData\Local\Mozilla Firefox\firefox.exe")
        Models    = @()
        ModelNote = $firefoxModelNote
    }
    [pscustomobject]@{
        Name      = 'Zen'
        Key       = 'HKLM:\SOFTWARE\Policies\Mozilla\Zen'
        Processes = @('zen')
        Exes      = @("$pf\Zen Browser\zen.exe", "$pf\Zen Twilight\zen.exe", "$users\AppData\Local\Zen Browser\zen.exe")
        Models    = @()
        ModelNote = $firefoxModelNote.Replace('Firefox', 'Zen')
    }
    [pscustomobject]@{
        Name      = 'Vivaldi'
        Key       = 'HKLM:\SOFTWARE\Policies\Vivaldi'
        Processes = @('vivaldi')
        Exes      = @("$pf\Vivaldi\Application\vivaldi.exe", "$users\AppData\Local\Vivaldi\Application\vivaldi.exe")
        Models    = @("$users\AppData\Local\Vivaldi\User Data\OptGuideOnDeviceModel")
        ModelNote = ''
    }
)

$settings = New-Object Collections.ArrayList
# $set maps "ValueName" or "Subkey\ValueName" to the value that turns the feature off (int = DWORD, string = REG_SZ).
# $prefs maps Firefox pref names to locked values written into the Preferences policy.
function S($browser, $group, $name, $desc, $set, $prefs, $default = $true) {
    $values = foreach ($id in $set.Keys) {
        $cut = $id.LastIndexOf('\')
        [pscustomobject]@{
            Id    = $id
            Sub   = if ($cut -ge 0) { $id.Substring(0, $cut) } else { '' }
            Prop  = $id.Substring($cut + 1)
            Value = $set[$id]
            Type  = if ($set[$id] -is [string]) { 'String' } else { 'DWord' }
        }
    }
    $prefList = if ($prefs) { foreach ($p in $prefs.Keys) { [pscustomobject]@{ Name = $p; Value = $prefs[$p] } } }
    $tip = @($values | ForEach-Object { "$($_.Id) = $($_.Value)" }) + @($prefList | ForEach-Object { "Preferences: $($_.Name) = $($_.Value)" })
    [void]$settings.Add([pscustomobject]@{
            Browser = $browser; Group = $group; Name = $name; Desc = $desc; Default = $default
            Values  = @($values); Prefs = @($prefList); Tip = ($tip -join "`n")
        })
}

# Firefox and Zen share the same policy engine, only the registry key differs
function F($group, $name, $desc, $set, $prefs, $default = $true) {
    S Firefox $group $name $desc $set $prefs $default
    S Zen $group $name $desc $set $prefs $default
}

# ---------------- Chrome ----------------
S Chrome AI 'Ask Google about this page and Lens' 'Hides "Ask Google about this page" and Google Lens, and stops sharing page content with AI Mode and Lens.' @{ SearchContentSharingSettings = 1 }
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
S Chrome Clutter 'Promotions' 'Hides Google promotional content.' @{ PromotionsEnabled = 0 }
S Chrome Clutter 'Shopping features' 'Turns off price tracking and the shopping list.' @{ ShoppingListEnabled = 0 }
S Chrome Clutter 'New Tab page cards' 'Hides the cards on the New Tab page.' @{ NTPCardsVisible = 0 }
S Chrome Clutter 'Default browser nag' 'Stops Chrome asking to be the default browser. It can no longer set itself as default.' @{ DefaultBrowserSettingEnabled = 0 }
S Chrome Clutter 'Run in background' 'Chrome fully exits when its last window is closed.' @{ BackgroundModeEnabled = 0 }
S Chrome Optional 'Address bar suggestions' 'Stops sending what you type in the address bar to Google. You lose search suggestions.' @{ SearchSuggestEnabled = 0 } -default $false

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
S Edge Optional 'Address bar suggestions' 'Stops sending what you type in the address bar to Bing. You lose search suggestions.' @{ SearchSuggestEnabled = 0 } -default $false
S Edge Optional 'Microsoft Editor spell check' 'Spell check runs on your PC only. You lose grammar suggestions.' @{ MicrosoftEditorProofingEnabled = 0 } -default $false
S Edge Optional 'Share with Windows Search' 'Stops sharing browsing data with Windows Search.' @{ LocalBrowserDataShareEnabled = 0 } -default $false
S Edge Optional 'Online error help' 'Network errors and missing pages are handled without asking Microsoft.' @{ ResolveNavigationErrorsUseWebService = 0; AlternateErrorPagesEnabled = 0 } -default $false
S Edge Optional 'New Tab quick links' 'Hides all quick links on the New Tab page, including your own.' @{ NewTabPageQuickLinksEnabled = 0 } -default $false
S Edge Optional 'Live video translation' 'Turns off on-device live video translation.' @{ LiveVideoTranslationEnabled = 0 } -default $false
S Edge Optional 'Drop' 'Turns off Drop file and note sharing between your devices.' @{ EdgeEDropEnabled = 0 } -default $false

# ---------------- Vivaldi ----------------
# Vivaldi reads Chromium policies from its own key, but only officially supports them from 8.3
S Vivaldi AI 'On-device AI model' 'Stops Vivaldi downloading Chromium''s on-device AI model and deletes it if already downloaded.' @{ GenAILocalFoundationalModelSettings = 1 }
S Vivaldi AI 'Built-in AI for websites' 'Stops websites using the browser''s built-in AI APIs.' @{ BuiltInAIAPIsEnabled = 0 }
S Vivaldi Telemetry 'Make searches and browsing better' 'Stops sending the URLs you visit to improve browsing.' @{ UrlKeyedAnonymizedDataCollectionEnabled = 0 }
S Vivaldi Telemetry 'Enhanced spell check' 'Uses only the local spell checker, not the web spelling service.' @{ SpellCheckServiceEnabled = 0 }
S Vivaldi Clutter 'Direct Match' 'Turns off sponsored Direct Match suggestions in the address bar.' @{ VivaldiDirectMatchEnabled = 0 }
S Vivaldi Clutter 'Promotions' 'Hides promotional content.' @{ PromotionsEnabled = 0 }
S Vivaldi Clutter 'Default browser nag' 'Stops Vivaldi asking to be the default browser.' @{ DefaultBrowserSettingEnabled = 0 }
S Vivaldi Clutter 'Run in background' 'Vivaldi fully exits when its last window is closed.' @{ BackgroundModeEnabled = 0 }
S Vivaldi Optional 'Address bar suggestions' 'Stops sending what you type in the address bar to your search engine. You lose search suggestions.' @{ SearchSuggestEnabled = 0 } -default $false
S Vivaldi Optional 'Built-in VPN' 'Hides the built-in Proton VPN.' @{ VivaldiVPNEnabled = 0 } -default $false
S Vivaldi Optional 'Online error help' 'Stops using a web service to suggest pages when a site fails to load.' @{ AlternateErrorPagesEnabled = 0 } -default $false
S Vivaldi Optional 'Preloading' 'Turns off preloading pages. Pages may load a little slower.' @{ NetworkPredictionOptions = 2 } -default $false

# ---------------- Firefox and Zen ----------------
# AIControls is Firefox 149 and newer, GenerativeAI covers 144 to 149
F AI 'AI chatbot' 'Removes the AI chatbot sidebar, menu and shortcuts.' @{ 'AIControls\SidebarChatbot\Value' = 'blocked'; 'AIControls\SidebarChatbot\Locked' = 1; 'GenerativeAI\Chatbot' = 0; 'GenerativeAI\Locked' = 1 } @{ 'browser.ml.chat.enabled' = $false; 'browser.ml.chat.menu' = $false; 'browser.ml.chat.shortcuts' = $false; 'browser.ml.chat.sidebar' = $false }
F AI 'Link previews' 'Turns off AI link previews and key points.' @{ 'AIControls\LinkPreviewKeyPoints\Value' = 'blocked'; 'AIControls\LinkPreviewKeyPoints\Locked' = 1; 'GenerativeAI\LinkPreviews' = 0; 'GenerativeAI\Locked' = 1 }
F AI 'Smart tab groups' 'Turns off AI tab grouping and group name suggestions.' @{ 'AIControls\SmartTabGroups\Value' = 'blocked'; 'AIControls\SmartTabGroups\Locked' = 1; 'GenerativeAI\TabGroups' = 0; 'GenerativeAI\Locked' = 1 } @{ 'browser.tabs.groups.smart.enabled' = $false }
F AI 'Smart Window' 'Turns off the AI Smart Window.' @{ 'AIControls\SmartWindow\Value' = 'blocked'; 'AIControls\SmartWindow\Locked' = 1; 'GenerativeAI\SmartWindow' = 0; 'GenerativeAI\Locked' = 1 } @{ 'browser.smartwindow.enabled' = $false }
F AI 'PDF alt text' 'Stops generating image descriptions in PDFs and downloading the model for it.' @{ 'AIControls\PDFAltText\Value' = 'blocked'; 'AIControls\PDFAltText\Locked' = 1 } @{ 'pdfjs.enableAltTextModelDownload' = $false; 'pdfjs.enableGuessAltText' = $false }
F AI 'Speech recognition' 'Turns off on-device AI speech recognition.' @{ 'AIControls\SpeechRecognition\Value' = 'blocked'; 'AIControls\SpeechRecognition\Locked' = 1 }
F AI 'AI engine' 'Turns off the on-device machine learning engine that the AI features use.' @{ 'GenerativeAI\Enabled' = 0; 'GenerativeAI\Locked' = 1 } @{ 'browser.ml.enable' = $false }
F AI 'AI for extensions' 'Stops extensions using Firefox''s AI and downloading models.' @{} @{ 'extensions.ml.enabled' = $false }
F AI 'AI history search' 'Turns off AI search of your history.' @{} @{ 'places.semanticHistory.featureGate' = $false }
F Telemetry 'Telemetry' 'Stops sending usage and technical data to Mozilla.' @{ DisableTelemetry = 1 }
F Telemetry 'Studies' 'Stops Mozilla running studies and experiments in your browser.' @{ DisableFirefoxStudies = 1 }
F Telemetry 'Address bar data' 'Stops sending what you type in the address bar to Mozilla.' @{ 'FirefoxSuggest\ImproveSuggest' = 0; 'FirefoxSuggest\OnlineEnabled' = 0; 'FirefoxSuggest\Locked' = 1 }
F Telemetry 'Default browser agent' 'Stops the background task that reports default browser info.' @{ DisableDefaultBrowserAgent = 1 }
F Telemetry 'New Tab telemetry' 'Stops sending New Tab page usage data.' @{} @{ 'browser.newtabpage.activity-stream.telemetry' = $false; 'browser.newtabpage.activity-stream.feeds.telemetry' = $false }
F Telemetry 'Personalized recommendations' 'Stops personalized extension recommendations.' @{} @{ 'browser.discovery.enabled' = $false }
F Telemetry 'Feedback commands' 'Removes the Submit Feedback and Report Deceptive Site menu items.' @{ DisableFeedbackCommands = 1 }
F Clutter 'Sponsored shortcuts' 'Removes sponsored shortcuts from the New Tab page.' @{ 'FirefoxHome\SponsoredTopSites' = 0; 'FirefoxHome\Locked' = 1 }
F Clutter 'Sponsored stories' 'Removes sponsored stories from the New Tab page.' @{ 'FirefoxHome\SponsoredStories' = 0; 'FirefoxHome\SponsoredPocket' = 0; 'FirefoxHome\Locked' = 1 }
F Clutter 'Sponsored suggestions' 'Removes sponsored suggestions from the address bar.' @{ 'FirefoxSuggest\SponsoredSuggestions' = 0; 'FirefoxSuggest\Locked' = 1 }
F Clutter 'Extension recommendations' 'Stops recommending extensions while you browse.' @{ 'UserMessaging\ExtensionRecommendations' = 0; 'UserMessaging\Locked' = 1 }
F Clutter 'Feature recommendations' 'Stops feature recommendation pop-ups.' @{ 'UserMessaging\FeatureRecommendations' = 0; 'UserMessaging\Locked' = 1 }
F Clutter 'Address bar tips' 'Stops Firefox tips in the address bar.' @{ 'UserMessaging\UrlbarInterventions' = 0; 'UserMessaging\Locked' = 1 }
F Clutter 'Onboarding' 'Skips the onboarding screens.' @{ 'UserMessaging\SkipOnboarding' = 1; 'UserMessaging\Locked' = 1 }
F Clutter 'More from Mozilla' 'Hides "More from Mozilla" in Settings.' @{ 'UserMessaging\MoreFromMozilla' = 0; 'UserMessaging\Locked' = 1 }
F Clutter 'Product promotions' 'Hides VPN and other Mozilla product promotions.' @{} @{ 'browser.vpn_promo.enabled' = $false; 'identity.fxaccounts.toolbar.pxiToolbarEnabled' = $false }
F Clutter 'Built-in VPN' 'Removes the built-in VPN feature and its prompts.' @{ IPProtectionAvailable = 0 }
F Clutter 'Default browser nag' 'Stops asking to be the default browser.' @{ DontCheckDefaultBrowser = 1 }
F Clutter 'Terms of Use pop-up' 'Skips the Terms of Use pop-up at startup.' @{ SkipTermsOfUse = 1 }
F Clutter 'Visual search' 'Removes visual image search from the right-click menu.' @{ VisualSearchEnabled = 0 }
F Clutter 'Pocket (old)' 'Turns off Pocket. Only matters on older versions.' @{ DisablePocket = 1 }
F Optional 'Translations' 'Turns off page translation. It runs on your PC and sends nothing to Mozilla.' @{ 'AIControls\Translations\Value' = 'blocked'; 'AIControls\Translations\Locked' = 1; TranslateEnabled = 0 } -default $false
F Optional 'Block all other AI' 'Blocks every AI feature without its own switch, including future ones and Translations.' @{ 'AIControls\Default\Value' = 'blocked'; 'AIControls\Default\Locked' = 1 } -default $false
F Optional 'Address bar suggestions' 'Stops sending what you type in the address bar to your search engine. You lose search suggestions.' @{ SearchSuggestEnabled = 0 } -default $false
F Optional 'Firefox Suggest' 'Turns off Firefox Suggest completely.' @{ 'FirefoxSuggest\WebSuggestions' = 0; 'FirefoxSuggest\Locked' = 1 } -default $false
F Optional 'Trending searches' 'Removes trending searches from the address bar.' @{} @{ 'browser.urlbar.trending.featureGate' = $false } -default $false
F Optional 'New Tab stories' 'Removes all stories from the New Tab page.' @{ 'FirefoxHome\Stories' = 0; 'FirefoxHome\Pocket' = 0; 'FirefoxHome\Locked' = 1 } -default $false
F Optional 'New Tab weather' 'Removes the weather widget from the New Tab page.' @{ 'FirefoxHome\Weather' = 0; 'FirefoxHome\Locked' = 1 } -default $false
F Optional 'Preloading' 'Turns off DNS prefetch and preconnect. Pages may load a little slower.' @{ NetworkPrediction = 0 } -default $false
F Optional 'Firefox Labs' 'Hides Firefox Labs in Settings.' @{ 'UserMessaging\FirefoxLabs' = 0; 'UserMessaging\Locked' = 1 } -default $false
F Optional 'Remote feature rollouts' 'Stops Mozilla turning features on between updates. This can also delay some fixes.' @{ DisableRemoteImprovements = 1 } -default $false

$groupTitles = [ordered]@{ AI = 'AI features'; Telemetry = 'Telemetry'; Clutter = 'Clutter'; Optional = 'Optional (not ticked by default)' }

# ---------------- Registry ----------------
function PathOf($b, $v) { if ($v.Sub) { "$($b.Key)\$($v.Sub)" } else { $b.Key } }

function Get-Prefs($b) {
    $prefs = [ordered]@{}
    $raw = (Get-ItemProperty -Path $b.Key -ErrorAction SilentlyContinue).Preferences
    if ($raw) {
        $json = ($raw -join "`n") | ConvertFrom-Json -ErrorAction Stop
        foreach ($p in $json.PSObject.Properties) { $prefs[$p.Name] = $p.Value }
    }
    $prefs
}

function Set-Prefs($b, $prefs) {
    if ($prefs.Count) {
        if (-not (Test-Path $b.Key)) { New-Item -Path $b.Key -Force | Out-Null }
        $json = $prefs | ConvertTo-Json -Compress -Depth 5
        New-ItemProperty -Path $b.Key -Name Preferences -PropertyType MultiString -Value @($json) -Force | Out-Null
    }
    else { Remove-ItemProperty -Path $b.Key -Name Preferences -ErrorAction SilentlyContinue }
}

# returns how many of the setting's values are in place, out of its total
function Get-Hits($b, $s, $prefs) {
    $hits = 0
    foreach ($v in $s.Values) {
        $cur = (Get-ItemProperty -Path (PathOf $b $v) -ErrorAction SilentlyContinue).($v.Prop)
        if ($null -ne $cur -and "$cur" -eq "$($v.Value)") { $hits++ }
    }
    foreach ($p in $s.Prefs) {
        $e = $prefs[$p.Name]
        if ($e -and "$($e.Value)" -eq "$($p.Value)" -and $e.Status -eq 'locked') { $hits++ }
    }
    $hits
}

function Remove-EmptyKeys($b, $path) {
    while ($path -ne $b.Key -and (Test-Path $path) -and -not (Get-Item $path).ValueCount -and -not (Get-ChildItem $path)) {
        Remove-Item $path
        $path = Split-Path $path
    }
}

# ---------------- UI ----------------
$scale = [Drawing.Graphics]::FromHwnd([IntPtr]::Zero).DpiX / 96
function Px($n) { [int]($n * $scale) }

$form = New-Object Windows.Forms.Form
$form.Text = 'Browser Tools'
$form.Font = New-Object Drawing.Font('Segoe UI', 9)
$form.Size = New-Object Drawing.Size((Px 1120), (Px 800))
$form.StartPosition = 'CenterScreen'

function Msg($text, $buttons = 'OK', $icon = 'Information') {
    [Windows.Forms.MessageBox]::Show($form, $text, $form.Text, $buttons, $icon)
}

$info = New-Object Windows.Forms.Label
$info.Text = "Ticked features get turned off for everyone on this PC. Buttons act on the tab you are on. Hover a row to see the policies it sets.`nThe Firefox tab covers Firefox, Developer Edition, ESR and Nightly. Vivaldi only officially supports policies from version 8.3."
$info.Dock = 'Top'
$info.Height = Px 46
$info.Padding = New-Object Windows.Forms.Padding((Px 8), 0, 0, 0)
$info.TextAlign = 'MiddleLeft'

$tabs = New-Object Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$tabs.Padding = New-Object Drawing.Point((Px 12), (Px 4))

foreach ($b in $browsers) {
    $installed = [bool]($b.Exes | Where-Object { Test-Path $_ })
    $page = New-Object Windows.Forms.TabPage($(if ($installed) { $b.Name } else { "$($b.Name) (not installed)" }))
    $page.Tag = $b

    $list = New-Object Windows.Forms.ListView
    $list.View = 'Details'
    $list.CheckBoxes = $true
    $list.FullRowSelect = $true
    $list.ShowItemToolTips = $true
    $list.Dock = 'Fill'
    [void]$list.Columns.Add('Feature', (Px 260))
    [void]$list.Columns.Add('What turning it off does', (Px 610))
    [void]$list.Columns.Add('Status on this PC', (Px 150))

    $groups = @{}
    foreach ($g in $groupTitles.Keys) {
        $groups[$g] = New-Object Windows.Forms.ListViewGroup($g, $groupTitles[$g])
        [void]$list.Groups.Add($groups[$g])
    }
    foreach ($s in $settings | Where-Object Browser -eq $b.Name) {
        $item = New-Object Windows.Forms.ListViewItem($s.Name)
        [void]$item.SubItems.Add($s.Desc)
        [void]$item.SubItems.Add('')
        $item.Group = $groups[$s.Group]
        $item.Checked = $s.Default
        $item.ToolTipText = $s.Tip
        $item.Tag = $s
        [void]$list.Items.Add($item)
    }
    $b | Add-Member -NotePropertyName List -NotePropertyValue $list -Force
    $page.Controls.Add($list)
    $tabs.TabPages.Add($page)
}

function Current { $tabs.SelectedTab.Tag }

function Update-Status($b) {
    $prefs = try { Get-Prefs $b } catch { [ordered]@{} }
    foreach ($item in $b.List.Items) {
        $s = $item.Tag
        $hits = Get-Hits $b $s $prefs
        $item.SubItems[2].Text = if ($hits -eq $s.Values.Count + $s.Prefs.Count) { 'Turned off' } elseif ($hits) { 'Partly set' } else { 'Not set' }
    }
}

function Get-Ticked($b) { @($b.List.CheckedItems | ForEach-Object { $_.Tag }) }

function Get-ModelDirs($b) {
    @($b.Models | ForEach-Object { Get-ChildItem $_ -Directory -Force -ErrorAction SilentlyContinue })
}

function Get-Size($dirs) {
    $sum = ($dirs | ForEach-Object { Get-ChildItem $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue } | Measure-Object Length -Sum).Sum
    '{0:N2} GB' -f ($sum / 1GB)
}

function Close-Browser($b) {
    for ($i = 0; $i -lt 20 -and (Get-Process $b.Processes -ErrorAction SilentlyContinue); $i++) {
        Get-Process $b.Processes -ErrorAction SilentlyContinue | ForEach-Object { [void]$_.CloseMainWindow() }
        Start-Sleep -Milliseconds 500
    }
    Get-Process $b.Processes -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 1
}

$reload = 'Restart the browser to apply. Chrome and Edge can also reload policies from chrome://policy or edge://policy.'

$panel = New-Object Windows.Forms.FlowLayoutPanel
$panel.Dock = 'Bottom'
$panel.AutoSize = $true
$panel.Padding = New-Object Windows.Forms.Padding((Px 6))

function Add-Button($text, $onClick) {
    $btn = New-Object Windows.Forms.Button
    $btn.Text = $text
    $btn.AutoSize = $true
    $btn.Padding = New-Object Windows.Forms.Padding((Px 6), (Px 2), (Px 6), (Px 2))
    $btn.Add_Click({
            try { & $onClick }
            catch { [void](Msg $_.Exception.Message 'OK' 'Error') }
        }.GetNewClosure())
    $panel.Controls.Add($btn)
}

Add-Button 'Turn off ticked' {
    $b = Current
    $ticked = Get-Ticked $b
    if (-not $ticked) { return }
    $prefs = Get-Prefs $b
    $prefsChanged = $false
    foreach ($s in $ticked) {
        foreach ($v in $s.Values) {
            $path = PathOf $b $v
            if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
            New-ItemProperty -Path $path -Name $v.Prop -Value $v.Value -PropertyType $v.Type -Force | Out-Null
        }
        foreach ($p in $s.Prefs) {
            $prefs[$p.Name] = [pscustomobject]@{ Value = $p.Value; Status = 'locked' }
            $prefsChanged = $true
        }
    }
    if ($prefsChanged) { Set-Prefs $b $prefs }
    Update-Status $b
    [void](Msg "$($b.Name): turned off $($ticked.Count) feature(s).`n`n$reload")
}

Add-Button 'Restore ticked to default' {
    $b = Current
    $ticked = Get-Ticked $b
    if (-not $ticked) { return }
    $prefs = Get-Prefs $b
    # keep values that another, still applied setting shares (for example GenerativeAI\Locked)
    $keepValues = @{}
    $keepPrefs = @{}
    foreach ($item in $b.List.Items) {
        if ($item.Checked -or -not (Get-Hits $b $item.Tag $prefs)) { continue }
        foreach ($v in $item.Tag.Values) { $keepValues[$v.Id] = $true }
        foreach ($p in $item.Tag.Prefs) { $keepPrefs[$p.Name] = $true }
    }
    $prefsChanged = $false
    foreach ($s in $ticked) {
        foreach ($v in $s.Values) {
            if ($keepValues[$v.Id]) { continue }
            $path = PathOf $b $v
            Remove-ItemProperty -Path $path -Name $v.Prop -ErrorAction SilentlyContinue
            Remove-EmptyKeys $b $path
        }
        foreach ($p in $s.Prefs) {
            if ($keepPrefs[$p.Name] -or -not $prefs.Contains($p.Name)) { continue }
            $prefs.Remove($p.Name)
            $prefsChanged = $true
        }
    }
    if ($prefsChanged) { Set-Prefs $b $prefs }
    Update-Status $b
    [void](Msg "$($b.Name): restored $($ticked.Count) feature(s) to the browser's default.`n`n$reload")
}

Add-Button 'Delete AI model files' {
    $b = Current
    if ($b.ModelNote) {
        [void](Msg $b.ModelNote)
        return
    }
    $dirs = Get-ModelDirs $b
    if (-not $dirs) {
        [void](Msg "No downloaded $($b.Name) AI model found on this PC. Nothing to delete.")
        return
    }
    $found = "$($b.Name)'s on-device AI model takes $(Get-Size $dirs):`n`n" + (($dirs | ForEach-Object FullName) -join "`n")
    if ((Msg "$found`n`nDelete it?" 'YesNo' 'Question') -ne 'Yes') { return }
    if (Get-Process $b.Processes -ErrorAction SilentlyContinue) {
        if ((Msg "$($b.Name) has to be closed first. Close it now?`n`nUnsaved work in open tabs will be lost." 'OKCancel' 'Warning') -ne 'OK') { return }
        Close-Browser $b
    }
    foreach ($d in $dirs) { Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    $left = Get-ModelDirs $b
    [void](Msg $(if ($left) { "Could not delete:`n`n" + (($left | ForEach-Object FullName) -join "`n") } else { 'Deleted.' }))
}

Add-Button 'Tick all' { foreach ($i in (Current).List.Items) { $i.Checked = $true } }
Add-Button 'Untick all' { foreach ($i in (Current).List.Items) { $i.Checked = $false } }

$form.Controls.Add($tabs)
$form.Controls.Add($panel)
$form.Controls.Add($info)
foreach ($b in $browsers) { Update-Status $b }
[void]$form.ShowDialog()
