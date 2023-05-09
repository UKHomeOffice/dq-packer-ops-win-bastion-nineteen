Start-Transcript -path C:\PerfLogs\userdata_output.log -append

Write-Host 'Getting IP address of host!'
$myip = Get-Netipaddress -addressfamily ipv4

$firstoctate = $myip[0].ipaddress.Substring(0,4)
$secondoctate = $myip[0].ipaddress.Substring(5,4)

Write-Host $firstoctate
Write-Host $secondoctate

Write-Host 'Deciphering the Environment!'
if($firstoctate -eq "10.8")
{
$environment = "notprod"

}

elseif($firstoctate -eq "10.2")
{
$environment = "prod"

}

else {
$environment = "test"

}

Write-Host ">>>>>>>>>>> Environment is $environment! <<<<<<<<<<<<<"

Write-Host 'Deciphering the Bastion!'
if($secondoctate -eq "0.12")
{
$bastion = "WIN-BASTION-1"

}

elseif($secondoctate -eq "0.13")
{
$bastion = "WIN-BASTION-2"

}

elseif($secondoctate -eq "0.14")
{
$bastion = "WIN-BASTION-3"

}

else {
$bastion = "WIN-BASTION-4"

}

Write-Host ">>>>>>>>>>> Host is $bastion <<<<<<<<<<<<<"

Write-Host 'Adding bucket variable'
[Environment]::SetEnvironmentVariable("S3_OPS_CONFIG_BUCKET", "s3-dq-ops-config-$environment/sqlworkbench", "Machine")
[System.Environment]::SetEnvironmentVariable('S3_OPS_CONFIG_BUCKET','s3-dq-ops-config-$environment/sqlworkbench')

Write-Host 'Adding Tableau Development RDP Shortcuts to Desktop'
Copy-Item -Path C:\misc\* -Filter *-$environment* -Destination C:\Users\Public\Desktop -Recurse

Write-Host 'Installing the Windows RDS services'
Install-WindowsFeature -name windows-internal-database -Verbose
Install-WindowsFeature -Name RDS-RD-Server -Verbose -IncludeAllSubFeature
Install-WindowsFeature -Name RDS-licensing -Verbose
Install-WindowsFeature -Name RDS-connection-broker -IncludeAllSubFeature -verbose


Write-Host 'Creating pgadmin4 Shortcut to Desktop'
Move-Item 'C:\Users\Administrator\AppData\Local\Programs\pgAdmin 4' 'C:\Program Files'
$SourceFileLocation = 'C:\Program Files\pgAdmin 4\v6\runtime\pgAdmin4.exe'
$ShortcutLocation = 'C:\Users\Public\Desktop\pgAdmin4.lnk'
$WScriptShell = New-Object -ComObject WScript.Shell
$Shortcut = $WScriptShell.CreateShortcut($ShortcutLocation)
$Shortcut.TargetPath = $SourceFileLocation
$Shortcut.Save()
Write-Host 'pgAdmin4 Shortcut created! Click on pgAdmin 4 Folder to initialize shortcut!'



Write-Host 'Setting home location to the United Kingdom'
Set-WinHomeLocation 0xf2

Write-Host 'Setting system local'
Set-WinSystemLocale en-GB

Write-Host 'Setting regional format (date/time etc.) to English (United Kingdon) - this applies to all users'
Set-Culture en-GB

Write-Host 'Setting TimeZone to GMT'
Set-TimeZone "GMT Standard Time"

Stop-Transcript
