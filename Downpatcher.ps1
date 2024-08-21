# Define the path for SteamCMD based on the script directory
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Definition
$steamcmdPath = Join-Path $scriptDirectory "steamcmd\steamcmd.exe"
$steamCmdDownloadUrl = "https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip"
$tempZipPath = Join-Path $env:TEMP "steamcmd.zip"

$global:username = ""
$global:password = ConvertTo-SecureString " " -AsPlainText -Force
$global:guard = ""

$global:userid = ""

$global:depotSize = 54985540625
$global:requiredSize = 56000000000

function Get-SteamDirectory {
    # Check common paths
    $possiblePaths = @(
        "C:\Program Files (x86)\Steam",
        "C:\Program Files\Steam"
    )

    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            return $path
        }
    }

    # Check registry
    $steamRegKey = "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam"
    if (Test-Path $steamRegKey) {
        return (Get-ItemProperty -Path $steamRegKey).InstallPath
    }

    # Check running process
    $steamProcess = Get-Process -Name "steam" -ErrorAction SilentlyContinue
    if ($steamProcess) {
        return Split-Path -Path $steamProcess.Path
    }

    return $null
}

function Test-MHW {
    $mhwPath = Join-Path $scriptDirectory "MonsterHunterWorld.exe"
    return Test-Path $mhwPath
}

function Test-Stracker {
    $strackerPath = Join-Path $scriptDirectory "loader.dll"
    return Test-Path $strackerPath
}

function Test-ICE {
    $ICEPath = Join-Path $scriptDirectory "ice_managed_code.dll"
    return Test-Path $ICEPath
}

function Test-EnoughDiskSpace {
    $currentDriveLetter = (Get-Location).Drive.Name
    $drive = "$($currentDriveLetter):"

    $disk = Get-WmiObject -Class Win32_LogicalDisk -Filter "DeviceID='$drive'"

    return ($global:requiredSize -lt $disk.FreeSpace)
}

function Test-SteamCMDInstalled {
    return Test-Path $steamcmdPath
}

function Install-SteamCMD {
    $installDir = Join-Path $scriptDirectory "steamcmd"
    New-Item -Path $installDir -ItemType Directory -Force | Out-Null

    Invoke-WebRequest -Uri $steamCmdDownloadUrl -OutFile $tempZipPath

    Expand-Archive -Path $tempZipPath -DestinationPath $installDir -Force

    Remove-Item $tempZipPath | Out-Null
}

function Set-Credentials {
    $global:username = Read-Host "Enter your Steam username"
    $global:password = Read-Host "Enter your Steam password" -AsSecureString
    $global:guard    = Read-Host "Enter your Steam Guard code (leave blank if not enabled)"
}

function Show-DownloadBar {
    $folderPath = Join-Path $scriptDirectory "steamcmd\steamapps\content"
    $Delay = 1000
    $BarLength = 30

    if (-not (Test-Path $FolderPath)) {
        Start-Sleep -Milliseconds $Delay
        Show-DownloadBar
        return
    }

    Write-Output "The Progress halts for a while at about 78% and slows down immensely. This is expected behavior."

    do {
        $folderSizeBytes = (Get-ChildItem -Path $FolderPath -Recurse -File | Measure-Object -Property Length -Sum).Sum

        $percentComplete = [math]::Round(($folderSizeBytes / $global:depotSize) * 100)
        $progress = [math]::Round(($percentComplete / 100) * $BarLength)

        $loadingBar = ("#" * $progress).PadRight($BarLength)

        $progressMessage = "[$loadingBar] $percentComplete% ($([math]::Round($folderSizeBytes / 1GB, 2)) GB / $([math]::Round($global:depotSize / 1GB, 2)) GB)"
        Write-Host "`r$progressMessage" -NoNewline

        Start-Sleep -Milliseconds $Delay

        $folderSizeBytes = (Get-ChildItem -Path $FolderPath -Recurse -File | Measure-Object -Property Length -Sum).Sum

    } while ($folderSizeBytes -lt $global:depotSize)

    Write-Host "`nPatch Download Complete."
}

function Backup-Saves {

    Write-Output "Searching for Steam..."
    $steamPath = Get-SteamDirectory
    if (-not ($steamPath)) {
        Write-Output "Steam not found."
        Write-Output "Please perform manual save backup if saves exist."
        return
    }
    Write-Output "Steam found."

    $baseBackupDir = "$HOME\Documents\MHWSaveBackup"

    if (-not (Test-Path -Path $baseBackupDir)) {
        New-Item -Path $baseBackupDir -ItemType Directory | Out-Null
    }

    $dateTime = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $backupDir = Join-Path -Path $baseBackupDir -ChildPath $dateTime

    New-Item -Path $backupDir -ItemType Directory | Out-Null

    Write-Output "Searching for MHW Save Data..."

    $userPath = Join-Path $steamPath "userdata\"

    $userids = Get-ChildItem -Path $userPath -Directory | ForEach-Object { $_.Name }

    foreach ($id in $userids) {
        $idPath = Join-Path $userPath "$id\582010"

        if(Test-Path $idPath) {
            $idBackupPath = Join-Path $backupDir "$id\"

            if (-not (Test-Path -Path $idBackupPath)) {
                New-Item -Path $idBackupPath -ItemType Directory | Out-Null
            }

            Copy-Item -Path $idPath\* -Destination $idBackupPath -Recurse -Force  | Out-Null
            Write-Output $backupDir
        }
    }

    Write-Output "Data backed up to: $backupDir"
    Write-Output "This backup process may not backup all user's mhw data."
    Write-Output "It is recommended to continue with a manual backup."
}

function Invoke-DownPatch {
    $chunkG11Path = Join-Path $scriptDirectory "chunk\chunkG11.bin"
    Remove-Item -Path $chunkG11Path -Force -ErrorAction SilentlyContinue

    $chunkG11ICEPath = Join-Path $scriptDirectory "ICE\chunk\chunkG11.bin"
    Remove-Item -Path $chunkG11ICEPath -Force -ErrorAction SilentlyContinue

    $chunkICEPath = Join-Path $scriptDirectory "ICE\chunk\"
    $excludeFiles = @("cHiPCG0.bin", "cHiPCG63.bin")

    Get-ChildItem -Path $chunkICEPath -Filter "cHiPC*.bin" | Where-Object {
        $excludeFiles -notcontains $_.Name
    } | ForEach-Object {
        Remove-Item -Path $_.FullName -Force | Out-Null
        Write-Output "Deleted file: $($_.FullName)"
    }

    $sourcePath = Join-Path $scriptDirectory "steamcmd\steamapps\content\app_582010\depot_582011\"

    $sourceMHWEXEPath = Join-Path $sourcePath "MonsterHunterWorld.exe"
    $sourceSteamAPIPatch = Join-Path $sourcePath "steam_api64.dll"
    $sourceChunkPath = Join-Path $sourcePath "chunk\chunkG60.bin"

    $destinationMHWEXEPath = Join-Path $scriptDirectory "MonsterHunterWorld.exe"
    $destinationSteamAPIPatch = Join-Path $scriptDirectory "steam_api64.dll"
    $destinationChunkPath = Join-Path $scriptDirectory "chunk\chunkG60.bin"

    Copy-Item -Path $sourceMHWEXEPath -Destination $destinationMHWEXEPath -Force
    Copy-Item -Path $sourceSteamAPIPatch -Destination $destinationSteamAPIPatch -Force
    Copy-Item -Path $sourceChunkPath -Destination $destinationChunkPath -Force
}

if(-not (Test-MHW)) {
    Write-Output "MonsterHunterWorld.exe not found in current directory."
    Write-Output "Press any key to continue..."
    [System.Console]::ReadKey($true) | Out-Null
    exit
}

if(-not (Test-Stracker)) {
    Write-Output "Stracker not installed."
    Write-Output "https://www.nexusmods.com/monsterhunterworld/mods/1982"
    Write-Output "Press any key to continue..."
    [System.Console]::ReadKey($true) | Out-Null
    exit
}

if(-not (Test-ICE)) {
    Write-Output "ICE not installed"
    Write-Output "https://github.com/AsteriskAmpersand/Ice-Stable"
    Write-Output "Press any key to continue..."
    [System.Console]::ReadKey($true) | Out-Null
    exit
}

if(-not (Test-EnoughDiskSpace)) {
    Write-Output "Not Enough Free Space."
    Write-Output "Press any key to continue..."
    [System.Console]::ReadKey($true) | Out-Null
    exit
}

if (-not (Test-SteamCMDInstalled)) {
    Write-Output "SteamCMD not found. Installing SteamCMD..."
    Install-SteamCMD
}

Write-Output "SteamCMD installed."

Set-Credentials

$passwordPlainText = [System.Net.NetworkCredential]::new("", $global:password).Password

Start-Process -FilePath $steamcmdPath "+login $global:username $passwordPlainText $global:guard +download_depot 582010 582011 3388885539667572621 +quit"

Write-Output "Waiting on patch download to begin..."
Show-DownloadBar

Backup-Saves

Invoke-DownPatch

do {
    Write-Output "Waiting for SteamCMD to close..."
    Start-Sleep 1
} while (Get-Process -Name "steamcmd" -ErrorAction SilentlyContinue)

Write-Output "Deleting SteamCMD and Depot"
$tempPath = Join-Path $scriptDirectory "steamcmd"
Remove-Item -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
Write-Output "Cleaned up."

Write-Output "ICE should be ready to play!"

Write-Output "Press any key to continue..."
[System.Console]::ReadKey($true) | Out-Null