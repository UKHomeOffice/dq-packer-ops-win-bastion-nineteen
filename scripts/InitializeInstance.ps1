# Copyright 2016 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Amazon Software License (the "License").
# You may not use this file except in compliance with the License.
# A copy of the License is located at
#
# http://aws.amazon.com/asl/
#
# or in the "license" file accompanying this file. This file is distributed
# on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
# express or implied. See the License for the specific language governing
# permissions and limitations under the License.

<#
.SYNOPSIS

    Initializes EC2 instance by configuring all required settings.

.DESCRIPTION

    During EC2 instance launch, it configures all required settings and displays information to console.

    0. Wait for sysprep: to ensure that sysprep process is finished.
    1. Add routes: to connect to instance metadata service and KMS service.
    2. Wait for metadata: to ensure that metadata is available to retrieve.
    3. Rename computer: to rename computer based on instance ip address.
    4. Display instance info: to inform user about your instance/AMI.
    5. Extend boot volume: to extend boot volume with unallocated spaces.
    6. Set password: to set password, so you can get password from console
    7. Windows is Ready: to display "Message: Windows is Ready to use" to console.
    8. Execute userdata: to execute userdata retrieved from metadata
    9. Register disabled scheduledTask: to keep the script as scheduledTask for future use.

    * By default, it always checks serial port setup.
    * If any task requires reboot, it re-regsiters the script as scheduledTask.
    * Userdata is executed after windows is ready because it is not required by default and can be a long running process.

.PARAMETER Schedule

    Provide this parameter to register script as scheduledtask and trigger it at startup. If you want to run script immediately, run it without this parameter.

.EXAMPLE

    ./InitializeInstance.ps1 -Schedule

#>

# Required for powershell to determine what parameter set to use when running with zero args (us a non existent set name)
[CmdletBinding(DefaultParameterSetName = 'Default')]
param (
    # Schedules the script to run on the next boot.
    # If this argument is not provided, script is executed immediately.
    [parameter(Mandatory = $false, ParameterSetName = "Schedule")]
    [switch] $Schedule = $false,
    # Schedules the script to run at every boot.
    # If this argument is not provided, script is executed immediately.
    [parameter(Mandatory = $false, ParameterSetName = "SchedulePerBoot")]
    [switch] $SchedulePerBoot = $false,
    # After the script executes, keeps the schedule instead of disabling it.
    [parameter(Mandatory = $false, ParameterSetName = "KeepSchedule")]
    [switch] $KeepSchedule = $false
)

Set-Variable rootPath -Option Constant -Scope Local -Value (Join-Path $env:ProgramData -ChildPath "Amazon\EC2-Windows\Launch")
Set-Variable modulePath -Option Constant -Scope Local -Value (Join-Path $rootPath -ChildPath "Module\Ec2Launch.psd1")
Set-Variable scriptPath -Option Constant -Scope Local -Value (Join-Path $PSScriptRoot -ChildPath $MyInvocation.MyCommand.Name)
Set-Variable scheduleName -Option Constant -Scope Local -Value "Instance Initialization"

Set-Variable amazonSSMagent -Option Constant -Scope Local -Value "AmazonSSMAgent"
Set-Variable ssmAgentTimeoutSeconds -Option Constant -Scope Local -Value 25
Set-Variable ssmAgentSleepSeconds -Option Constant -Scope Local -Value 5

# Import Ec2Launch module to prepare to use helper functions.
Import-Module $modulePath

# Before calling any function, initialize the log with filename and also allow LogToConsole.
Initialize-Log -Filename "Ec2Launch.log" -AllowLogToConsole

if ($Schedule -or $SchedulePerBoot) {
    $arguments = $null
    if ($SchedulePerBoot) {
        # If a user wants to run on every reboot, the next invocation of InitializeInstance should not disable it's schedule
        $arguments = "-KeepSchedule"

        # Disable and user data schedule so that user data doesn't run twice on the next run (once in launch, another time in the external schedule)
        Invoke-Userdata -OnlyUnregister
    }

    # Scheduling script with no argument tells script to start normally.
    Register-ScriptScheduler -ScriptPath $scriptPath -ScheduleName $scheduleName -Arguments $arguments

    # Set AmazonSSMAgent StartupType to be Disabled to prevent AmazonSSMAgent from running util windows is ready.
    Set-Service $amazonSSMagent -StartupType Disabled -ErrorAction SilentlyContinue
    Write-Log "Instance initialization is scheduled successfully"
    Complete-Log
    Exit 0
}

try {
    Write-Log "Initializing instance is started"

    # Serial Port must be available in your instance to send logs to console.
    # If serial port is not available, it sets the serial port and requests reboot.
    # If serial port is already available, it continues without reboot.
    if ((Test-NanoServer) -and (Set-SerialPort)) {
        # Now Computer can restart.
        Write-Log "Message: Windows is restarting..."
        Register-ScriptScheduler -ScriptPath $scriptPath -ScheduleName $scheduleName
        Restart-Computer
        Exit 0
    }

    # Serial port COM1 must be opened before executing any task.
    Open-SerialPort

    # Task must be executed after sysprep is complete.
    # WMI object seems to be missing during sysprep.
    Wait-Sysprep

    # Routes need to be added to connect to instance metadata service and KMS service.
    Add-Routes

    # Once routes are added, we need to wait for metadata to be available
    # becuase there are several tasks that need information from metadata.
    Wait-Metadata

    # Set KMS server and port in registry key.
    Set-ActivationSettings

    # Create wallpaper setup cmd file in windows startup directory, which
    # renders instance information on wallpaper as user logs in.
    New-WallpaperSetup

    # Installs EGPU for customers that request it
    Install-EgpuManager

    # Before renaming computer, it checks if computer is already renamed.
    # If computer is not renamed yet, it renames computer and requests reboot.
    # If computer is already renamed or failed to be renamed, it continues without reboot.
    if (Set-ComputerName) {
        # Now Computer can restart.
        Write-Log "Message: Windows is restarting..." -LogToConsole
        Register-ScriptScheduler -ScriptPath $scriptPath -ScheduleName $scheduleName
        Close-SerialPort
        Restart-Computer
        Exit 0
    }

    # All of the instance information is displayed to console.
    Send-AMIInfo
    Send-OSInfo
    Send-IDInfo
    Send-InstanceInfo
    Send-MsSqlInfo
    Send-DriverInfo
    Send-Ec2LaunchVersion
    Send-VSSVersion
    Send-SSMAgentVersion
    Send-RDPCertInfo
    Send-FeatureStatus

    # Add DNS suffixes in search list and store that in registry key.
    Add-DnsSuffixList

    # The volume size is extended with unallocated spaces.
    Set-BootVolumeSize

    # Disable Configure ENA Network settings. This setting has never been enabled on the agent.
    # Configure ENA Network settings
    # if (Set-ENAConfig) {
    #     # Now Computer can restart.
    #     Write-Log "Message: Windows is restarting..." -LogToConsole
    #     Register-ScriptScheduler -ScriptPath $scriptPath -ScheduleName $scheduleName
    #     Close-SerialPort
    #     Restart-Computer
    #     Exit 0
    # }

    # If requested, sets the monitor to never turn off which will interfere with acpi signals
    Set-MonitorAlwaysOn
    # If requested, tells windows to go in to hibernate instead of sleep
    # when the system sends the acpi sleep signal.
    Set-HibernateOnSleep

    # Password is randomly generated and provided to console in encrypted format.
    # Here, also admin account gets enabled.
    $creds = Set-AdminAccount

    # Encrypt the admin credentials and send it to console.
    # Console understands the admin password and allows users to decrypt it with private key.
    if ($creds.Username -and $creds.Password) {
        Send-AdminCredentials -Username $creds.Username -Password $creds.Password
    }

    try {
        # Set AmazonSSMAgent StartupType to be back to Automatic
        Set-Service $amazonSSMagent -StartupType Automatic -ErrorAction Stop
    }
    catch {
        Write-Log ("Failed to set AmazonSSMAgent service to Automatic {0}" -f $_.Exception.Message)
    }

    # Windows-is-ready message is displayed to console after all steps above are complete.
    Send-WindowsIsReady

    # Disable the scheduledTask if we were only suppose to run once, otherwise, leave the schedule.
    if (!$KeepSchedule) {
        Register-ScriptScheduler -ScriptPath $scriptPath -ScheduleName $scheduleName -Disabled
    }

    # Serial port COM1 must be closed before ending.
    Close-SerialPort

    # If this run is from a "run on every boot" schedule, make sure we only execute user data (dont
    # schedule it as a separate task), this is so we can instead execute it inline on every boot.

    # Userdata can be executed now if user provided one before launching instance. Because
    # userdata is not required by default and can be a long running process, it is not a
    # part of windows-is-ready condition and executed after Send-WindowsIsReady.
    $persistUserData = Invoke-Userdata -Username $creds.Username -Password $creds.Password -OnlyExecute:$KeepSchedule

    try {
        # Start AmazonSSMAgent service.
        # Have to use closure argument list because the closure will be running in a sub-job that wont have access to local variables
        Invoke-WithTimeout -ScriptName $amazonSSMagent -ScriptBlock { Start-Service -Name $args[0] -ErrorAction Stop } -ArgumentList $amazonSSMagent -SleepSeconds $ssmAgentSleepSeconds -TimeoutSeconds $ssmAgentTimeoutSeconds
    }
    catch {
        Write-Log ("Failed to start AmazonSSMAgent service: {0}" -f $_.Exception.Message)
    }

    # If this run is from a "run on every boot" schedule, disable certain functionality for future runs.
    if ($KeepSchedule) {
        Get-LaunchConfig -Key AdminPasswordType -Delete
        Get-LaunchConfig -Key SetMonitorAlwaysOn -Delete

        # Only disable handle user data if persist was false
        if (!$persistUserData) {
            Get-LaunchConfig -Key HandleUserData -Delete
        }
    }

    Write-Log "Initializing instance is done"
    Exit 0
}
catch {
    Write-Log ("Failed to continue initializing the instance: {0}" -f $_.Exception.Message)

    # Serial port COM1 must be closed before ending.
    Close-SerialPort
    Exit 1
}
finally {
    # Before finishing the script, complete the log.
    Complete-Log

    # Clear the credentials from memory.
    if ($creds) {
        $creds.Clear()
    }
}

# SIG # Begin signature block
# MIIc9AYJKoZIhvcNAQcCoIIc5TCCHOECAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDRBQX62zsLH+hD
# ZDpLMnBifJxOsx8DRajcEu4Evgwuo6CCDJ8wggXbMIIEw6ADAgECAhALhtAE1iqy
# 3BEl7IX117EeMA0GCSqGSIb3DQEBCwUAMGwxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xKzApBgNV
# BAMTIkRpZ2lDZXJ0IEVWIENvZGUgU2lnbmluZyBDQSAoU0hBMikwHhcNMjEwNDEz
# MDAwMDAwWhcNMjIwNDE4MjM1OTU5WjCB8jEdMBsGA1UEDwwUUHJpdmF0ZSBPcmdh
# bml6YXRpb24xEzARBgsrBgEEAYI3PAIBAxMCVVMxGTAXBgsrBgEEAYI3PAIBAhMI
# RGVsYXdhcmUxEDAOBgNVBAUTBzQxNTI5NTQxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdTZWF0dGxlMSIwIAYDVQQKExlBbWF6b24g
# V2ViIFNlcnZpY2VzLCBJbmMuMRMwEQYDVQQLEwpBbWF6b24gRUMyMSIwIAYDVQQD
# ExlBbWF6b24gV2ViIFNlcnZpY2VzLCBJbmMuMIIBIjANBgkqhkiG9w0BAQEFAAOC
# AQ8AMIIBCgKCAQEAyc04nmrj0mFs+J19mqr0o6yal0uNsXc7Z4vQslqbHTBJ7Xzf
# Qli6jQSOk6OzD3MrFbpT5eWM+0YqbSHHZNVdmGEko4LR4WJLmPmsGqwO754/zeXT
# KIlas66c4cRw6igGPeDRDkNUMRFfvnmbM/HZZIwR0HeLtRDOZddDDdydvLo6rcGW
# nRLG15NeKWPemWs2jHvWBcNuSV2/8TlEuujgznt/U3p1x6xenzlGTedx6JBA0GPa
# l9YF2ijvPpVowaljpCLun4agFHTMnzq+tWGocvgF80N78E20wl16i3Ls7hbnwjcn
# crjpQiBgYWvWrU+xpeT/8fPs6id03o4Ggadh7QIDAQABo4IB8DCCAewwHwYDVR0j
# BBgwFoAUj+h+8G0yagAFI8dwl2o6kP9r6tQwHQYDVR0OBBYEFNOsLmIr6HnXlCro
# QE13eT9iOwKbMC4GA1UdEQQnMCWgIwYIKwYBBQUHCAOgFzAVDBNVUy1ERUxBV0FS
# RS00MTUyOTU0MA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcDAzB7
# BgNVHR8EdDByMDegNaAzhjFodHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRVZDb2Rl
# U2lnbmluZ1NIQTItZzEuY3JsMDegNaAzhjFodHRwOi8vY3JsNC5kaWdpY2VydC5j
# b20vRVZDb2RlU2lnbmluZ1NIQTItZzEuY3JsMEoGA1UdIARDMEEwNgYJYIZIAYb9
# bAMCMCkwJwYIKwYBBQUHAgEWG2h0dHA6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzAH
# BgVngQwBAzB+BggrBgEFBQcBAQRyMHAwJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3Nw
# LmRpZ2ljZXJ0LmNvbTBIBggrBgEFBQcwAoY8aHR0cDovL2NhY2VydHMuZGlnaWNl
# cnQuY29tL0RpZ2lDZXJ0RVZDb2RlU2lnbmluZ0NBLVNIQTIuY3J0MAwGA1UdEwEB
# /wQCMAAwDQYJKoZIhvcNAQELBQADggEBAJIKG4PvG2fKZaJxKzF+Buzkm/vCffHd
# doEOHwxP5dxg0ITPpqo1oZ3mEgNOG5sA+x5h8l1D/hrmOXwjKKpP7l3aPPjzD64j
# Dv4mVENm6wr4t5fG5GWFNBzmY3JBSJqGAIJ0aPKs0Sd4TqAW2BGc7nRqH67/mJvE
# X6Piw2M6/Wa6WhrpCxjyBhB4FcX5UsVWuXz7iIg6TsGkOQaNOCpr9nF3daepI11l
# uZE5KfVOi+IRGe362zNllomxdpoRbk+ApxBY/40hB7Qx7eBi7c7jkd6kr5KcuATv
# JfX4UWFLaXs+1dbqclGWeJa8CZQJxmshSY3rhQLCBthCFHGITP3NSb8wgga8MIIF
# pKADAgECAhAD8bThXzqC8RSWeLPX2EdcMA0GCSqGSIb3DQEBCwUAMGwxCzAJBgNV
# BAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdp
# Y2VydC5jb20xKzApBgNVBAMTIkRpZ2lDZXJ0IEhpZ2ggQXNzdXJhbmNlIEVWIFJv
# b3QgQ0EwHhcNMTIwNDE4MTIwMDAwWhcNMjcwNDE4MTIwMDAwWjBsMQswCQYDVQQG
# EwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNl
# cnQuY29tMSswKQYDVQQDEyJEaWdpQ2VydCBFViBDb2RlIFNpZ25pbmcgQ0EgKFNI
# QTIpMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAp1P6D7K1E/Fkz4SA
# /K6ANdG218ejLKwaLKzxhKw6NRI6kpG6V+TEyfMvqEg8t9Zu3JciulF5Ya9DLw23
# m7RJMa5EWD6koZanh08jfsNsZSSQVT6hyiN8xULpxHpiRZt93mN0y55jJfiEmpqt
# RU+ufR/IE8t1m8nh4Yr4CwyY9Mo+0EWqeh6lWJM2NL4rLisxWGa0MhCfnfBSoe/o
# PtN28kBa3PpqPRtLrXawjFzuNrqD6jCoTN7xCypYQYiuAImrA9EWgiAiduteVDgS
# YuHScCTb7R9w0mQJgC3itp3OH/K7IfNs29izGXuKUJ/v7DYKXJq3StMIoDl5/d2/
# PToJJQIDAQABo4IDWDCCA1QwEgYDVR0TAQH/BAgwBgEB/wIBADAOBgNVHQ8BAf8E
# BAMCAYYwEwYDVR0lBAwwCgYIKwYBBQUHAwMwfwYIKwYBBQUHAQEEczBxMCQGCCsG
# AQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wSQYIKwYBBQUHMAKGPWh0
# dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEhpZ2hBc3N1cmFuY2VF
# VlJvb3RDQS5jcnQwgY8GA1UdHwSBhzCBhDBAoD6gPIY6aHR0cDovL2NybDMuZGln
# aWNlcnQuY29tL0RpZ2lDZXJ0SGlnaEFzc3VyYW5jZUVWUm9vdENBLmNybDBAoD6g
# PIY6aHR0cDovL2NybDQuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0SGlnaEFzc3VyYW5j
# ZUVWUm9vdENBLmNybDCCAcQGA1UdIASCAbswggG3MIIBswYJYIZIAYb9bAMCMIIB
# pDA6BggrBgEFBQcCARYuaHR0cDovL3d3dy5kaWdpY2VydC5jb20vc3NsLWNwcy1y
# ZXBvc2l0b3J5Lmh0bTCCAWQGCCsGAQUFBwICMIIBVh6CAVIAQQBuAHkAIAB1AHMA
# ZQAgAG8AZgAgAHQAaABpAHMAIABDAGUAcgB0AGkAZgBpAGMAYQB0AGUAIABjAG8A
# bgBzAHQAaQB0AHUAdABlAHMAIABhAGMAYwBlAHAAdABhAG4AYwBlACAAbwBmACAA
# dABoAGUAIABEAGkAZwBpAEMAZQByAHQAIABDAFAALwBDAFAAUwAgAGEAbgBkACAA
# dABoAGUAIABSAGUAbAB5AGkAbgBnACAAUABhAHIAdAB5ACAAQQBnAHIAZQBlAG0A
# ZQBuAHQAIAB3AGgAaQBjAGgAIABsAGkAbQBpAHQAIABsAGkAYQBiAGkAbABpAHQA
# eQAgAGEAbgBkACAAYQByAGUAIABpAG4AYwBvAHIAcABvAHIAYQB0AGUAZAAgAGgA
# ZQByAGUAaQBuACAAYgB5ACAAcgBlAGYAZQByAGUAbgBjAGUALjAdBgNVHQ4EFgQU
# j+h+8G0yagAFI8dwl2o6kP9r6tQwHwYDVR0jBBgwFoAUsT7DaQP4v0cB1JgmGggC
# 72NkK8MwDQYJKoZIhvcNAQELBQADggEBABkzSgyBMzfbrTbJ5Mk6u7UbLnqi4vRD
# Qheev06hTeGx2+mB3Z8B8uSI1en+Cf0hwexdgNLw1sFDwv53K9v515EzzmzVshk7
# 5i7WyZNPiECOzeH1fvEPxllWcujrakG9HNVG1XxJymY4FcG/4JFwd4fcyY0xyQwp
# ojPtjeKHzYmNPxv/1eAal4t82m37qMayOmZrewGzzdimNOwSAauVWKXEU1eoYObn
# AhKguSNkok27fIElZCG+z+5CGEOXu6U3Bq9N/yalTWFL7EZBuGXOuHmeCJYLgYyK
# O4/HmYyjKm6YbV5hxpa3irlhLZO46w4EQ9f1/qbwYtSZaqXBwfBklIAxgg+rMIIP
# pwIBATCBgDBsMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkw
# FwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSswKQYDVQQDEyJEaWdpQ2VydCBFViBD
# b2RlIFNpZ25pbmcgQ0EgKFNIQTIpAhALhtAE1iqy3BEl7IX117EeMA0GCWCGSAFl
# AwQCAQUAoHwwEAYKKwYBBAGCNwIBDDECMAAwGQYJKoZIhvcNAQkDMQwGCisGAQQB
# gjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkE
# MSIEIMwfW359gFUByMUozenctIMOO80L3/3jboovVaZO6mfwMA0GCSqGSIb3DQEB
# AQUABIIBADFZq2MrdTl0eCGfqucH9wyryfoQaXqEha1rQNBdNkvj01nUiPHvD1Rb
# BqiE0yl7jMrsieWfItGYnS1a74COSrsSEkvL4fY4AHBdFZtg8ELpyCYtB1Sl221u
# gBYCgpZCMotAHD4itPpokE/OXJHT5zkT5DvJgPrMqZPbwClRe47X5rdLUK4TFTq0
# xsRRiBcey8RYWvuq6Ulq7oI5a2T5bwucxNlNNMLH04C2Tge9VWJ0aSCyJhSOm22W
# 0GX9H/I6pP5Psc6pf7Xqf78ZAzvuvLwUo9tUMeVy9SRtRD3OGBctSUcflbwhT7uS
# c8Q8BTQuCa4D5jCnKnrGt5SkGiBPhvGhgg19MIINeQYKKwYBBAGCNwMDATGCDWkw
# gg1lBgkqhkiG9w0BBwKggg1WMIINUgIBAzEPMA0GCWCGSAFlAwQCAQUAMHcGCyqG
# SIb3DQEJEAEEoGgEZjBkAgEBBglghkgBhv1sBwEwMTANBglghkgBZQMEAgEFAAQg
# vw9QyvgAenfnSAbOTAJU6o51MNjHMcXakgU3BPw/fbsCEEh+C5uxceul0MBq6LFR
# CJcYDzIwMjEwODA0MTgzOTAxWqCCCjcwggT+MIID5qADAgECAhANQkrgvjqI/2BA
# Ic4UAPDdMA0GCSqGSIb3DQEBCwUAMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxE
# aWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMT
# KERpZ2lDZXJ0IFNIQTIgQXNzdXJlZCBJRCBUaW1lc3RhbXBpbmcgQ0EwHhcNMjEw
# MTAxMDAwMDAwWhcNMzEwMTA2MDAwMDAwWjBIMQswCQYDVQQGEwJVUzEXMBUGA1UE
# ChMORGlnaUNlcnQsIEluYy4xIDAeBgNVBAMTF0RpZ2lDZXJ0IFRpbWVzdGFtcCAy
# MDIxMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAwuZhhGfFivUNCKRF
# ymNrUdc6EUK9CnV1TZS0DFC1JhD+HchvkWsMlucaXEjvROW/m2HNFZFiWrj/Zwuc
# Y/02aoH6KfjdK3CF3gIY83htvH35x20JPb5qdofpir34hF0edsnkxnZ2OlPR0dNa
# No/Go+EvGzq3YdZz7E5tM4p8XUUtS7FQ5kE6N1aG3JMjjfdQJehk5t3Tjy9XtYcg
# 6w6OLNUj2vRNeEbjA4MxKUpcDDGKSoyIxfcwWvkUrxVfbENJCf0mI1P2jWPoGqtb
# sR0wwptpgrTb/FZUvB+hh6u+elsKIC9LCcmVp42y+tZji06lchzun3oBc/gZ1v4N
# SYS9AQIDAQABo4IBuDCCAbQwDgYDVR0PAQH/BAQDAgeAMAwGA1UdEwEB/wQCMAAw
# FgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwQQYDVR0gBDowODA2BglghkgBhv1sBwEw
# KTAnBggrBgEFBQcCARYbaHR0cDovL3d3dy5kaWdpY2VydC5jb20vQ1BTMB8GA1Ud
# IwQYMBaAFPS24SAd/imu0uRhpbKiJbLIFzVuMB0GA1UdDgQWBBQ2RIaOpLqwZr68
# KC0dRDbd42p6vDBxBgNVHR8EajBoMDKgMKAuhixodHRwOi8vY3JsMy5kaWdpY2Vy
# dC5jb20vc2hhMi1hc3N1cmVkLXRzLmNybDAyoDCgLoYsaHR0cDovL2NybDQuZGln
# aWNlcnQuY29tL3NoYTItYXNzdXJlZC10cy5jcmwwgYUGCCsGAQUFBwEBBHkwdzAk
# BggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tME8GCCsGAQUFBzAC
# hkNodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRTSEEyQXNzdXJl
# ZElEVGltZXN0YW1waW5nQ0EuY3J0MA0GCSqGSIb3DQEBCwUAA4IBAQBIHNy16Zoj
# vOca5yAOjmdG/UJyUXQKI0ejq5LSJcRwWb4UoOUngaVNFBUZB3nw0QTDhtk7vf5E
# AmZN7WmkD/a4cM9i6PVRSnh5Nnont/PnUp+Tp+1DnnvntN1BIon7h6JGA0789P63
# ZHdjXyNSaYOC+hpT7ZDMjaEXcw3082U5cEvznNZ6e9oMvD0y0BvL9WH8dQgAdryB
# DvjA4VzPxBFy5xtkSdgimnUVQvUtMjiB2vRgorq0Uvtc4GEkJU+y38kpqHNDUdq9
# Y9YfW5v3LhtPEx33Sg1xfpe39D+E68Hjo0mh+s6nv1bPull2YYlffqe0jmd4+TaY
# 4cso2luHpoovMIIFMTCCBBmgAwIBAgIQCqEl1tYyG35B5AXaNpfCFTANBgkqhkiG
# 9w0BAQsFADBlMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkw
# FwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1
# cmVkIElEIFJvb3QgQ0EwHhcNMTYwMTA3MTIwMDAwWhcNMzEwMTA3MTIwMDAwWjBy
# MQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3
# d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFzc3VyZWQg
# SUQgVGltZXN0YW1waW5nIENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKC
# AQEAvdAy7kvNj3/dqbqCmcU5VChXtiNKxA4HRTNREH3Q+X1NaH7ntqD0jbOI5Je/
# YyGQmL8TvFfTw+F+CNZqFAA49y4eO+7MpvYyWf5fZT/gm+vjRkcGGlV+Cyd+wKL1
# oODeIj8O/36V+/OjuiI+GKwR5PCZA207hXwJ0+5dyJoLVOOoCXFr4M8iEA91z3Fy
# Tgqt30A6XLdR4aF5FMZNJCMwXbzsPGBqrC8HzP3w6kfZiFBe/WZuVmEnKYmEUeaC
# 50ZQ/ZQqLKfkdT66mA+Ef58xFNat1fJky3seBdCEGXIX8RcG7z3N1k3vBkL9olMq
# T4UdxB08r8/arBD13ays6Vb/kwIDAQABo4IBzjCCAcowHQYDVR0OBBYEFPS24SAd
# /imu0uRhpbKiJbLIFzVuMB8GA1UdIwQYMBaAFEXroq/0ksuCMS1Ri6enIZ3zbcgP
# MBIGA1UdEwEB/wQIMAYBAf8CAQAwDgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoG
# CCsGAQUFBwMIMHkGCCsGAQUFBwEBBG0wazAkBggrBgEFBQcwAYYYaHR0cDovL29j
# c3AuZGlnaWNlcnQuY29tMEMGCCsGAQUFBzAChjdodHRwOi8vY2FjZXJ0cy5kaWdp
# Y2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3J0MIGBBgNVHR8EejB4
# MDqgOKA2hjRodHRwOi8vY3JsNC5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVk
# SURSb290Q0EuY3JsMDqgOKA2hjRodHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGln
# aUNlcnRBc3N1cmVkSURSb290Q0EuY3JsMFAGA1UdIARJMEcwOAYKYIZIAYb9bAAC
# BDAqMCgGCCsGAQUFBwIBFhxodHRwczovL3d3dy5kaWdpY2VydC5jb20vQ1BTMAsG
# CWCGSAGG/WwHATANBgkqhkiG9w0BAQsFAAOCAQEAcZUS6VGHVmnN793afKpjerN4
# zwY3QITvS4S/ys8DAv3Fp8MOIEIsr3fzKx8MIVoqtwU0HWqumfgnoma/Capg33ak
# OpMP+LLR2HwZYuhegiUexLoceywh4tZbLBQ1QwRostt1AuByx5jWPGTlH0gQGF+J
# OGFNYkYkh2OMkVIsrymJ5Xgf1gsUpYDXEkdws3XVk4WTfraSZ/tTYYmo9WuWwPRY
# aQ18yAGxuSh1t5ljhSKMYcp5lH5Z/IwP42+1ASa2bKXuh1Eh5Fhgm7oMLSttosR+
# u8QlK0cCCHxJrhO24XxCQijGGFbPQTS2Zl22dHv1VjMiLyI2skuiSpXY9aaOUjGC
# AoYwggKCAgEBMIGGMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJ
# bmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0
# IFNIQTIgQXNzdXJlZCBJRCBUaW1lc3RhbXBpbmcgQ0ECEA1CSuC+Ooj/YEAhzhQA
# 8N0wDQYJYIZIAWUDBAIBBQCggdEwGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEE
# MBwGCSqGSIb3DQEJBTEPFw0yMTA4MDQxODM5MDFaMCsGCyqGSIb3DQEJEAIMMRww
# GjAYMBYEFOHXgqjhkb7va8oWkbWqtJSmJJvzMC8GCSqGSIb3DQEJBDEiBCB6DHTe
# 5sxVaTTz3vIh5yzAshpxL9wYG9z3w9zEhFeDTDA3BgsqhkiG9w0BCRACLzEoMCYw
# JDAiBCCzEJAGvArZgweRVyngRANBXIPjKSthTyaWTI01cez1qTANBgkqhkiG9w0B
# AQEFAASCAQCQZZ7TTXDm/Dy2Uu4/JzRtsX6hIbUQouLMJivcfeEnUhBRnssHh+l6
# qHZ0Z11rj/2MifLvWx0D7tnTV6YS0vnqTqBQAPKmaXftJ3xuaw68sLMhA7A5294N
# QwtUY1SY7aYHt/ERkPnIEyy8otJ+0bG4JrBgDHuTEgI5UgaT7d92sCJNBp86jAmg
# SXYcD65GGfEvNQzdIzuKNq+CN6Z00VYRNT+VXbcGx81phnnVHWeqaxE0UKHzk5R6
# lv5gTpRukSwUGEbD9Pdqr9DpF7YMfX8SgC1St7vLzVJbhMtrVLK6si7VQKmsM6tY
# 5itRA1q2GA2HKI9y2hyn695FbzhAi3Un
# SIG # End signature block
