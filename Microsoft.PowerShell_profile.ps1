################
# Module Setup #
################

# *** Function Modules ***

# PSReadLine
Import-Module -Name PSReadLine

# Load the CompletionPredictor module if PSVersion is 7.2 or higher
if ($PSVersionTable.PSVersion.Major -ge 7 -and $PSVersionTable.PSVersion.Minor -ge 2) {
    Import-Module -Name CompletionPredictor
}

# gsudo
Import-Module "$env:USERPROFILE\scoop\apps\gsudo\current\gsudoModule.psd1"

# *** Style Modules ***

# Posh-Git
try{
    Import-Module -Name posh-git

    $env:POSH_GIT_ENABLED = $true # Used to determine if posh-git is loaded
}catch{
    $env:POSH_GIT_ENABLED = $false
}


# Terminal-Icons
Import-Module -Name Terminal-Icons

# *** Package Manager Modules ***

# Winget
Import-Module -Name Microsoft.WinGet.Client

# Chocolatey
Import-Module "$env:ChocolateyInstall\helpers\chocolateyInstaller.psm1"

# Scoop-completion: Auto-Completion for scoop 
Import-Module "$($(Get-Item $(Get-Command scoop.ps1).Path).Directory.Parent.FullName)\modules\scoop-completion"

# posh-vcpkg
Import-Module 'C:\tools\vcpkg\scripts\posh-vcpkg'

# *** Other Modules ***

# Written by me

# NCR 
Import-Module Posh-NCR

# Fuzzy-Winget
Import-Module fuzzy-winget

<# External Programs #>

# Zoxide
try{
    Invoke-Expression (& { # Zoxide intialisation is different for PowerShell 5 and 6+ 
        $hook = if ($PSVersionTable.PSVersion.Major -lt 6) { 'prompt' } else { 'pwd' }
        (zoxide init --hook $hook powershell | Out-String)
    })

    # If Zoxide is loaded and available replace "cd" with it
    Set-Alias -Name cd -Value z -Option AllScope
}catch{
    # Do Nothing
}

<# Environment Variables #>

# *** Fzf ***

# Colours - Uses Catppuccin theme from https://github.com/catppuccin/fzf
$ENV:FZF_DEFAULT_OPTS=@"
--color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8
--color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc
--color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8
"@

<# Globals #>
# Determine if the current user is elevated
$IsAdminSession =  ([Security.Principal.WindowsPrincipal] ([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# --- Prompt Globals --- #
# Each of the following variables are declared as global so that they can be modified outside of the prompt function
# Mainly used to cache values so that the prompt is not recalculated every time it is redrawn on a Vi mode change

# Vi Mode, false = insert mode, true = command mode
$ViCommandMode = $false  # Default to insert mode

# - Cached Values -
# Cached version of the first two lines of the prompt, used to redraw the prompt when the vi mode is changed
$CurrentPrompt = $null

# Width is checked to see if the window has been resized, if it has the prompt is recalculated
$LastHostWidth = $Host.UI.RawUI.WindowSize.Width 

# - Flags - 
# Set by OnViModeChange to prevent the prompt from being recalculated when the vi mode is changed
$IsPromptRedraw = $false

# --- Colour Globals --- #

# Catppuccin's Mocha theme
# URL: https://github.com/catppuccin/catppuccin
# Usage: $PSStyle.[Foreground/Background].FromRgb($CatppuccinMocha[<ColourName>])
$CatppuccinMocha = [ordered]@{
    # Colour Palette - 14 colours
    Rosewater = 0xf5e0dc
    Flamingo =  0xf2cdcd
    Pink =      0xf5c2e7
    Mauve =     0xcba6f7
    Red =       0xf38ba8
    Maroon =    0xeba0ac
    Peach =     0xfab387
    Yellow =    0xf9e2af
    Green =     0xa6e3a1
    Teal =      0x94e2d5
    Sky =       0x89dceb
    Sapphire =  0x74c7ec
    Blue =      0x89b4fa
    Lavender =  0xb4bef4

    # Grayscale Palette - 12 colours
    Text =      0xcdd6f4
    Subtext1 =  0xbac2de
    Subtext0 =  0xa6adc8
    Overlay2 =  0x9399b2
    Overlay1 =  0x7f849c
    Overlay0 =  0x6c7086
    Surface2 =  0x585b70
    Surface1 =  0x45475a
    Surface0 =  0x313244
    Base =      0x1e1e2e
    Mantle =    0x181825
    Crust =     0x11111b
}

################
# Prompt Setup #
################

function prompt {
    <# Heavily inspired by the 'ys' theme included with Oh-My-Zsh

    Instead of ys's $ prompt, I use a > for the prompt in vi insert mode and a < for the prompt in vi command mode

    Current Format:
    [NewLine]
    [Privelege] [User] @ [Host] in [Directory] [on [GitBranch] [GitStatus]] [Nesting Level] [Time] [ExitCode] Right Aligned -> [Execution Time (>=5s)] [NewLine]
    [Vi Mode/Prompt] #>

    # Check if the window has been resized
    if ($global:LastHostWidth -ne $Host.UI.RawUI.WindowSize.Width) {
        $global:LastHostWidth = $Host.UI.RawUI.WindowSize.Width
        $global:CurrentPrompt = $null # Force a recalculation of the prompt
    }

    # Only recalculate the prompt if it is not a redraw
    if ((-not $global:IsPromptRedraw) -or ($null -eq $global:CurrentPrompt)) {
        
        # --- Pre-Prompt ---
        # Gather values that may be updated before they are checked
        $CurrentExitCode = $global:LASTEXITCODE
        $CurrentExitCode ??= 0 # If $CurrentExitCode is null, set it to 0

        # --- Start Prompt ---

        # Start the prompt with a blank line to separate it from the previous command
        $BlankLine = "`n"

        # --- Left Status ---

        # ***User***
        # If the user is an admin, prefix the username with a red "#",otherwise prefix with a blue "$"
        # IsAdminSession is a global variable set in the prompt setup
        $LeftStatus = if ($IsAdminSession) { "$($PSStyle.Foreground.Red)% " } else { "$($PSStyle.Foreground.Blue)# " }

        # Username may be null, in this case derive the username from the name of the user's home folder (for WSL mainly)
        if($null -eq $env:UserName){
            $LeftStatus += "$($PSStyle.Foreground.Cyan)$($($env:Homepath | Split-Path -leaf)) "
        } else {
            $LeftStatus += "$($PSStyle.Foreground.Cyan)$($env:UserName) "
        }

        # ***Host***
        $LeftStatus += "$($PSStyle.Foreground.BrightBlack)@ $($PSStyle.Foreground.Green)$($env:COMPUTERNAME) "
        
        # ***Directory***
        $LeftStatus += "$($PSStyle.Foreground.BrightBlack)in $($PSStyle.Foreground.Yellow)$($(Get-Location).ToString().replace($env:HOMEDRIVE + $env:HOMEPATH, '~').replace('Microsoft.PowerShell.Core\FileSystem::', '')) "
        
        # ***Git***
        # If the current directory is a git repository, display the current branch
        if(($env:POSH_GIT_ENABLED -eq $true) -and ($status = Get-GitStatus -Force)){
            # Branch Name
            $LeftStatus += "$($PSStyle.Foreground.BrightBlack)on $($PSStyle.Foreground.White)git:$($PSStyle.Foreground.Cyan)$($status.Branch)"
            
            # Branch Status - Dirty (x) or Clean (o)
            $LeftStatus += if ($status.HasWorking) { "$($PSStyle.Foreground.Red) x " } else { "$($PSStyle.Foreground.Green) o " }
        }

        # ***Timestamp***
        # Use the cached timestamp to prevent the time from moving forward  
        $LeftStatus += "$($PSStyle.Foreground.BrightBlack)[$(Get-Date -Format "HH:mm:ss")] "

        # ***Nesting***
        # If the prompt is nested, display the nesting level
        if($nestedPromptLevel -gt 0){ # Don't display the nesting level if it is 0
            $LeftStatus += "$($PSStyle.Foreground.BrightWhite)L:$($PSStyle.Foreground.Yellow)$NestedPromptLevel "
        }

        # ys has a counter for the number of commands run here, but I don't see the point of it

        # ***Exit Code***
        if($CurrentExitCode -ne 0){ # Don't display the exit code if it is 0 (Success)
            $LeftStatus += "$($PSStyle.Foreground.BrightWhite)C:$($PSStyle.Foreground.Red)$CurrentExitCode "
        }

        # Since the left status is complete, trim the trailing space
        $LeftStatus = $LeftStatus.TrimEnd()

        # --- Right Status ---
        $RightStatus = ""

        # ***Duration***
        # Display the duration of the last command
        $LastCommandTime = Get-LastCommandDuration -MinimumSeconds 5

        if ($LastCommandTime -gt 0) {
            $RightStatus += "$($PSStyle.Foreground.BrightBlack)took $($PSStyle.Foreground.Magenta)$($LastCommandTime)"
        }

        # *** Padding ***
        # Pad the right side of the prompt right element appear on the right edge of the window
        # To determine the correct amount of padding we need to strip any ANSI escape sequences from the left and right status
        $AnsiRegex = "\x1b\[[0-9;]*m"
        $Padding = " " * ($Host.UI.RawUI.WindowSize.Width - (($LeftStatus -replace $AnsiRegex, "").Length + ($RightStatus -replace $AnsiRegex, "").Length))

        # --- End of Status Line ---

        # Cache the prompt
        $global:CurrentPrompt = $BlankLine + $LeftStatus + $Padding + $RightStatus + "`r"
    }

    # Write the cached prompt, will contain the recalculated prompt if it is not a redraw
    Write-Host -Object $global:CurrentPrompt

    # --- Prompt Line ---
    # NOTE: This section is run every time the prompt is redrawn

    # ***Prompt***
    # Determine the prompt character and colour based on the vi mode
    if ($global:ViCommandMode) {
        $PromptChar = "<"
        $PromptColor = "Blue"
    } else {
        $PromptChar = ">"
        $PromptColor = "Green"
    }

    # Write the prompt character - Using -ForegroundColor instead of $PSStyle.Foreground because PSReadLine doesn't seem to like PSStyle
    Write-Host -Object $PromptChar -NoNewline -ForegroundColor $PromptColor

    # Tell PSReadLine what the prompt character is
    Set-PSReadLineOption -PromptText "$PromptChar " 

    # Reset the exit code if it was updated by any of the above script
    $global:LASTEXITCODE = $CurrentExitCode

    # Reset the redraw flag
    $global:IsPromptRedraw = $false

    # Return a space to act as a proxy prompt character
    return ' '
}

<# PSReadLine #>

# Function to run every time the vi mode is changed
# Prompt: Green '>' for insert mode, blue '<' for command mode - both distinct from the red error prompt character
# Cursor: Blinking block for insert mode, blinking line for command mode
function OnViModeChange {
    # Suppress the warning as the global variables updated below are basically parameters for the prompt function
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "", Justification="Global variable is accessed from a different scope", Scope="Function")]
    param(
        [Parameter(ValueFromRemainingArguments=$true)]
        [string]$Mode
    )

    # Set the redraw flag so that the prompt isn't recalculated
    $global:IsPromptRedraw = $true

    # Set the global vi mode variable to the current mode
    $global:ViCommandMode = $Mode -eq 'Command' 

    # Change the cursor style
    Write-Host $(if ($global:ViCommandMode) { "`e[1 q" } else { "`e[5 q" })

    # Redraw the prompt
    [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()
}

# PSReadLine Options
$PSReadLineOptions = @{
    # Don't alert errors visually/audibly
    BellStyle = "None"

    # Set colours
    Colors = @{
        # Colour the continuation prompt cyan to keep it similar to yet distinct from both the command prompt and insert prompt
        ContinuationPrompt = "Cyan"
    }

    # Define string used as the continuation prompt
    ContinuationPrompt = "> "

    # Use vi-like command line editting
    EditMode = "Vi"

    # Prompt Spans multiple lines, required because InvokePrompt is used in OnViModeChange to modify the prompt
    # Currently blank line -> status line -> prompt line
    ExtraPromptLineCount = 2

    # Don't display duplicates in the history search
    HistoryNoDuplicates = $true

    # Move cursor to the end of the line when searching command history
    HistorySearchCursorMovesToEnd = $true

    # Display history search results and plugin suggestions together
    PredictionSource = "HistoryAndPlugin"
    
    # Render the predictions in a drop down list - use inline view in VSCode
    PredictionViewStyle = if ($env:TERM_PROGRAM -eq 'vscode') { "InlineView" } else { "ListView" }

    PromptText = "> "

    # Run a function whenever the vi mode is changed
    ViModeIndicator = "Script" 
    
    # Define which function will be called when the vi mode is changed
    ViModeChangeHandler = $Function:OnViModeChange
}

# Assign the above values
Set-PSReadLineOption @PSReadLineOptions

# Import the script that defines the key bindings
. "$PSScriptRoot\Bindings\PSReadLine.ps1"

<# PSStyle Options #>

# Set the PSStyle options if PSStyle is available, i.e. if the PSVersion is 7.2 or greater
if ($PSVersionTable.PSVersion.Major -gt 7 -or ($PSVersionTable.PSVersion.Major -eq 7 -and $PSVersionTable.PSVersion.Minor -ge 2)){

    # If the terminal supports OSC indicators, use the OSC progress bar - I only know of Windows Terminal supporting this
    if ($env:WT_SESSION) {
        $PSStyle.Progress.UseOSCIndicator = $true
    }

    $PSStyle.Formatting.TableHeader = "`e[33;3m" # Yellow Italics
}

#############
# Functions #
#############

# *** Terminal-Icons ***

function Update-TerminalIconsTheme{
    # Use Add-[x]Theme functions with -force to update the existing themes
    Add-TerminalIconsColorTheme  $($env:OneDriveConsumer + '\.config\Terminal-Icons\colorThemes\personal-theme.psd1') -force
    Add-TerminalIconsIconTheme $($env:OneDriveConsumer + '\.config\Terminal-Icons\iconThemes\personal-theme.psd1') -force

    # Apply the newly updated Themes
    Set-TerminalIconsTheme -ColorTheme personal-theme -IconTheme personal-theme
}

function Add-NewTerminalIcon{
    param(
        [Parameter(Mandatory)]
        [string]$Icon,

        [Parameter(Mandatory)]
        [string]$Colour
    )

    $valid = $true

    # Check if the icon is a valid glyph
    $glyphs = Invoke-Expression (Get-Content $($env:OneDriveConsumer + '\.config\Terminal-Icons\glyphs.ps1') | Out-String)
    if(-Not ($glyphs.ContainsKey($Icon))){
        Write-Host "Glyph not found." -ForegroundColor Red
        $valid = $false
    }

    # Check if the colour is in the correct format
    if($Colour -notmatch '[0-9a-fA-F]{6}'){
        Write-Host "Colour not in the correct format." -ForegroundColor Red
        $valid = $false
    }

    # Return if any of the above checks fail
    if(-Not $valid){
        return
    }

    # Update the Icon theme to reflect the changes
    Update-TerminalIconsTheme
}

# ***Alias Functions***

# TODO: Change the below functions to allow pass through of parameters to Get-ChildItem
# But I'm not doing it now because I can't fucking figure this shit out

# Make ll more like unix ls -l
function Get-ChildItemUnixStyleLong {
    Get-ChildItem -Exclude '_*', '.*', '#*', '$*' | Sort-Object { $_.GetType() }, Name | Format-Table -AutoSize
}

# Make ls more like unix ls
function Get-ChildItemUnixStyleShort {
    Get-ChildItem -Exclude '_*', '.*', '#*', '$*' | Sort-Object { $_.GetType() }, Name | Format-Wide -AutoSize
}

# Function for listing all the functions
function Get-ChildItemFunctions {
    Get-ChildItem Functions:\
}

# Function for listing all the aliases
function Get-ChildItemAliases {
    Get-ChildItem Alias:\
}

function Get-LastCommandDuration {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$IncludeMilliseconds = $false,

        [Parameter()]
        [int]$MinimumSeconds = 0
    )

    # Get the previously executed command
    $LastCommand = Get-History -Count 1

    # Don't do anything if the last command is null i.e on Shell startup
    if ($null -ne $LastCommand) {
        # Get the duration of the last command
        $Duration = $LastCommand.EndExecutionTime - $LastCommand.StartExecutionTime
        
        # Don't do anything if the duration is less than the minimum seconds
        if ($Duration.TotalSeconds -lt $MinimumSeconds) { return "" }

        # Initialise the duration text
        $DurationText = ""

        # Format the time in the format: 1d 2h 3m 4s [5ms]
        # Where the parts are only included if they are greater than 0
        if ($Duration.Days -gt 0) { $DurationText += "{0:N0}d" -f $Duration.Days }
        if ($Duration.Hours -gt 0) { $DurationText += "{0:N0}h " -f $Duration.Hours }
        if ($Duration.Minutes -gt 0) { $DurationText += "{0:N0}m " -f $Duration.Minutes }
        if ($Duration.Seconds -gt 0) { $DurationText += "{0:N0}s " -f $Duration.Seconds }
        if ($IncludeMilliseconds -and $Duration.Milliseconds -gt 0) { $DurationText += "{0:N0}ms" -f $Duration.Milliseconds }

        # Return the formatted time, trimming any trailing space
        return $($DurationText.Trim())
    }
}

function Invoke-FzfBat{
    fzf --preview 'bat --style=numbers --color=always --line-range :500 {}'
}

function Invoke-FzfTldr{
    tldr -l | fzf --preview 'tldr {} --color=always -p=windows | bat --color=always --language=man --plain' --preview-window '50%,rounded,<50(up,85%,border-bottom)' --prompt='ﳁ TLDR >'
}

function Invoke-FzfES{
    $es_args = ""
    if($args.Count -gt 0){
        # If there are any args pass them directly on to es.exe
        $es_args = $args
    }else{
        # Passing ES no args will list every file on the system which may take some time
        # So check if the user wants actually to do it
        $confirm = Read-Host "Do you really want to search all files? (Y/N)"

        if(-not $($($confirm -eq "Y") -or $($confirm -eq "y"))){
            return
        }
    }

    # Invoke es and pipe it to fzf
    es $es_args | fzf --preview 'bat --style=numbers --color=always --line-range :500 {}' --prompt=' ES >'
}

# List all updates available from WinGet
# Filter out any packages that don't have a version number similar to how "winget upgrade" works
function Get-WinGetUpdates {
    Get-WinGetPackage | Where-Object {($_.Version -ne "Unknown") -and $_.IsUpdateAvailable} | Select-Object -Property Name, Id, Version, @{Name="Latest Version";Expression={$_.AvailableVersions[0]}}
}

# Function to reset the Last exit code on a clear screen
function Clear-HostandExitCode {
    $global:LASTEXITCODE = 0
    Clear-Host
}

# Function to open the current profile in VSCode
function Edit-Profile {
    code $PROFILE
}

# Function to open the current profile folder in VSCode. Useful for editing included files
function Edit-ProfileFolder {
    code $PSScriptRoot
}

# Print blocks showing all of the colours in the Catppuccin Mocha theme
# I guess this could be used to test true colour support?
function Write-CatppuccinBlocks {
    foreach($Colour in $CatppuccinMocha.GetEnumerator()){
        Write-Host "$($PSStyle.Foreground.FromRgb($Colour.Value))███" -NoNewline
    }
}

function Get-BlockColour {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [object]$InputObject
    )
    process {
        Write-Host $_

        switch ($InputObject.GetType().FullName) {
            "System.Int32" { $($PSStyle | Select-Object -ExpandProperty $Position).FromRgb($InputObject) }
            "System.String" { $PSStyle | Select-Object -ExpandProperty $Position | Select-Object -ExpandProperty $InputObject }
        }
    }
}

function Get-BlockStyle {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [string]$InputObject
    )
    process {
        switch ($InputObject) {
            "Bold" { "$($PSStyle.Bold)" }
            "Underline" { "$($PSStyle.Underline)" }
            "Italic" { "$($PSStyle.Italic)" }
        }
    }
}

function Test-Shit {
    $Block = @{
        Condition = $true
        Highlight = @{ Foreground = "Red"
                       Background = 0x123456 
                       Style = "Bold", "Underline", "Italic" }
        ScriptBlock = { return "Hello World" }               
    }

    if ($Block.Condition) {
        $output = ""

        if ($Block.Highlight) {
            $hl = $Block.Highlight
            $output += Get-BlockColour @hl
        }

        if ($Block.Highlight.Style) {
            $output += $Block.Highlight.Style | Get-BlockStyle | ForEach-Object { return $_ }
        }

        $output += $($Block.ScriptBlock.Invoke())

        $output += $PSStyle.Reset

        Write-Host $output
    }
}

###########
# Aliases #
###########

# *** Built in ***

# Get-ChildItem
Set-Alias -Name ls -Value Get-ChildItemUnixStyleShort # TODO: make this show less details - more like ls in bash
Set-Alias -Name ll -Value Get-ChildItemUnixStyleLong # Should be similar to ls -l

# Get-ChilItem for non-filesystem items
Set-Alias -Name lf -Value Get-ChildItemFunctions # List all functions
Set-Alias -Name la -Value Get-ChildItemAliases # List all aliases

# Clear-Host
Set-Alias -Name clear -Value Clear-HostandExitCode # Reset the exit code on clear
Set-Alias -Name cls -Value Clear-HostandExitCode # Replace the built in cls alias - I don't use it
Set-Alias -Name cl -Value Clear-HostandExitCode # Shorter alias

# New-Item
Set-Alias -Name mk -Value New-Item # Similar to mkdir

# *** External Programs ***

# gsudo
Set-Alias -Name sudo -Value gsudo # I'd rather use sudo than gsudo
Set-Alias -Name su -Value gsudo # Shorter alias

# Python - 32 bit for test scripts
Set-Alias -Name py32 -Value $($env:LOCALAPPDATA + "\Programs\Python\Python37-32\python.exe")

# Winget
Set-Alias -Name wg -Value Winget # Shorter alias for cmd cli
Set-Alias -Name wgu -Value Get-WinGetUpdates # List all updates available from WinGet

# lazygit
Set-Alias -Name lg -Value lazygit

# *** Visual Studio ***

# Installed Visual Studio Versions
Set-Alias -Name vs22 -Value "C:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\IDE\devenv.exe" # 2022
Set-Alias -Name vs19 -Value "C:\Program Files (x86)\Microsoft Visual Studio\2019\Professional\Common7\IDE\devenv.exe" # 2019
Set-Alias -Name vs17 -Value "C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\Common7\IDE\devenv.exe" # 2017

# Cleaner alias for the latest version
Set-Alias -Name vs -Value vs22

# *** FZF ***

# Custom FZF Aliases
Set-Alias -Name fzfp -Value Invoke-FzfBat # fuzzy bat preview
Set-Alias -Name fzft -Value Invoke-FzfTldr # fuzzy tldr
Set-Alias -Name fzfe -Value Invoke-FzfES # fuzzy es

# Fuzzy package manager aliases
Set-Alias -Name fpi -Value Invoke-FuzzyPackageInstall # fuzzy package install
Set-Alias -Name fpr -Value Invoke-FuzzyPackageUninstall # fuzzy package uninstall (remove)
Set-Alias -Name fpu -Value Invoke-FuzzyPackageUpdate # fuzzy package update

<# Argument Compeleters #>

# Winget Argument Completer
Register-ArgumentCompleter -Native -CommandName winget, wg -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
        [Console]::InputEncoding = [Console]::OutputEncoding = $OutputEncoding = [System.Text.Utf8Encoding]::new()
        $Local:word = $wordToComplete.Replace('"', '""')
        $Local:ast = $commandAst.ToString().Replace('"', '""')
        winget complete --word="$Local:word" --commandline "$Local:ast" --position $cursorPosition | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
}

<# Final Setup #>
# Steps that must be completed after the rest of the profile has been processed

# ***Variables***

# Reset LASTEXITCODE so that no error code is displayed at the prompt on start up.
$LASTEXITCODE = 0