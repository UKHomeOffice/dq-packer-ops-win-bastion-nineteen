#Init


# Variables
$ErrorActionPreference = "Stop"
$PythonExpectedDisplayName = "Python 2.7.15 (64-bit)"

# Functions
function GetPythonRegistryValue(){
  return (Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Select-Object DisplayName | where {$_.DisplayName -Like "${PythonExpectedDisplayName}" }).DisplayName
}

# Create Python Folder
Write-Host "Creating Python Install Folder"
cd C:\
'Binaries\Python27' | % {New-Item -Name "Tools\$_" -ItemType 'Directory'}

# Add Python to System PATH
Write-Host "Adding Python to System Path"
[Environment]::SetEnvironmentVariable('Path',$Env:Path + ';C:\Tools\Binaries\Python27;C:\Tools\Binaries\Python27\Scripts;C:\Tools\Scripts', 'Machine')

# Reload System PATH
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
Write-Host "System Path is now: $env:Path"

# Download Python MSI
$file = "python-2.7.15.amd64.msi"
$link = "https://artefactrepository.service.ops.iptho.co.uk/repository/python/2.7.15/$file"
$tmp = "$env:TEMP\$file"
Write-Host "Downloading Python 2.7.15 from: $link"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $link -OutFile $tmp

# Install Python 2.7.15
msiexec /i $tmp /qn AllUsers=1 TargetDir="C:\Tools\Binaries\Python27"
Write-Host "Installing Python 2.7.15"

# Check Python installed correctly and output to screen/log
$Count = 0
$PythonRegistryValue = GetPythonRegistryValue

While ($PythonRegistryValue -ne $PythonExpectedDisplayName){
    If ($Count -gt 6) {
        Throw "Python install failed, looking for '${PythonExpectedDisplayName}' but actually got '${PythonRegistryValue}'"
    } Else {
        $Count++
        Write-Host "Python install not complete, sleeping..."
        Start-Sleep -Seconds 10
        Write-Host "Checking Python is installed correctly before continuing"
        $PythonRegistryValue = GetPythonRegistryValue
    }
}

Write-Host "Python version ${PythonRegistryValue} successfully installed"

# Install pip For Package Management
Write-Host "Installing pip"
Start-Process -FilePath "python.exe" -ArgumentList ("-m", "ensurepip") -Wait

# Check pip Is Up To Date
Write-Host "Updating pip"
Start-Process -FilePath "python.exe" -ArgumentList ("-m", "pip", "install", "--upgrade", "pip") -Wait

# Install psutil for windows service querying
Write-Host "Install psutil"
Start-Process -FilePath "pip.exe" -ArgumentList ("install", "psutil") -Wait

# Install pytest for Buildtime Tooling Testing
Write-Host "Installing pytest"
Start-Process -FilePath "pip.exe" -ArgumentList ("install", "pytest") -Wait

# Tidy Up
Write-Host "Removing python .msi"
Remove-Item $tmp


# End
