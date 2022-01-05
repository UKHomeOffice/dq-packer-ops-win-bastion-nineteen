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

	Start sysprep with answer file provided in the current directory.

.DESCRIPTION

    Ensure Unattend.xml is located under Sysprep directory.

.PARAMETER NoShutdown

    NoShutdown prevents sysprep to shutdown the instance.

.EXAMPLE

    ./SysprepInstance

#>
param (
    [parameter(Mandatory=$false)]
    [switch] $NoShutdown
)

Set-Variable rootPath -Option Constant -Scope Local -Value (Join-Path $env:ProgramData -ChildPath "Amazon\EC2-Windows\Launch")
Set-Variable modulePath -Option Constant -Scope Local -Value (Join-Path $rootPath -ChildPath "Module\Ec2Launch.psd1")
Set-Variable scriptPath -Option Constant -Scope Local -Value (Join-Path $PSScriptRoot -ChildPath $MyInvocation.MyCommand.Name)
Set-Variable sysprepResDir -Option Constant -Scope Local -Value (Join-Path $rootPath -ChildPath "Sysprep")
Set-Variable beforeSysprepFile -Option Constant -Scope Local -Value (Join-Path $sysprepResDir -ChildPath "BeforeSysprep.cmd")
Set-Variable answerFilePath -Option Constant -Scope Local -Value (Join-Path $sysprepResDir -ChildPath "Unattend.xml")
Set-Variable sysprepPath -Option Constant -Scope Local -Value (Join-Path $env:windir -ChildPath "System32\Sysprep\Sysprep.exe")
Set-Variable powershellPath -Option Constant -Scope Local -Value (Join-Path $env:windir -ChildPath "System32\WindowsPowerShell\v1.0\powershell.exe")
Set-Variable assistPath -Option Constant -Scope Local -Value (Join-Path $sysprepResDir -ChildPath "Randomize-LocalAdminPassword.ps1")

# Import Ec2Launch module to prepare to use helper functions.
Import-Module $modulePath

# Check if answer file is located in correct path.
if (-not (Test-Path $answerFilePath))
{
    throw New-Object System.IO.FileNotFoundException("{0} not found" -f $answerFilePath)
}

if (-not (Test-Path $sysprepPath))
{
    throw New-Object System.IO.FileNotFoundException("{0} not found" -f $sysprepPath)
}

# Update the unattend.xml.
try
{
    # Get the locale and admin name to update unattend.xml
    $localAdmin = Get-CimInstance -ClassName Win32_UserAccount -Filter "LocalAccount='True'" | Where-Object {$_.SID -like 'S-1-5-21-*' -and $_.SID -like '*-500'}
    $localAdminName = $localAdmin.Name
    $locale = ([CultureInfo]::CurrentCulture).IetfLanguageTag

    # Get content as xml
    $content = [xml](Get-Content $answerFilePath)

    # Search for empty locales and assign the correct locale for current OS
    $localeTarget = ($content.unattend.settings | where {$_.pass -ieq 'oobeSystem'}).component | `
                    where {$_.name -ieq 'Microsoft-Windows-International-Core'}
    if ($localeTarget.InputLocale -eq '') { $localeTarget.InputLocale = $locale }
    if ($localeTarget.SystemLocale -eq '') { $localeTarget.SystemLocale = $locale }
    if ($localeTarget.UILanguage -eq '') { $localeTarget.UILanguage = $locale }
    if ($localeTarget.UserLocale -eq '') { $localeTarget.UserLocale = $locale }

    # Search for the first empty RunSynchronousCommand and assign the correct command for current OS
    $adminTarget = (($content.unattend.settings | where {$_.pass -ieq 'specialize'}).component | `
                    where {$_.name -ieq 'Microsoft-Windows-Deployment'}).RunSynchronous | `
                    Foreach {$_.RunSynchronousCommand | where {$_.Order -eq 1 }}
    if ($adminTarget.Path -eq '') { $adminTarget.Path = "$powershellPath {0} {1}" -f $assistPath, $localAdmin.Name }

    # Save the final xml content
    $content.Save($answerFilePath)
}
catch
{
    Write-Warning "Failed to update the custom answer file. Ignore this message if you modified the file."
}

# Clear instance information from wallpaper.
try
{
    Clear-Wallpaper
}
catch
{
    Write-Warning ("Failed to update the wallpaper: {0}" -f $_.Exception.Message)
}

#Disable hibernation
try
{
    Disable-HibernateOnSleep
}
catch
{
    Write-Warning ("Failed to disable hibernation prior to sysprep: {0}" -f $_.Exception.Message)
}

# Unregister userdata scheduled task.
try
{
    Invoke-Userdata -OnlyUnregister
}
catch
{
    Write-Warning ("Failed to unreigster the userdata scheduled task: {0}" -f $_.Exception.Message)
}

# Perform commands in BeforeSysprep.cmd.
if (Test-Path $beforeSysprepFile)
{
    Invoke-Item $beforeSysprepFile
}

# Finally, perform sysprep.
if ($NoShutdown)
{
    Start-Process -FilePath $sysprepPath -ArgumentList ("/oobe /quit /generalize `"/unattend:{0}`"" -f $answerFilePath) -Wait -NoNewWindow
}
else
{
    Start-Process -FilePath $sysprepPath -ArgumentList ("/oobe /shutdown /generalize `"/unattend:{0}`"" -f $answerFilePath) -Wait -NoNewWindow
}


# SIG # Begin signature block
# MIIc9QYJKoZIhvcNAQcCoIIc5jCCHOICAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCPd0DAFcSJmiv/
# rwnHX+UMyz2CUuncgbVATCQPPPoi0aCCDJ8wggXbMIIEw6ADAgECAhALhtAE1iqy
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
# O4/HmYyjKm6YbV5hxpa3irlhLZO46w4EQ9f1/qbwYtSZaqXBwfBklIAxgg+sMIIP
# qAIBATCBgDBsMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkw
# FwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSswKQYDVQQDEyJEaWdpQ2VydCBFViBD
# b2RlIFNpZ25pbmcgQ0EgKFNIQTIpAhALhtAE1iqy3BEl7IX117EeMA0GCWCGSAFl
# AwQCAQUAoHwwEAYKKwYBBAGCNwIBDDECMAAwGQYJKoZIhvcNAQkDMQwGCisGAQQB
# gjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkE
# MSIEIG099GLcAoFaKfqgNRCsoD7mbAAhAMdAMg5z2sigaIFyMA0GCSqGSIb3DQEB
# AQUABIIBAEzUVBIOH2IWA2KPAfaM8Uvvt3Fhzgnhd+1cPeBEww6+/Q33bdIItK69
# zEiFITWTGvdkKpvHnmzWFbwkfN4cetq/k6yoRYFGngomyYxKE4Zp048/XOLzT8Zz
# TTo+7Rsl2m1LMKMxCyYXW3rUEfuziMMeSAYW3FnOVHF3hrP1LGmSQ9Mphkzxq9qn
# oOkTTYb6oKF/jDUTpHuvqqlyS16konPGmWVu5EQV5FmgTjdR+/A9oCAMu7Woqoj+
# 2pD27TkzBOAxyML+G+ynaAZpNPmOL1Xj8D8+a6gDDuG7akzDMEaOCwK5dI3hAbDo
# 7FRU9PDzwRF2zREcEFIJDm1czrA71hGhgg1+MIINegYKKwYBBAGCNwMDATGCDWow
# gg1mBgkqhkiG9w0BBwKggg1XMIINUwIBAzEPMA0GCWCGSAFlAwQCAQUAMHgGCyqG
# SIb3DQEJEAEEoGkEZzBlAgEBBglghkgBhv1sBwEwMTANBglghkgBZQMEAgEFAAQg
# Min6Msckw8hVEf90Uon8+sGkEz68Bf72nK3LFHa/JBMCEQCGWVXJt3UZBtHv/oQs
# knmzGA8yMDIxMDgwNDE4MzkxMlqgggo3MIIE/jCCA+agAwIBAgIQDUJK4L46iP9g
# QCHOFADw3TANBgkqhkiG9w0BAQsFADByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMM
# RGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQD
# EyhEaWdpQ2VydCBTSEEyIEFzc3VyZWQgSUQgVGltZXN0YW1waW5nIENBMB4XDTIx
# MDEwMTAwMDAwMFoXDTMxMDEwNjAwMDAwMFowSDELMAkGA1UEBhMCVVMxFzAVBgNV
# BAoTDkRpZ2lDZXJ0LCBJbmMuMSAwHgYDVQQDExdEaWdpQ2VydCBUaW1lc3RhbXAg
# MjAyMTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAMLmYYRnxYr1DQik
# Rcpja1HXOhFCvQp1dU2UtAxQtSYQ/h3Ib5FrDJbnGlxI70Tlv5thzRWRYlq4/2cL
# nGP9NmqB+in43Stwhd4CGPN4bbx9+cdtCT2+anaH6Yq9+IRdHnbJ5MZ2djpT0dHT
# WjaPxqPhLxs6t2HWc+xObTOKfF1FLUuxUOZBOjdWhtyTI433UCXoZObd048vV7WH
# IOsOjizVI9r0TXhG4wODMSlKXAwxikqMiMX3MFr5FK8VX2xDSQn9JiNT9o1j6Bqr
# W7EdMMKbaYK02/xWVLwfoYervnpbCiAvSwnJlaeNsvrWY4tOpXIc7p96AXP4Gdb+
# DUmEvQECAwEAAaOCAbgwggG0MA4GA1UdDwEB/wQEAwIHgDAMBgNVHRMBAf8EAjAA
# MBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMEEGA1UdIAQ6MDgwNgYJYIZIAYb9bAcB
# MCkwJwYIKwYBBQUHAgEWG2h0dHA6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzAfBgNV
# HSMEGDAWgBT0tuEgHf4prtLkYaWyoiWyyBc1bjAdBgNVHQ4EFgQUNkSGjqS6sGa+
# vCgtHUQ23eNqerwwcQYDVR0fBGowaDAyoDCgLoYsaHR0cDovL2NybDMuZGlnaWNl
# cnQuY29tL3NoYTItYXNzdXJlZC10cy5jcmwwMqAwoC6GLGh0dHA6Ly9jcmw0LmRp
# Z2ljZXJ0LmNvbS9zaGEyLWFzc3VyZWQtdHMuY3JsMIGFBggrBgEFBQcBAQR5MHcw
# JAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBPBggrBgEFBQcw
# AoZDaHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0U0hBMkFzc3Vy
# ZWRJRFRpbWVzdGFtcGluZ0NBLmNydDANBgkqhkiG9w0BAQsFAAOCAQEASBzctema
# I7znGucgDo5nRv1CclF0CiNHo6uS0iXEcFm+FKDlJ4GlTRQVGQd58NEEw4bZO73+
# RAJmTe1ppA/2uHDPYuj1UUp4eTZ6J7fz51Kfk6ftQ55757TdQSKJ+4eiRgNO/PT+
# t2R3Y18jUmmDgvoaU+2QzI2hF3MN9PNlOXBL85zWenvaDLw9MtAby/Vh/HUIAHa8
# gQ74wOFcz8QRcucbZEnYIpp1FUL1LTI4gdr0YKK6tFL7XOBhJCVPst/JKahzQ1Ha
# vWPWH1ub9y4bTxMd90oNcX6Xt/Q/hOvB46NJofrOp79Wz7pZdmGJX36ntI5nePk2
# mOHLKNpbh6aKLzCCBTEwggQZoAMCAQICEAqhJdbWMht+QeQF2jaXwhUwDQYJKoZI
# hvcNAQELBQAwZTELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZ
# MBcGA1UECxMQd3d3LmRpZ2ljZXJ0LmNvbTEkMCIGA1UEAxMbRGlnaUNlcnQgQXNz
# dXJlZCBJRCBSb290IENBMB4XDTE2MDEwNzEyMDAwMFoXDTMxMDEwNzEyMDAwMFow
# cjELMAkGA1UEBhMCVVMxFTATBgNVBAoTDERpZ2lDZXJ0IEluYzEZMBcGA1UECxMQ
# d3d3LmRpZ2ljZXJ0LmNvbTExMC8GA1UEAxMoRGlnaUNlcnQgU0hBMiBBc3N1cmVk
# IElEIFRpbWVzdGFtcGluZyBDQTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoC
# ggEBAL3QMu5LzY9/3am6gpnFOVQoV7YjSsQOB0UzURB90Pl9TWh+57ag9I2ziOSX
# v2MhkJi/E7xX08PhfgjWahQAOPcuHjvuzKb2Mln+X2U/4Jvr40ZHBhpVfgsnfsCi
# 9aDg3iI/Dv9+lfvzo7oiPhisEeTwmQNtO4V8CdPuXciaC1TjqAlxa+DPIhAPdc9x
# ck4Krd9AOly3UeGheRTGTSQjMF287DxgaqwvB8z98OpH2YhQXv1mblZhJymJhFHm
# gudGUP2UKiyn5HU+upgPhH+fMRTWrdXyZMt7HgXQhBlyF/EXBu89zdZN7wZC/aJT
# Kk+FHcQdPK/P2qwQ9d2srOlW/5MCAwEAAaOCAc4wggHKMB0GA1UdDgQWBBT0tuEg
# Hf4prtLkYaWyoiWyyBc1bjAfBgNVHSMEGDAWgBRF66Kv9JLLgjEtUYunpyGd823I
# DzASBgNVHRMBAf8ECDAGAQH/AgEAMA4GA1UdDwEB/wQEAwIBhjATBgNVHSUEDDAK
# BggrBgEFBQcDCDB5BggrBgEFBQcBAQRtMGswJAYIKwYBBQUHMAGGGGh0dHA6Ly9v
# Y3NwLmRpZ2ljZXJ0LmNvbTBDBggrBgEFBQcwAoY3aHR0cDovL2NhY2VydHMuZGln
# aWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEUm9vdENBLmNydDCBgQYDVR0fBHow
# eDA6oDigNoY0aHR0cDovL2NybDQuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJl
# ZElEUm9vdENBLmNybDA6oDigNoY0aHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0Rp
# Z2lDZXJ0QXNzdXJlZElEUm9vdENBLmNybDBQBgNVHSAESTBHMDgGCmCGSAGG/WwA
# AgQwKjAoBggrBgEFBQcCARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzAL
# BglghkgBhv1sBwEwDQYJKoZIhvcNAQELBQADggEBAHGVEulRh1Zpze/d2nyqY3qz
# eM8GN0CE70uEv8rPAwL9xafDDiBCLK938ysfDCFaKrcFNB1qrpn4J6JmvwmqYN92
# pDqTD/iy0dh8GWLoXoIlHsS6HHssIeLWWywUNUMEaLLbdQLgcseY1jxk5R9IEBhf
# iThhTWJGJIdjjJFSLK8pieV4H9YLFKWA1xJHcLN11ZOFk362kmf7U2GJqPVrlsD0
# WGkNfMgBsbkodbeZY4UijGHKeZR+WfyMD+NvtQEmtmyl7odRIeRYYJu6DC0rbaLE
# frvEJStHAgh8Sa4TtuF8QkIoxhhWz0E0tmZdtnR79VYzIi8iNrJLokqV2PWmjlIx
# ggKGMIICggIBATCBhjByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQg
# SW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2Vy
# dCBTSEEyIEFzc3VyZWQgSUQgVGltZXN0YW1waW5nIENBAhANQkrgvjqI/2BAIc4U
# APDdMA0GCWCGSAFlAwQCAQUAoIHRMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRAB
# BDAcBgkqhkiG9w0BCQUxDxcNMjEwODA0MTgzOTEyWjArBgsqhkiG9w0BCRACDDEc
# MBowGDAWBBTh14Ko4ZG+72vKFpG1qrSUpiSb8zAvBgkqhkiG9w0BCQQxIgQgRbAT
# BRe4viWmMb/LYKkFnRe7Fw86d7xIfQ8gVEETPCcwNwYLKoZIhvcNAQkQAi8xKDAm
# MCQwIgQgsxCQBrwK2YMHkVcp4EQDQVyD4ykrYU8mlkyNNXHs9akwDQYJKoZIhvcN
# AQEBBQAEggEAlQNt5pWUt2zEXilZukU6BUx8iELTqc8RnHwZpfA4WXGCw0IcOmOp
# LAd7arq2dDUfDVoyL7axilZQLh3gqF8lsngsX/pnnsO+ulUmNHj5zyslcyhV7eNR
# z3QyucMEhSDYwMhDIGX6RBdZqrlNmRfjTwCDi71lfTipoK7SxIWUj5n7GcdfQsbe
# bVnCDGcasTa/1Rxt8/GagEX1NrnR0QUZPXXke1vwLowkuzKkUY6dInMIjECHeUdc
# 2CELSvSrlZYWAn6k7TxuvDp8fhJYybOAuPSiP1vtNeAHKkeEw2W+uVI2tT4SeZa3
# omZFAa2mxEEjS1dIMElgiqHdIZBBvvpoNA==
# SIG # End signature block
