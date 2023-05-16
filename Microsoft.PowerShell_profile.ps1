################
# Profile Args #
################
<# 
    The following variables are used to configure the profile for different environments
    These are to be set by the user in their profile
#>

# Set to true to force the the use of ASCII characters in the prompt
$script:UseAscii = $false

# Flavour of Catppucin to use
$script:CatppuccinFlavour = 'Mocha'

################
# Module Setup #
################

# Variables required for importing modules

# Path to Scoop's installation directory
$script:ScoopHome = $($(Get-Item $(Get-Command scoop.ps1).Path).Directory.Parent.FullName)

# *** Function Modules ***

# PSReadLine
Import-Module -Name PSReadLine

# Load the CompletionPredictor module if PSVersion is 7.2 or higher
if ($PSVersionTable.PSVersion.Major -ge 7 -and $PSVersionTable.PSVersion.Minor -ge 2) {
    Import-Module -Name CompletionPredictor
}

# gsudo
Import-Module "$ScoopHome\apps\gsudo\current\gsudoModule.psd1"

# *** Style Modules ***

# Posh-Git - Variable used to determine if Posh-Git is loaded for use in the prompt
$env:POSH_GIT_ENABLED = [bool]$(Import-Module -Name posh-git -PassThru -ErrorAction SilentlyContinue)

# Terminal-Icons
Import-Module -Name Terminal-Icons

# *** Package Manager Modules ***

# Winget
Import-Module -Name Microsoft.WinGet.Client

# Chocolatey
Import-Module "$env:ChocolateyInstall\helpers\chocolateyInstaller.psm1"

# Scoop-completion: Auto-Completion for scoop 
Import-Module -Name Scoop-Completion

# posh-vcpkg
Import-Module "$ScoopHome\apps\vcpkg\current\scripts\posh-vcpkg"

# *** Other Modules ***

# Written by me

# NCR 
Import-Module Posh-NCR

# Fuzzy-Winget
Import-Module fuzzy-winget

# Catppuccin
Import-Module Catppuccin

<# External Programs #>

# Zoxide
try {
    # Load zoxide into the current session
    # This is a cut down version of the powershell init script from zoxide
    # I don't need Windows Powershell support in this profile
    Invoke-Expression (& { zoxide init --hook 'pwd' powershell | Out-String } ) 

    $ZoxideLoaded = $true
} catch {
    $ZoxideLoaded = $false
} finally {
    # Clear the error if it is just a zoxide error
    if ($Error.Count -eq 1 -and $Error[0].ToString().Contains('zoxide')) { $Error.Clear() }
}

# Source all of the scripts in the Autocompletion directory
Get-ChildItem -Path $PSScriptRoot\Autocompletion\*.ps1 | ForEach-Object { . $_.FullName }

<# Environment Variables #>

# Set the default encoding to UTF-8
$OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = New-Object System.Text.UTF8Encoding

# Max the history size to 2^15 - 1. Who gives a fuck about disk space? I don't
$MaximumHistoryCount = 32767

<# Globals #>
# Determine if the current user has elevated privileges
$IsAdminSession = ([Security.Principal.WindowsPrincipal]([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# --- Prompt Globals --- #
# Each of the following variables are declared as global so that they can be modified outside of the prompt function
# Mainly used to cache values so that the prompt is not recalculated every time it is redrawn on a Vi mode change

# Vi Mode, false = insert mode, true = command mode
$ViCommandMode = $false  # Default to insert mode

# - Cached Values -
# Cached version of the first two lines of the prompt, used to redraw the prompt when the vi mode is changed
$CurrentPrompt = $null # Default to null so that a fresh prompt will always be calculated at startup

# Width is checked to see if the window has been resized, if it has the prompt is recalculated
$LastHostWidth = $Host.UI.RawUI.WindowSize.Width 

# - Flags - 
# Set by OnViModeChange to prevent the prompt from being recalculated when the vi mode is changed
$IsPromptRedraw = $false

# - Prompt Configuration -
# The following variables are used to configure the prompt

# Hashtable of icons to use for the prompt
$PromptIcons = if (-not $global:UseAscii) {
    # Unicode icons - avoids nerd fonts for now
    @{
        # Debug icon
        Debug  = '!'

        # User type icons
        Admin  = '#'
        User   = '$'

        # Git status icons
        Git    = @{
            Clean       = 'o'
            Dirty       = 'x'
            Ahead       = '↑'
            Behind      = '↓'
            AheadBehind = '↕'
            Same        = '='
            Stash       = '*'
        }

        # Mode dependant prompt icons
        Prompt = @{
            Insert  = '>'
            Command = '<'
        }
    }
} else {
    # ASCII only icons
    @{    
        # Debug icon
        Debug  = '!'

        # User type icons
        Admin  = '#'
        User   = '$'

        # Git status icons
        Git    = @{
            Clean       = 'o'
            Dirty       = 'x'
            Ahead       = '>'
            Behind      = '<'
            AheadBehind = '<>'
            Same        = '='
            Stash       = '*'
        }

        # Mode dependant prompt icons
        Prompt = @{
            Insert  = '>'
            Command = '<'
        }
    }
}

# --- Colour Globals --- #
$global:Flavour = $Catppuccin[$script:CatppuccinFlavour]

# FZF Colours - Reimplementation and extension of the Catppuccin theme from https://github.com/catppuccin/fzf
$ENV:FZF_DEFAULT_OPTS = @"
--color=bg+:$($global:Flavour.Surface0),bg:$($global:Flavour.Base),spinner:$($global:Flavour.Rosewater)
--color=hl:$($global:Flavour.Red),fg:$($global:Flavour.Text),header:$($global:Flavour.Red)
--color=info:$($global:Flavour.Mauve),pointer:$($global:Flavour.Rosewater),marker:$($global:Flavour.Rosewater)
--color=fg+:$($global:Flavour.Text),prompt:$($global:Flavour.Mauve),hl+:$($global:Flavour.Red)
--color=border:$($global:Flavour.Surface2)
"@

# --- Module Configuration --- #
# The following variables are used to configure the modules

# Enable the checking of stash status in Posh-Git
$GitPromptSettings.EnableStashStatus = $true

################
# Prompt Setup #
################

function prompt {
    <#
    .SYNOPSIS
        Custom PowerShell prompt
    
    .DESCRIPTION
        Custom PowerShell prompt. Heavily inspired by the 'ys' theme included with Oh-My-Zsh/Oh-My-Posh,

        REQUIRED MODULES:
        - Catppuccin - for the colours
        - Posh-Git - for the git branch and status
        - PSReadLine - required for the accompanying OnViModeChanged Function to force a prompt redraw

        CUSTOM ELEMENTS:
        On top of 'ys', I have added the following elements:

        Debug:
        If the current session is in debug mode, the prompt will be prefixed with "[!]" in red.
        
        Prompt:
        Instead of ys's $ prompt, I use a > for the prompt in vi insert mode and a < for the prompt in vi command 
        mode.

        Time:
        I have also added an execution time to the prompt if the execution time is >= 5 seconds. This is placed at 
        the end of the prompt and is right aligned.

        Git Status:
        I have enhanced the git status to include more information. The git status is displayed in the following
        format: 
            
            git:[branch] [[clean|dirty] [ahead|behind] [stash]].

        Where:
            branch - The current branch
            clean/dirty - Whether the working directory is clean or dirty (o = clean, x = dirty)
            ahead/behind - Whether the current branch is ahead or behind the remote (↑ = ahead, ↓ = behind)
            stash - Whether there are stashed changes (* = stashed)
        

        CURRENT FORMAT:
        [NewLine]
        Left Aligned  -> [Debug] [Privilege] [User] @ [Host] in [Directory] [on [GitBranch] [GitStatus]] 
                      -> [Nesting Level] [ExitCode] 
        Right Aligned -> [Execution Time (if >= 5s)] [Time] [NewLine]
        [Vi Mode/Prompt] 
    #>

    # Check if the window has been resized
    if ($global:LastHostWidth -ne $Host.UI.RawUI.WindowSize.Width) {
        $global:LastHostWidth = $Host.UI.RawUI.WindowSize.Width
        $global:CurrentPrompt = $null # Force a recalculation of the prompt
    }

    # Only recalculate the prompt if it is not a redraw
    if ((-not $global:IsPromptRedraw) -or ($null -eq $global:CurrentPrompt)) {
        # --- Pre-Prompt ---

        # Gather values that may be updated before they are checked
        $private:CurrentExitCode = $global:LASTEXITCODE
        $private:CurrentExitCode ??= 0 # If $CurrentExitCode is null, set it to 0

        # --- Start Prompt ---

        # If the prompt is being drawn at the top of screen, omit the blank line
        if ($Host.UI.RawUI.CursorPosition.Y -eq 0) {
            $private:BlankLine = '' 
            Set-PSReadLineOption -ExtraPromptLineCount 1
        } else {
            $private:BlankLine = "`n"
            Set-PSReadLineOption -ExtraPromptLineCount 2
        }

        # --- Left Status ---

        # ***Debug***
        # If the $PSDebugContext variable is set, the user is in debug mode, prefix the prompt with a red "!"
        # NOTE: This seems to be flaky, sometimes it is set, sometimes it is not
        $private:LeftStatus = if (Test-Path 'Variable:\PSDebugContext') {
            "$($global:Flavour.Surface2.Foreground())[" + 
            "$($global:Flavour.Red.Foreground())$($PSStyle.Bold)$($PromptIcons.Debug)$($PSStyle.BoldOff)" +
            "$($global:Flavour.Surface2.Foreground())] "
        }

        # ***User***
        # If the user is an admin, prefix the username with a red "#",otherwise prefix with a blue "$"
        # IsAdminSession is a global variable set in the prompt setup
        $private:LeftStatus += if ($IsAdminSession) { 
            "$($global:Flavour.Red.Foreground())$($PromptIcons.Admin) "
        } else {
            "$($global:Flavour.Blue.Foreground())$($PromptIcons.User) "
        }

        # Username may be null, in this case derive the username from the name of the user's home folder 
        # Seems to be required when running pwsh.exe from within WSL mainly
        $private:LeftStatus += if ($null -eq $env:UserName) {
            "$($global:Flavour.Teal.Foreground())$($($env:Homepath | Split-Path -Leaf)) "
        } else {
            "$($global:Flavour.Teal.Foreground())$($env:UserName) "
        }

        # ***Host***
        $private:LeftStatus += "$($global:Flavour.Surface2.Foreground())@ " + 
        "$($global:Flavour.Green.Foreground())$($env:COMPUTERNAME) "
        
        # ***Location***
        $private:LeftStatus += "$($global:Flavour.Surface2.Foreground())in " + 
        "$($global:Flavour.Yellow.Foreground())$(Get-LocationFormatted -TruncateLength 2) "
        
        # ***Git***
        # If the current directory is a git repository, display the current branch
        if ($env:POSH_GIT_ENABLED -and ($private:GitStatus = Get-GitStatus -Force)) {
            # Branch Name
            $private:LeftStatus += "$($global:Flavour.Surface2.Foreground())on " +
            "$($global:Flavour.Text.Foreground())git:$($global:Flavour.Sapphire.Foreground())$($status.Branch) "
            
            # Status section
            $private:LeftStatus += "$($global:Flavour.Surface2.Foreground())["
            
            # Branch Status - Dirty (x) or Clean (o)
            $private:LeftStatus += if ($private:GitStatus.HasWorking) { 
                "$($global:Flavour.Red.Foreground())$($PromptIcons.Git.Dirty)" 
            } else {
                "$($global:Flavour.Green.Foreground())$($PromptIcons.Git.Clean)"
            }

            # Branch Status - Ahead (↑) or Behind (↓) or Both (↕) or Same (=)
            $private:LeftStatus += if ($private:GitStatus.AheadBy -gt 0) {
                if ($private:GitStatus.BehindBy -gt 0) {
                    " $($global:Flavour.Yellow.Foreground())$($PromptIcons.Git.AheadBehind)"
                } else {
                    " $($global:Flavour.Green.Foreground())$($PromptIcons.Git.Ahead)"
                }
            } elseif ($private:GitStatus.BehindBy -gt 0) {
                " $($global:Flavour.Red.Foreground())$($PromptIcons.Git.Behind)"
            } else {
                " $($global:Flavour.Sapphire.Foreground())$($PromptIcons.Git.Same)"
            }

            # Branch Status - Has stashed changes (*)
            $private:LeftStatus += if ($private:GitStatus.StashCount -gt 0) {
                " $($global:Flavour.Sky.Foreground())$($PromptIcons.Git.Stash)"
            }

            # End of Status section
            $private:LeftStatus += "$($global:Flavour.Surface2.Foreground())] "
        }

        # ***Nesting***
        # If the prompt is nested, display the nesting level
        $private:LeftStatus += if ($nestedPromptLevel -gt 0) {
            # Don't display the nesting level if it is 0
            "$($global:Flavour.Text.Foreground())L:$($global:Flavour.Yellow.Foreground())$NestedPromptLevel "
        }

        # ys has a counter for the number of commands run here, but I don't see the point of it

        # ***Exit Code***
        $private:LeftStatus += if ($CurrentExitCode -ne 0) {
            # Don't display the exit code if it is 0 (Success)
            "$($global:Flavour.Text.Foreground())C:$($global:Flavour.Red.Foreground())$private:CurrentExitCode "
        } elseif (-not $?) {
            # If the last command failed, but the exit code is 0, display a question mark
            "$($global:Flavour.Text.Foreground())C:$($global:Flavour.Red.Foreground())? "
        }

        # Since the left status is complete, trim the trailing space
        $private:LeftStatus = $private:LeftStatus.TrimEnd()

        # --- Right Status ---

        # ***Duration***
        # Display the duration of the last command
        $private:LastCommandTime = Get-LastCommandDuration -MinimumSeconds 5

        $private:RightStatus = if ($private:LastCommandTime -gt 0) {
            "$($global:Flavour.Surface2.Foreground())took " + 
            "$($global:Flavour.Mauve.Foreground())$($private:LastCommandTime) "
        }

        # ***Timestamp*** 
        $private:RightStatus += "$($global:Flavour.Surface2.Foreground())[" + 
        "$($global:Flavour.Lavender.Foreground())$(Get-Date -Format 'HH:mm:ss')" + 
        "$($global:Flavour.Surface2.Foreground())] "

        # Since the right status is complete, trim the trailing space
        $private:RightStatus = $private:RightStatus.TrimEnd()

        # *** Padding ***
        # Pad the right side of the prompt right element so they appear on the right edge of the window
        # To determine the correct amount of padding we need to strip any ANSI escape sequences from the left and 
        # right status segments
        $private:AnsiRegex = '\x1b\[[0-9;]*m'
        $private:Padding = ' ' * ($Host.UI.RawUI.WindowSize.Width - 
            (($private:LeftStatus -replace $private:AnsiRegex, '').Length + 
            ($private:RightStatus -replace $private:AnsiRegex, '').Length))

        # --- End of Status Line ---

        # Combine and cache the prompt
        $global:CurrentPrompt = $private:BlankLine + 
            $private:LeftStatus + 
            $private:Padding + 
            $private:RightStatus + "`r"
    }

    # Write the cached prompt, will contain the recalculated prompt if it is not a redraw
    Write-Host -Object $global:CurrentPrompt

    # --- Prompt Line ---
    # NOTE: This section is run every time the prompt is redrawn

    # ***Prompt***
    # Determine the prompt character and colour based on the vi mode
    if ($global:ViCommandMode) {
        $private:PromptChar = $PromptIcons.Prompt.Command
        $private:PromptColor = 'Blue'
    } else {
        $private:PromptChar = $PromptIcons.Prompt.Insert
        $private:PromptColor = 'Green'
    }

    # Write the prompt character 
    # Using -ForegroundColor instead of $PSStyle.Foreground because PSReadLine doesn't seem to like PSStyle
    Write-Host -Object $private:PromptChar -NoNewline -ForegroundColor $private:PromptColor

    # Tell PSReadLine what the prompt character is
    Set-PSReadLineOption -PromptText "$private:PromptChar " 

    # Reset the exit code if it was updated by any of the above script
    $global:LASTEXITCODE = $private:CurrentExitCode

    # Reset the redraw flag
    $global:IsPromptRedraw = $false

    # Return a space to act as a proxy prompt character
    return ' '
}

<# PSReadLine #>

# Function to run every time the vi mode is changed
# Prompt: Green '>' for insert mode, blue '<' for command mode - both distinct from the red error prompt character
# Cursor: Blinking block for command mode, blinking line for insert mode
function OnViModeChange {
    # Suppress the warning as the global variables updated below are basically parameters for the prompt function
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', 
        Justification = 'Global variable is accessed from a different scope', Scope = 'Function')]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
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
    BellStyle                     = 'None'

    # Set colours
    Colors                        = @{
        # Largely based on the proposed Code Editor style guide in pr #1997 in the Catppuccin/Catppuccin repo
        # Emphasis, ListPrediction and ListPredictionSelected are inspired by the Catppuccin fzf theme
        
        # Powershell colours
        ContinuationPrompt     = $global:Flavour.Teal.Foreground()
        Emphasis               = $global:Flavour.Red.Foreground()
        Selection              = $global:Flavour.Surface0.Background()
        
        # PSReadLine prediction colours
        InlinePrediction       = $global:Flavour.Overlay0.Foreground()
        ListPrediction         = $global:Flavour.Mauve.Foreground()
        ListPredictionSelected = $global:Flavour.Surface0.Background()

        # Syntax highlighting
        Command                = $global:Flavour.Blue.Foreground()
        Comment                = $global:Flavour.Overlay0.Foreground()
        Default                = $global:Flavour.Text.Foreground()
        Error                  = $global:Flavour.Red.Foreground()
        Keyword                = $global:Flavour.Mauve.Foreground()
        Member                 = $global:Flavour.Rosewater.Foreground()
        Number                 = $global:Flavour.Peach.Foreground()
        Operator               = $global:Flavour.Sky.Foreground()
        Parameter              = $global:Flavour.Pink.Foreground() # I prefer this to the proposed Flamingo colour
        String                 = $global:Flavour.Green.Foreground()
        Type                   = $global:Flavour.Yellow.Foreground()
        Variable               = $global:Flavour.Lavender.Foreground()
    }

    # Define string used as the continuation prompt
    ContinuationPrompt            = '> '

    # Use vi-like command line editting
    EditMode                      = 'Vi'

    # Prompt Spans multiple lines, required because InvokePrompt is used in OnViModeChange to modify the prompt
    # Currently blank line -> status line -> prompt line
    # This value is updated in OnViModeChange
    ExtraPromptLineCount          = 1

    # Don't display duplicates in the history search
    HistoryNoDuplicates           = $true

    # Move cursor to the end of the line when searching command history
    HistorySearchCursorMovesToEnd = $true

    # Increase the number of history items stored
    MaximumHistoryCount           = $MaximumHistoryCount # I think it does this by default, but just in case

    # Display history search results and plugin suggestions together
    PredictionSource              = 'HistoryAndPlugin'
    
    # Render the predictions in a drop down list - use inline view in VSCode
    PredictionViewStyle           = if ($env:TERM_PROGRAM -eq 'vscode') { 'InlineView' } else { 'ListView' }

    # This is likely to be changed before it's ever read by PSReadLine, but it's here just in case
    PromptText                    = '> '

    # Run a function whenever the vi mode is changed
    ViModeIndicator               = 'Script' 
    
    # Define which function will be called when the vi mode is changed
    ViModeChangeHandler           = $Function:OnViModeChange
}

# Assign the above values
Set-PSReadLineOption @PSReadLineOptions

# Import the script that defines the key bindings
. "$PSScriptRoot\Bindings\PSReadLine.ps1"

<# PSStyle Options #>

# Set the PSStyle options if PSStyle is available, i.e. if the PSVersion is 7.2 or greater
if ($PSVersionTable.PSVersion.Major -gt 7 -or ($PSVersionTable.PSVersion.Major -eq 7 -and $PSVersionTable.PSVersion.Minor -ge 2)) {

    # If the terminal supports OSC indicators, use the OSC progress bar - I only know of Windows Terminal supporting this
    if ($env:WT_SESSION) {
        $PSStyle.Progress.UseOSCIndicator = $true
    }

    # Set the colours for the various formatting types
    $PSStyle.Formatting.Debug = $global:Flavour.Sky.Foreground()
    $PSStyle.Formatting.Error = $global:Flavour.Red.Foreground()
    $PSStyle.Formatting.ErrorAccent = $global:Flavour.Blue.Foreground()
    $PSStyle.Formatting.FormatAccent = $global:Flavour.Teal.Foreground()
    $PSStyle.Formatting.TableHeader = $global:Flavour.Rosewater.Foreground()
    $PSStyle.Formatting.Verbose = $global:Flavour.Yellow.Foreground()
    $PSStyle.Formatting.Warning = $global:Flavour.Peach.Foreground()
}

#############
# Functions #
#############

# ***Alias Functions***

# NOTE: This is good now
function Get-ChildItemUnixStyle {
    [CmdletBinding()]
    param(
        # --- Normal Parameters ---
        # The following parameters are identical to their Get-ChildItem Exquivalents
        [Parameter(Position = 0)]
        [string[]]$Path,

        [Parameter(Position = 1)]
        [string]$Filter,

        [string[]]$Include,

        [string[]]$Exclude,

        [switch]$Recurse,

        [uint]$Depth,

        [switch]$Force,

        [switch]$Name,

        # --- Extra Parameters ---

        # If not set the extra exclude parameters are added. Functionally similar to ls -a
        [switch]$All
    )

    if (-not $All) {
        # Add the extra exclude parameters
        # _* is for windows hidden files - Not common but I've seen it
        # .* is for unix hidden files - The gold standard
        # #* and $* are for the decoy files created by Carbon Black
        $Exclude += @('_*', '.*', '#*', '$*')
    } 

    # If -Recurse is set and -Depth is 0 then max -Depth so -Recurse will operate properly
    if ($Recurse -and $Depth -eq 0) {
        $Depth = [uint]::MaxValue
    }

    # Splatting Hashtable
    $GCIArgs = @{
        'Path'    = $Path
        'Filter'  = $Filter
        'Include' = $Include
        'Exclude' = $Exclude
        'Recurse' = $Recurse
        'Depth'   = $Depth
        'Force'   = $Force
        'Name'    = $Name
    }

    # Sort by type then name becuase I think exclude can mess with the default sort order, which this restores
    Get-ChildItem @GCIArgs | Sort-Object { $_.GetType() }, Name
}

# Make ll more like unix ls -l
function Get-ChildItemUnixStyleLong {
    Get-ChildItemUnixStyle @args | Format-Table -AutoSize 
}

# Make ls more like unix ls
function Get-ChildItemUnixStyleShort {
    Get-ChildItemUnixStyle @args | Format-Wide -AutoSize
}

# Make lla more like unix ls -la
function Get-ChildItemUnixStyleLongAll {
    # Ensure the args don't contain -All.
    $filteredArgs = $args | Where-Object { $_ -notmatch '-[aA][lL]{0,2}' }
    Get-ChildItemUnixStyleLong @filteredArgs -All
}

# Make la more like unix ls -a
function Get-ChildItemUnixStyleShortAll {
    # Ensure the args don't contain -All. 
    $filteredArgs = $args | Where-Object { $_ -notmatch '-[aA][lL]{0,2}' } 
    Get-ChildItemUnixStyleShort @filteredArgs -All
}

function Get-Tree {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        # The path to get the tree of
        [string]$Path = $PWD.Path,

        [Alias('f')] # Alias so that it's similar to tree /F
        [Parameter()]
        # Include files in the output
        [switch]$IncludeFiles
    )

    # Define the recursive function
    function Get-TreeRecursor($Path, $IndentString, $GetFiles) {
        # Get the contents of the path
        $Directories = Get-ChildItem -Directory $Path

        # If the -IncludeFiles switch is set, include files in the output
        if ($GetFiles) {
            $Files = Get-ChildItem -File $Path
        } else {
            $Files = @()
        }

        # Directories first
        foreach ($Directory in $Directories) {
            # Get the icon from TerminalIcons - strip one of the spaces after the icon
            $IconText = ($Directory | Format-TerminalIcons) -replace '(.*?)  (.*)', '$1 $2'
            
            # If the directory is the last directory and there are no files, print a closing icon
            if ($Directory -eq $Directories[-1] -and !$Files) {
                # Print the indent string, the pointer line icon and the directory name
                Write-Output "$IndentString└─ $IconText"
    
                # Call the function recursively to print the contents of the directory
                Get-TreeRecursor $Directory.FullName ($IndentString + '   ') $GetFiles
            } else {
                # Otherwise print a t-junction icon
                Write-Output "$IndentString├─ $IconText"
                Get-TreeRecursor $Directory.FullName ($IndentString + '│  ') $GetFiles
            }
        }
        
        # Then files - As above
        foreach ($File in $Files) {
            $IconText = ($File | Format-TerminalIcons) -replace '(.*?)  (.*)', '$1 $2'
            if ($File -eq $Files[-1]) {
                Write-Output "$IndentString└─ $IconText"
            } else {
                Write-Output "$IndentString├─ $IconText"
            }
        }
    }

    # Write then name and icon of the root directory
    Write-Output "`n$((Get-Item $Path | Format-TerminalIcons) -replace '(.*?)  (.*)', '$1 $2')"

    # Call the recursive function
    Get-TreeRecursor $Path '' $IncludeFiles
}



# Function for listing all the functions
function Get-ChildItemFunctions {
    Get-ChildItem Function:\
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
        if ($Duration.TotalSeconds -lt $MinimumSeconds) { return '' }

        # Initialise the duration text
        $DurationText = ''

        # Format the time in the format: 1d 2h 3m 4s [5ms]
        # Where the parts are only included if they are greater than 0
        if ($Duration.Days -gt 0) { $DurationText += '{0:N0}d' -f $Duration.Days }
        if ($Duration.Hours -gt 0) { $DurationText += '{0:N0}h ' -f $Duration.Hours }
        if ($Duration.Minutes -gt 0) { $DurationText += '{0:N0}m ' -f $Duration.Minutes }
        if ($Duration.Seconds -gt 0) { $DurationText += '{0:N0}s ' -f $Duration.Seconds }
        if ($IncludeMilliseconds -and $Duration.Milliseconds -gt 0) { $DurationText += '{0:N0}ms' -f $Duration.Milliseconds }

        # Return the formatted time, trimming any trailing space
        return $($DurationText.Trim())
    }
}

function Get-LocationFormatted {
    <#
    .SYNOPSIS
        Returns the current location in a formatted string

    .DESCRIPTION
        Returns the current location in a formatted string. Intended to be printed in the prompt.

        Shortens the path if it is too long, truncating each segment to $TruncateLength characters.

        The Current Directory is always displayed in full and in bold.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)] # TruncateLength must be greater than 0
        [int]$TruncateLength = 1,

        [Parameter()]
        [ValidateRange(0, 1)] # MaxDirLengthPercent must be between 0 and 1
        [double]$MaxDirLengthPercent = 0.30
    )

    $Location = $(Get-Location).ToString()

    # Clean up the location string
    $Location = $Location.replace($env:HOMEDRIVE + $env:HOMEPATH, '~') 
    $Location = $Location.replace('Microsoft.PowerShell.Core\FileSystem::', '') 

    # If the location is too long, shorten it 
    if ($Location.Length -gt ($Host.UI.RawUI.WindowSize.Width * $MaxDirLengthPercent)) {
        $SplitLocation = $Location.Split('\')

        # If the path is only one segment long, return the full path (e.g. C:\ or ~)
        if ($SplitLocation.Length -eq 1) {
            return $Location
        }

        # First part of the path is always included, should be the drive letter or ~
        $Location = $SplitLocation[0] + '\'

        # Add the $TruncateLength letters of each folder in the path
        for ($i = 1; $i -lt $SplitLocation.Length - 1; $i++) {
            $Location += $($SplitLocation[$i][0..($TruncateLength - 1)] -join '') + '\'
        }

        # Add the last folder in the path in bold
        $Location += $PSStyle.Bold + $SplitLocation[-1] + $PSStyle.BoldOff
    } else {
        # If the path is short enough, just bold the last folder
        $Index = $Location.LastIndexOf('\')
        $Location = $Location.Substring(0, $Index + 1) + 
        $PSStyle.Bold + $Location.Substring($Index + 1) + $PSStyle.BoldOff
    }

    return $Location
}

function Invoke-HexylBat {
    hexyl.exe $args --terminal-width=$($Host.UI.RawUI.WindowSize.Width) | bat.exe --color=always --plain
}

function Invoke-FzfBat {
    fzf --preview 'bat --style=numbers --color=always --line-range :500 {}'
}

function Invoke-FzfTldr {
    tldr -l | fzf --preview 'tldr {} --color=always -p=windows | bat --color=always --language=man --plain' `
        --preview-window '50%,rounded,<50(up,85%,border-bottom)' --prompt='ﳁ TLDR >'
}

function Invoke-FzfES {
    $es_args = ''
    if ($args.Count -gt 0) {
        # If there are any args pass them directly on to es.exe
        $es_args = $args
    } else {
        # Passing ES no args will list every file on the system which may take some time
        # So check if the user wants to do it
        $confirm = Read-Host 'Do you really want to search all files? (Y/N)'

        if (-not $($($confirm -eq 'Y') -or $($confirm -eq 'y'))) {
            return
        }
    }

    # Invoke es and pipe it to fzf
    es $es_args | fzf --preview 'bat --style=numbers --color=always --line-range :500 {}' --prompt=' ES >'
}

function Find-File ($Name) {
    <# 
    .SYNOPSIS
        Similar to unix find command
    #>
    Get-ChildItem -Recurse -Filter "*${Name}*" -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Output $_.FullName
    }
}

# List all updates available from WinGet
# Filter out any packages that don't have a version number similar to how "winget upgrade" works
function Get-WinGetUpdates {
    Get-WinGetPackage | 
        Where-Object { ($_.Version -ne 'Unknown') -and $_.IsUpdateAvailable } |
        Select-Object -Property Name, Id, Version, @{ Name = 'Latest Version'; Expression = { $_.AvailableVersions[0] } }
}

# Function to reset the Last exit code on a clear screen
function Clear-HostandExitCode {
    $global:LASTEXITCODE = 0
    Clear-Host
}

# *** Profile Maniuplation ***

# Function to open the current profile in VSCode
function Edit-Profile {
    code $PROFILE
}

# Function to open the current profile folder in VSCode. Useful for editing included files
function Edit-ProfileFolder {
    code $PSScriptRoot
}

# Function to reload the current profile
function Invoke-Profile {
    & $PROFILE
}

# *** Window Maniuplation ***

# Set the window title 
function Set-WindowTitle {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Title = 'PowerShell',

        # If true, the new title will be prepended to the current title
        [switch]$Prepend 
    )
    process {
        $Host.UI.RawUI.WindowTitle = $Title + $( if ($Prepend) { ' - ' + $Host.UI.RawUI.WindowTitle } )
    }
}

function Reset-WindowTitle {
    Set-WindowTitle # No args will reset the title to the default
}

# *** System Maniuplation ***

# -- wrapper functions for shutdown.exe --
function Stop-System {
    # Shutdown the system by calling the shutdown.exe command
    shutdown.exe /s /t 0
}

function Restart-System {
    # Restart the system by calling the shutdown.exe command
    shutdown.exe /r /t 0
}

function Disconnect-UserSession {
    # Log off the current user by calling the shutdown.exe command
    shutdown.exe /l /t 0
}

function Lock-System {
    # Lock the system by calling the LockWorkStation function
    rundll32.exe user32.dll, LockWorkStation
}



###########
# Aliases #
###########

# *** Built in ***

# Set-Location
if ($ZoxideLoaded) {
    # If Zoxide is loaded and available replace "cd" with it
    # This can be done safely because Zoxide will pass through to the original Set-Location when appropriate
    Set-Alias -Name cd -Value z -Option AllScope
    Set-Alias -Name sl -Value z -Option AllScope -Force # Force for read-only sl alias

    # Interactive version of zoxide using fzf
    Set-Alias -Name cdi -Value zi -Option AllScope
    Set-Alias -Name sli -Value zi -Option AllScope
}

# Get-ChildItem
Set-Alias -Name ls -Value Get-ChildItemUnixStyleShort # Like ls
Set-Alias -Name ll -Value Get-ChildItemUnixStyleLong # Like ls -l

Set-Alias -Name la -Value Get-ChildItemUnixStyleShortAll # Like ls -a
Set-Alias -Name lla -Value Get-ChildItemUnixStyleLongAll # Like ls -la

Set-Alias -Name lt -Value Get-Tree # Like exa --tree

# Get-ChildItem for non-filesystem items
Set-Alias -Name gfns -Value Get-ChildItemFunctions # List all functions
Set-Alias -Name gals -Value Get-ChildItemAliases # List all aliases

# Clear-Host
Set-Alias -Name clear -Value Clear-HostandExitCode # Reset the exit code on clear
Set-Alias -Name cls -Value Clear-HostandExitCode # Replace the built in cls alias - I don't use it
Set-Alias -Name cl -Value Clear-HostandExitCode # Shorter alias

# New-Item
Set-Alias -Name mk -Value New-Item # Similar to mkdir

# *** Custom Functions ***

# Find-File
Set-Alias -Name find -Value Find-File # Similar to unix find command [HIDES FIND.EXE]

# Set-WindowTitle and Reset-WindowTitle
Set-Alias -Name swt -Value Set-WindowTitle # Set the window title
Set-Alias -Name rwt -Value Reset-WindowTitle # Reset the window title

# *** External Programs ***

# gsudo
Set-Alias -Name sudo -Value gsudo # I'd rather use sudo than gsudo
Set-Alias -Name su -Value gsudo # Shorter alias

# Python
Set-Alias -Name py -Value python # Default python
Set-Alias -Name py32 -Value $($env:LOCALAPPDATA + '\Programs\Python\Python37-32\python.exe') # 32 bit python

# Winget
Set-Alias -Name wg -Value Winget # Shorter alias for cmd cli
Set-Alias -Name wgu -Value Get-WinGetUpdates # List all updates available from WinGet

# lazygit
Set-Alias -Name lg -Value lazygit

# *** Visual Studio ***

# Installed Visual Studio Versions
Set-Alias -Name vs22p -Value 'C:\Program Files\Microsoft Visual Studio\2022\Preview\Common7\IDE\devenv.exe' # 2022 Preview
Set-Alias -Name vs22 -Value 'C:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\IDE\devenv.exe' # 2022
Set-Alias -Name vs19 -Value 'C:\Program Files (x86)\Microsoft Visual Studio\2019\Professional\Common7\IDE\devenv.exe' # 2019
Set-Alias -Name vs17 -Value 'C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\Common7\IDE\devenv.exe' # 2017

# Cleaner alias for the latest version
Set-Alias -Name vs -Value vs22

# *** FZF ***

# Custom FZF Aliases
Set-Alias -Name fzfp -Value Invoke-FzfBat # fuzzy bat preview
Set-Alias -Name fzft -Value Invoke-FzfTldr # fuzzy tldr
Set-Alias -Name fzfe -Value Invoke-FzfES # fuzzy es

# *** Bat/Hexyl ***
Set-Alias -Name hb -Value Invoke-HexylBat # Hexyl piped into bat for paging. hb for hexyl bat

<# Final Setup #>
# Steps that must be completed after the rest of the profile has been processed

# *** Style ***

# Set the window title to the format [Admin:] PowerShell [Version]
Set-WindowTitle $('{0}PowerShell {1}' -f $(if ($IsAdminSession) { 'Admin: ' }), $PSVersionTable.PSVersion.ToString())

# ***Variables***

# Reset LASTEXITCODE so that no error code is displayed at the prompt on start up.
$LASTEXITCODE = 0