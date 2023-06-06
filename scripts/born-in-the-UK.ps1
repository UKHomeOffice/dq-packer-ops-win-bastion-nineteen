Write-Host 'Region and Locale'

Write-Host "Home Location"
$home_location = Get-WinHomeLocation
if ($home_location.GeoId -eq "242")
{
    Write-Host "Home Location already set to United Kingdom"
}
else
{
    Write-Host 'Setting home location to the United Kingdom'
    Set-WinHomeLocation 242
}


Write-Host 'System Locale'
$sys_loc = Get-WinSystemLocale
if ($sys_loc.Name -eq "en-GB")
{
    Write-Host "System Locale already set to British"
}
else
{
    Write-Host "Setting System Locale to British"
    Set-WinSystemLocale en-GB
}


Write-Host "Region"
$reg_cult = Get-Culture
if ($reg_cult.Name -eq "en-GB")
{
    Write-Host "Regional format already set to British"
}
else
{
    Write-Host 'Setting regional format (date/time etc.) to British'
    Set-Culture en-GB
}

Write-Host "We're done here!"
