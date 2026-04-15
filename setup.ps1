# ==============================================================================
#
#   ███████╗ ██████╗  ██████╗ ███████╗     ██████╗ ██╗      ██████╗ ██████╗  █████╗ ██╗
#   ╚══███╔╝██╔═══██╗██╔═══██╗██╔════╝    ██╔════╝ ██║     ██╔═══██╗██╔══██╗██╔══██╗██║
#     ███╔╝ ██║   ██║██║   ██║███████╗    ██║  ███╗██║     ██║   ██║██████╔╝███████║██║
#    ███╔╝  ██║   ██║██║   ██║╚════██║    ██║   ██║██║     ██║   ██║██╔══██╗██╔══██║██║
#   ███████╗╚██████╔╝╚██████╔╝███████║    ╚██████╔╝███████╗╚██████╔╝██████╔╝██║  ██║███████╗
#   ╚══════╝ ╚═════╝  ╚═════╝ ╚══════╝     ╚═════╝ ╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝
#
# ==============================================================================
#  Script    : Datadog DHCP Monitor - Setup Script
#  Version   : 1.2.0
#  Purpose   : Post-agent-installation setup
#              1. Validates Datadog Agent is installed and running
#              2. Validates DogStatsD is listening on :8125
#              3. Creates C:\Scripts directory
#              4. Copies dhcp-metrics.ps1 to C:\Scripts\
#              5. Unblocks both scripts (removes Zone.Identifier)
#              6. Runs dhcp-metrics.ps1 once for manual validation
#              7. Creates Windows Task Scheduler task (every 1 min, SYSTEM)
#              8. Prints final status summary
# ------------------------------------------------------------------------------
#  Author    : Shivam Anand
#  Title     : Sr. DevOps Engineer | Engineering
#  Org       : Zoos Global
#  Email     : shivam.anand@zoosglobal.com
#  Web       : www.zoosglobal.com
#  Address   : Violena, Pali Hill, Bandra West, Mumbai - 400050
# ------------------------------------------------------------------------------
#  Usage     : Run as Administrator from the folder containing dhcp-metrics.ps1
#              PowerShell.exe -ExecutionPolicy Bypass -File .\setup.ps1
#
#  Platform  : Windows Server 2019 / 2022 / 2025
#  Requires  : Datadog Agent already installed
#              PowerShell 5.1+
#              Administrator privileges
# ==============================================================================

#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

# Config
$ScriptsDir   = 'C:\Scripts'
$SourceScript = 'dhcp-metrics.ps1'
$TargetScript = 'C:\Scripts\dhcp-metrics.ps1'
$TaskName     = 'DHCP-Datadog-Metrics'
$TaskDesc     = 'Collects DHCP metrics every minute and submits to Datadog via DogStatsD. | Zoos Global'
$DDAgent      = 'datadogagent'
$DDStatsdPort = 8125

$SEP  = '=' * 70
$SEP2 = '-' * 60

function Write-Banner {
    Write-Host ''
    Write-Host $SEP -ForegroundColor Cyan
    Write-Host '  Datadog DHCP Monitor - Setup                       Zoos Global' -ForegroundColor Cyan
    Write-Host $SEP -ForegroundColor Cyan
    Write-Host '  Author : Shivam Anand | Sr. DevOps Engineer'
    Write-Host '  Web    : www.zoosglobal.com'
    Write-Host '  Email  : shivam.anand@zoosglobal.com'
    Write-Host $SEP
    Write-Host ''
}

function Write-Step($step, $msg) {
    Write-Host ''
    Write-Host "  [$step] $msg" -ForegroundColor Yellow
    Write-Host "  $SEP2" -ForegroundColor DarkGray
}

function Write-OK($msg)   { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-FAIL($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red   }
function Write-INFO($msg) { Write-Host "  [INFO] $msg" -ForegroundColor Cyan  }

# ==============================================================================
# BANNER
# ==============================================================================
Write-Banner

# ==============================================================================
# STEP 1 - Check Datadog Agent service
# ==============================================================================
Write-Step '1/7' 'Checking Datadog Agent service...'

try {
    $svc = Get-Service -Name $DDAgent -ErrorAction Stop
    if ($svc.Status -eq 'Running') {
        Write-OK "Datadog Agent is running (Status: $($svc.Status))"
    } else {
        Write-FAIL "Datadog Agent is NOT running (Status: $($svc.Status))"
        Write-INFO 'Attempting to start Datadog Agent...'
        Start-Service -Name $DDAgent
        Start-Sleep -Seconds 5
        $svc = Get-Service -Name $DDAgent
        if ($svc.Status -eq 'Running') {
            Write-OK 'Datadog Agent started successfully'
        } else {
            throw 'Datadog Agent could not be started. Please install the agent first.'
        }
    }
} catch {
    Write-FAIL "Datadog Agent service not found: $_"
    Write-INFO 'Install agent from: https://s3.amazonaws.com/ddagent-windows-stable/datadog-agent-7-latest.amd64.msi'
    exit 1
}

# ==============================================================================
# STEP 2 - Verify DogStatsD is listening on UDP :8125
# ==============================================================================
Write-Step '2/7' "Verifying DogStatsD is listening on UDP :$DDStatsdPort..."

try {
    $listening = netstat -an | Select-String "UDP.*0\.0\.0\.0:$DDStatsdPort|UDP.*127\.0\.0\.1:$DDStatsdPort"
    if ($listening) {
        Write-OK "DogStatsD is listening on :$DDStatsdPort"
        Write-INFO "$($listening[0].ToString().Trim())"
    } else {
        Write-FAIL "DogStatsD not found on port $DDStatsdPort"
        Write-INFO 'Check datadog.yaml: dogstatsd_port: 8125'
        exit 1
    }
} catch {
    Write-FAIL "Could not verify DogStatsD port: $_"
    exit 1
}

# ==============================================================================
# STEP 3 - Create C:\Scripts directory
# ==============================================================================
Write-Step '3/7' "Creating target directory: $ScriptsDir..."

try {
    if (Test-Path $ScriptsDir) {
        Write-OK "Directory already exists: $ScriptsDir"
    } else {
        New-Item -ItemType Directory -Path $ScriptsDir -Force | Out-Null
        Write-OK "Created directory: $ScriptsDir"
    }
} catch {
    Write-FAIL "Failed to create directory ${ScriptsDir}: $_"
    exit 1
}

# ==============================================================================
# STEP 4 - Copy dhcp-metrics.ps1 to C:\Scripts\
# ==============================================================================
Write-Step '4/7' "Copying $SourceScript to $TargetScript..."

try {
    $sourcePath = Join-Path (Get-Location).Path $SourceScript

    if (-not (Test-Path $sourcePath)) {
        Write-FAIL "$SourceScript not found in current directory: $(Get-Location)"
        Write-INFO 'Run setup.ps1 from the same folder as dhcp-metrics.ps1'
        exit 1
    }

    Copy-Item -Path $sourcePath -Destination $TargetScript -Force
    Write-OK "Copied successfully: $TargetScript"

    $copied = Get-Item $TargetScript
    Write-INFO "File size    : $([math]::Round($copied.Length / 1KB, 2)) KB"
    Write-INFO "Last written : $($copied.LastWriteTime)"

} catch {
    Write-FAIL "Failed to copy script: $_"
    exit 1
}

# ==============================================================================
# STEP 5 - Unblock scripts (remove Zone.Identifier from downloaded files)
# Files downloaded from internet/GitHub get a hidden Zone.Identifier NTFS
# stream that Windows treats as untrusted. Unblock-File removes it so the
# script can run without a digital signature.
# ==============================================================================
Write-Step '5/7' 'Unblocking scripts (removing Zone.Identifier)...'

try {
    Unblock-File -Path $TargetScript -ErrorAction SilentlyContinue
    Write-OK "Unblocked: $TargetScript"

    $setupPath = $MyInvocation.MyCommand.Path
    if ($setupPath -and (Test-Path $setupPath)) {
        Unblock-File -Path $setupPath -ErrorAction SilentlyContinue
        Write-OK "Unblocked: $setupPath"
    }

    $sourcePath = Join-Path (Get-Location).Path $SourceScript
    if (Test-Path $sourcePath) {
        Unblock-File -Path $sourcePath -ErrorAction SilentlyContinue
        Write-OK "Unblocked: $sourcePath"
    }

} catch {
    Write-FAIL "Unblock-File failed: $_"
    Write-INFO "Try manually: Unblock-File -Path '$TargetScript'"
    exit 1
}

# ==============================================================================
# STEP 6 - Run dhcp-metrics.ps1 once for manual validation
# ==============================================================================
Write-Step '6/7' 'Running dhcp-metrics.ps1 once for validation...'
Write-INFO "You should see 'Sent: dhcp.*' lines below."
Write-Host ''

try {
    & PowerShell.exe -NonInteractive -ExecutionPolicy Bypass -File $TargetScript
    Write-Host ''
    Write-OK 'Validation run completed'
    Write-INFO 'Verify in Datadog -> Metrics -> Explorer -> search: dhcp.scope.percent_in_use'
} catch {
    Write-FAIL "Validation run failed: $_"
    Write-INFO 'Review the error above. Setup will continue to create the scheduled task...'
}

# ==============================================================================
# STEP 7 - Create / Update Windows Task Scheduler task
# ==============================================================================
Write-Step '7/7' "Creating Task Scheduler task: '$TaskName'..."

try {
    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-INFO "Removed existing task: $TaskName"
    }

    $action = New-ScheduledTaskAction `
        -Execute  'PowerShell.exe' `
        -Argument "-NonInteractive -ExecutionPolicy Bypass -File `"$TargetScript`""

    $trigger = New-ScheduledTaskTrigger `
        -Once `
        -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Minutes 1) `
        -RepetitionDuration (New-TimeSpan -Days 3650)
    $settings = New-ScheduledTaskSettingsSet `
        -ExecutionTimeLimit         (New-TimeSpan -Minutes 5) `
        -MultipleInstances          IgnoreNew `
        -RestartCount               3 `
        -RestartInterval            (New-TimeSpan -Minutes 1) `
        -StartWhenAvailable `
        -RunOnlyIfNetworkAvailable:$false

    $principal = New-ScheduledTaskPrincipal `
        -UserId    'NT AUTHORITY\SYSTEM' `
        -RunLevel  Highest `
        -LogonType ServiceAccount

    Register-ScheduledTask `
        -TaskName    $TaskName `
        -Action      $action `
        -Trigger     $trigger `
        -Settings    $settings `
        -Principal   $principal `
        -Description $TaskDesc `
        -Force | Out-Null

    $task = Get-ScheduledTask -TaskName $TaskName
    Write-OK "Task created  : $TaskName"
    Write-INFO 'Run as        : NT AUTHORITY\SYSTEM'
    Write-INFO 'Interval      : Every 3 minute'
    Write-INFO "State         : $($task.State)"

    Start-ScheduledTask -TaskName $TaskName
    Write-OK 'Task started - first run triggered now'

} catch {
    Write-FAIL "Failed to create task: $_"
    exit 1
}

# ==============================================================================
# FINAL STATUS SUMMARY
# ==============================================================================
Write-Host ''
Write-Host $SEP -ForegroundColor Green
Write-Host '  SETUP COMPLETE' -ForegroundColor Green
Write-Host $SEP -ForegroundColor Green
Write-Host ''
Write-Host "  Script location : $TargetScript"
Write-Host "  Task name       : $TaskName"
Write-Host '  Schedule        : Every 1 minute'
Write-Host '  Run as          : NT AUTHORITY\SYSTEM'
Write-Host ''
Write-Host '  Next steps:'
Write-Host '  1. Open Datadog -> Metrics -> Explorer'
Write-Host '  2. Search: dhcp.scope.percent_in_use'
Write-Host '  3. Metrics should appear within ~30 seconds'
Write-Host ''
Write-Host '  Verify task is running:'
Write-Host "  > schtasks /query /tn $TaskName /fo LIST /v"
Write-Host ''
Write-Host '  Remove this setup:'
Write-Host "  > Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false"
Write-Host "  > Remove-Item '$TargetScript'"
Write-Host ''
Write-Host $SEP -ForegroundColor Cyan
Write-Host '  Powered by Zoos Global | www.zoosglobal.com' -ForegroundColor Cyan
Write-Host '  (c) 2026 Zoos Global | shivam.anand@zoosglobal.com' -ForegroundColor Cyan
Write-Host $SEP -ForegroundColor Cyan
Write-Host ''
# ==============================================================================
