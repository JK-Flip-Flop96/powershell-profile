<# Import Modules #>

# *** Function Modules ***

# PSReadLine
Import-Module PSReadLine

# Load the CompletionPredictor module if PSVersion is 7.2 or higher
if ($PSVersionTable.PSVersion.Major -ge 7 -and $PSVersionTable.PSVersion.Minor -ge 2) {
    Import-Module -Name CompletionPredictor
}

# gsudo
Import-Module "$env:USERPROFILE\scoop\apps\gsudo\current\gsudoModule.psd1"

# *** Style Modules ***

# Posh-Git
Import-Module posh-git

# Terminal-Icons
Import-Module -Name Terminal-Icons

# *** Package Manager Modules ***

# Winget
Import-Module Microsoft.WinGet.Client

# Chocolatey
Import-Module "$env:ChocolateyInstall\helpers\chocolateyInstaller.psm1"

# Scoop-completion: Auto-Completion for scoop 
Import-Module "$($(Get-Item $(Get-Command scoop.ps1).Path).Directory.Parent.FullName)\modules\scoop-completion"

# posh-vcpkg
Import-Module 'C:\tools\vcpkg\scripts\posh-vcpkg'

# *** Other Modules ***

# NCR 
Import-Module Posh-NCR

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

# *** Posh-Git ***

$ENV:POSH_GIT_ENABLED = $true

# *** Fzf ***

# Colours - Uses Catppuccin theme from https://github.com/catppuccin/fzf
$ENV:FZF_DEFAULT_OPTS=@"
--color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8
--color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc
--color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8
"@

<# Globals #>
# Determine if the current user is elevated
$isAdmin =  ([Security.Principal.WindowsPrincipal] ([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

<# oh-my-posh #>
try{
    oh-my-posh --init --shell pwsh --config ~/jandedobbeleer.omp.json | Invoke-Expression
    Set-PoshPrompt -Theme ys
}catch{
    # If oh-my-posh intialisation fails, reimplement the included "ys" theme in a prompt function as a stand-in
    function prompt {
        # Gather values that may be updated before they are checked
        $currentExitCode = $global:LASTEXITCODE.ToString()

        # Take a new line
        Write-Host ''

        # ***User*** 
        if($isAdmin){
            Write-Host '% ' -ForegroundColor Red -NoNewline
        }else{
            Write-Host '# ' -ForegroundColor Blue -NoNewline
        }

        # Username may be null, in this case derive the username from the name of the user's home folder (for WSL mainly)
        if($null -eq $env:UserName){
            Write-Host ($($env:Homepath | Split-Path -leaf) + ' ') -ForegroundColor Cyan -NoNewLine
		}else{
            Write-Host ($env:UserName + ' ') -ForegroundColor Cyan -NoNewline
		}

        # ***Host***
        Write-Host ('@ ') -ForegroundColor DarkGray -NoNewline
        Write-Host ($env:COMPUTERNAME + ' ') -ForegroundColor Green -NoNewline
        
        # ***Directory***
        Write-Host ('in ') -ForegroundColor DarkGray -NoNewline
        # Replace references to the home folder with a '~' and remove the 'Microsoft.PowerShell.Core\FileSystem::' prefix
        Write-Host ($(Get-Location).ToString().replace(($env:HOMEDRIVE + $env:HOMEPATH), '~').replace("Microsoft.PowerShell.Core\FileSystem::", "") + ' ') -ForegroundColor Yellow -NoNewline
        
        # ***Git***
        # If the current directory is a git repository, display the current branch
        if($env:POSH_GIT_ENABLED -eq $true){ # Only run if posh-git is enabled
            if($status = Get-GitStatus -Force){ # Only run if the current directory is a git repository
                Write-Host ('on ') -ForegroundColor DarkGray -NoNewline # Prefix
                Write-Host ('git:') -ForegroundColor White -NoNewline # Git Icon
                Write-Host ($status.Branch) -ForegroundColor Cyan -NoNewline # Branch Name
                
                # Status Icon
                if($status.HasWorking){
                    Write-Host (' x ') -ForegroundColor Red -NoNewline # Red X if the working directory is dirty
                }else {
                    Write-Host (' o ') -ForegroundColor Green -NoNewline # Green O if the working directory is clean
                }
            }
        }

        # ***Timestamp***
        Write-Host ('[' + (Get-Date -Format "HH:mm:ss") + '] ') -ForegroundColor DarkGray -NoNewline

        # ***Exit Code***

        # Don't display the exit code if it is 0 (Success)
        if($currentExitCode -ne '0'){
            Write-Host ('C:' + ($currentExitCode)) -ForegroundColor Red
        }else{
            Write-Host '' # Write a blank line to ensure the prompt is on a new line
        }
        
        # ***Prompt***
        # Write out the Prompt character seperately so that it can be colourised
        Write-Host '$' -ForegroundColor Red -NoNewline

        # Reset the exit code if it was updated by any of the above script
        $global:LASTEXITCODE = $currentExitCode

        # Return a space to act as a proxy prompt character
        return ' '
    }

    # Tell PSReadLine what the prompt character is
    Set-PSReadLineOption -PromptText '$ '
}

<# PSReadLine #>

# Function to run every time the vi mode is changed
function OnViModeChange {
    if ($args[0] -eq 'Command') {
        # Set the cursor to a blinking block.
        Write-Host -NoNewLine "`e[1 q"
    } else {
        # Set the cursor to a blinking line.
        Write-Host -NoNewLine "`e[5 q"
    }
}

# PSReadLine Options
$PSReadLineOptions = @{
    # Don't alert errors visually/audibly
    BellStyle = "None"

    # Set colours
    Colors = @{
        # Colour the continuation prompt red to match ys's red prompt
        ContinuationPrompt = "Red"
    }

    # Define string used as the continuation prompt
    ContinuationPrompt = "> "

    # Use vi-like command line editting
    EditMode = "Vi"

    # Don't display duplicates in the history search
    HistoryNoDuplicates = $true

    # Move cursor to the end of the line when searching command history
    HistorySearchCursorMovesToEnd = $true

    # Display history search results and plugin suggestions together
    PredictionSource = "HistoryAndPlugin"
    
    # Render the predictions in a drop down list - use inline view in VSCode
    PredictionViewStyle = if ($env:TERM_PROGRAM -eq 'vscode') { "InlineView" } else { "ListView" }

    # Run a function whenever the vi mode is changed
    ViModeIndicator = "Script" 
    
    # Define which function will be called when the vi mode is changed
    ViModeChangeHandler = $Function:OnViModeChange
}

# Assign the above values
Set-PSReadLineOption @PSReadLineOptions

# Import the script that defines the key bindings
. "$PSScriptRoot\Bindings\PSReadLine.ps1"

<# Functions #>

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

# Function for the ls alias so that it functions more Unix-like
function Get-ChildItemUnixStyle {
    # If any argument are passed to the alias bypass the filtering so that Get-ChildItem functions as normal
    if($args.Count -gt 0){
        & Get-ChildItem @args
    }else{
        # Exclude files hidden in a unix shell session, Also hide the dummy files created by Carbon Black
        Get-ChildItem . -Exclude '.*', '#*', '$*'
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

# Allow the user to select a winget package and update it
function Invoke-FuzzyWingetUpdate{
    # Get all updates available from WinGet and format them for fzf
    $updates = Get-WinGetPackage | Where-Object {($_.Version -ne "Unknown") -and $_.IsUpdateAvailable} | # Get all packages that have an update available and don't have an unknown version
    Select-Object -Property Source, Name, Id, Version, AvailableVersions | # Select only the properties we need
    ForEach-Object { # Format the output so that it can be used by fzf
        $source = "$($PSStyle.Foreground.Magenta)$($_.Source)"
        $name = "$($PSStyle.Foreground.White)$($_.Name)"
        $id = "$($PSStyle.Foreground.Yellow)$($_.Id)$($PSStyle.Foreground.BrightWhite)" # Ensure the closing bracket is white
        $version = "$($PSStyle.Foreground.Red)$($_.Version)"
        $latest_version = "$($PSStyle.Foreground.Green)$($_.AvailableVersions[0])" # Get the latest version from the array - this is the first element

        # Output the formatted string - these strings are the ones that will be displayed in fzf
        "$source `t $name ($id) `t $version $($PSStyle.Foreground.Cyan)-> $latest_version"
    }

    # If there are no updates available then exit
    if($updates.Count -eq 0){
        Write-Host "No updates found" -ForegroundColor Yellow
        return
    }

    # Define the preview command for fzf to use - Better to define it here for readability
    $fzfPreviewArgs = (
        'echo {} | ' + # Pipe the selected line to the command
        'pwsh -noLogo -noProfile -Command "' + # Preview command is run by cmd.exe so we need to start a new session
        '$id = $input | Select-String -Pattern \"\((.*?)\)\" | ForEach-Object { $_.Matches.Groups[1].Value }; ' +  # Get the ID from the selected line
        '$info = $(winget show $id) -replace \"^\s*Found\s*\", \"\"; ' + # Call the winget show command and remove the "Found" text from the output
        '$info = $info -replace \"(^.*) \[(.*)\]$\", \"$($PSStyle.Bold)`$1 ($($PSStyle.Foreground.Yellow)`$2$($PSStyle.Foreground.BrightWhite))$($PSStyle.BoldOff)\"; ' + # Colour the ID and make the whole header bold
        '$info -replace \"(^\S[a-zA-Z0-9 ]+:(?!/))\", \"$($PSStyle.Foreground.Cyan)`$1$($PSStyle.Foreground.White)\""' # Colour the keys, close the quotes and end the command
    ) # Will print $info in the preview window

    # Format the updates for fzf and pipe them to fzf
    $package = $updates | Format-Table -HideTableHeaders | Out-String | ForEach-Object { $_.Trim("`r", "`n") } |
        fzf --ansi --reverse --preview "$fzfPreviewArgs" --preview-window '50%,border-left' --prompt=' WinGet >'

    # If the user didn't select anything return
    if(-not $package){
        return
    }

    # Get the ID from the selected line
    $id = $package | Select-String -Pattern "\((.*?)\)" | ForEach-Object { $_.Matches.Groups[1].Value } 

    # If the ID is empty return
    if(-not $id){
        Write-Host "No ID found." -ForegroundColor Red # This should never happen
        return
    }

    Write-Host "Updating $id..." # Print the ID to the console so the user knows what is happening

    # Update the selected package
    $result = Update-WinGetPackage "$id"

    # Report the result to the user
    if($result.status -eq "Ok"){
        Write-Host "Successfully updated $id" -ForegroundColor Green
    }else{
        Write-Host "Failed to update $id" -ForegroundColor Red

        # Output the full status if the update failed
        $result | Format-List | Out-String | Write-Host
    }
}

# Allow the user to select a winget package and install it
function Invoke-FuzzyWingetUninstall{
    # Get all packages from WinGet and format them for fzf
    $installedPackages = Get-WinGetPackage | # Get all packages that don't have an unknown version
    Select-Object -Property Source, Name, Id, Version | # Select only the properties we need
    ForEach-Object { # Format the output so that it can be used by fzf
        $source = "$($PSStyle.Foreground.Magenta)$($_.Source)"
        $name = "$($PSStyle.Foreground.White)$($_.Name)"
        $id = "$($PSStyle.Foreground.Yellow)$($_.Id)$($PSStyle.Foreground.BrightWhite)" # Ensure the closing bracket is white
        $version = "$($PSStyle.Foreground.Green)$($_.Version)"

        # Output the formatted string - these strings are the ones that will be displayed in fzf
        "$source `t $name ($id) `t $version"
    }

    # If there are no packages then exit - This should never happen
    if($installedPackages.Count -eq 0){
        Write-Host "No packages found" -ForegroundColor Yellow
        return
    }

    # Define the preview command for fzf to use - Better to define it here for readability
    $fzfPreviewArgs = (
        'echo {} | ' + # Pipe the selected line to the command
        'pwsh -noLogo -noProfile -Command "' + # Preview command is run by cmd.exe so we need to start a new session
        '$id = $input | Select-String -Pattern \"\((.*?)\)\" | ForEach-Object { $_.Matches.Groups[1].Value }; ' +  # Get the ID from the selected line
        '$info = $(winget show $id) -replace \"^\s*Found\s*\", \"\"; ' + # Call the winget show command and remove the "Found" text from the output
        '$info = $info -replace \"(^.*) \[(.*)\]$\", \"$($PSStyle.Bold)`$1 ($($PSStyle.Foreground.Yellow)`$2$($PSStyle.Foreground.BrightWhite))$($PSStyle.BoldOff)\"; ' + # Colour the ID and make the whole header bold
        '$info -replace \"(^\S[a-zA-Z0-9 ]+:(?!/))\", \"$($PSStyle.Foreground.Cyan)`$1$($PSStyle.Foreground.White)\""' # Colour the keys, close the quotes and end the command
    ) # Will print $info in the preview window

    # Format the updates for fzf and pipe them to fzf
    $package = $installedPackages | Out-String | ForEach-Object { $_.Trim("`r", "`n") } |
        fzf --ansi --reverse --preview "$fzfPreviewArgs" --preview-window '50%,border-left' --prompt=' WinGet >'

    # If the user didn't select anything return
    if(-not $package){
        return
    }

    # Get the ID from the selected line
    $id = $package | Select-String -Pattern "\((.*?)\)" | ForEach-Object { $_.Matches.Groups[1].Value }

    # If the ID is empty return
    if(-not $id){
        Write-Host "No ID found." -ForegroundColor Red # This should never happen
        return
    }

    Write-Host "Uninstalling $id..." # Print the ID to the console so the user knows what is happening

    # Uninstall the selected package
    $result = Uninstall-WinGetPackage "$id"

    # Report the result to the user
    if($result.status -eq "Ok"){
        Write-Host "Successfully uninstalled $id" -ForegroundColor Green
    }else{
        Write-Host "Failed to uninstall $id" -ForegroundColor Red

        # Output the full status if the update failed
        $result | Format-List | Out-String | Write-Host
    }
}

# List all updates available from WinGet
# Filter out any packages that don't have a version number similar to how "winget upgrade" works
function Get-WinGetUpdates {
    Get-WinGetPackage | Where-Object {($_.Version -ne "Unknown") -and $_.IsUpdateAvailable} | Select-Object -Property Name, Id, Version, @{Name="Latest Version";Expression={$_.AvailableVersions[0]}}
}

# Function to reset the Last exit code on a reset
function Clear-HostandExitCode {
    $LASTEXITCODE = 0
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

<# Aliases #>

# *** Built in ***

# Get-ChildItem
Set-Alias -Name ls -Value Get-ChildItemUnixStyle
Set-Alias -Name ll -Value Get-ChildItemUnixStyle

# Clear-Host
Set-Alias -Name clear -Value Clear-HostandExitCode
Set-Alias -Name cl -Value Clear-HostandExitCode # Shorter alias

# New-Item
Set-Alias -Name mk -Value New-Item # Similar to mkdir

# *** External Programs ***

# gsudo
Set-Alias -Name sudo -Value gsudo
Set-Alias -Name su -Value gsudo

# Python - 32 bit for test scripts
Set-Alias -Name py32 -Value $($env:LOCALAPPDATA + "\Programs\Python\Python37-32\python.exe")

# Winget
Set-Alias -Name wg -Value Winget # Shorter alias for cmd cli
Set-Alias -Name wgu -Value Get-WinGetUpdates # List all updates available from WinGet

# lazygit
Set-Alias -Name lg -Value lazygit

# *** Visual Studio ***

# Installed Visual Studio Versions
# 22
Set-Alias -Name vs22 -Value "C:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\IDE\devenv.exe"
# 19
Set-Alias -Name vs19 -Value "C:\Program Files (x86)\Microsoft Visual Studio\2019\Professional\Common7\IDE\devenv.exe"
# 17
Set-Alias -Name vs17 -Value "C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\Common7\IDE\devenv.exe"

# Cleaner alias for the latest version
Set-Alias -Name vs -Value vs22

# *** FZF ***

# Use bat as a previewer for fzf
Set-Alias -Name fzfp -Value Invoke-FzfBat

# Search and view TLDR pages in fzf/bat
Set-Alias -Name fzft -Value Invoke-FzfTldr

# Use Fzf to select the results of an everything search
Set-Alias -Name fzfe -Value Invoke-FzfES

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