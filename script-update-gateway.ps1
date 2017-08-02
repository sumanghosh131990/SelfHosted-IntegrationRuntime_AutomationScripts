﻿# This script is used to udpate my data management gateway when I don't want my gateway auto updated, but I want to automate it myself.
# And the steps are like this:
# 1. check my current gateway version
# 2. check latest gateway version or specified version
# 3. if there is newer version than current version gateway available 
#    3.1 download gateway msi
#    3.2 upgrade it

## And here is the usage:
## 1. Download and install latest gateway
## PS > .\script-update-gateway.ps1
## 2. Download and install gateway of specified version
## PS > .\script-update-gateway.ps1 -version 2.11.6380.20

param([string]$version)

function Get-CurrentGatewayVersion()
{
    $registryKeyValue = Get-RegistryKeyValue "Software\Microsoft\DataTransfer\DataManagementGateway\ConfigurationManager"

    $baseFolderPath = [System.IO.Path]::GetDirectoryName($registryKeyValue.GetValue("DiacmdPath"))
    $filePath = [System.IO.Path]::Combine($baseFolderPath, "Microsoft.DataTransfer.GatewayManagement.dll")
    
    $version = $null
    if (Test-Path $filePath)
    {
        $version = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($filePath).FileVersion
        $msg = "Current gateway: " + $version
        Write-Host $msg
    }
    
    return $version
}

function Get-LatestGatewayVersion()
{
    $latestGateway = Get-RedirectedUrl "https://go.microsoft.com/fwlink/?linkid=839822"
    $item = $latestGateway.split("/") | Select-Object -Last 1
    if ($item -eq $null -or $item -notlike "DataManagementGateway*")
    {
        throw "Can't get latest gateway info"
    }

    $regexp = '^DataManagementGateway_(\d+\.\d+\.\d+\.\d+) \(64-bit\)\.msi$'

    $version = [regex]::Match($item, $regexp).Groups[1].Value
    if ($version -eq $null)
    {
        throw "Can't get version from gateway download uri"
    }

    $msg = "Latest gateway: " + $version
    Write-Host $msg
    return $version
}

function Get-RegistryKeyValue
{
     param($registryPath)

     $is64Bits = Is-64BitSystem
     if($is64Bits)
     {
          $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
          return $baseKey.OpenSubKey($registryPath)
     }
     else
     {
          $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry32)
          return $baseKey.OpenSubKey($registryPath)
     }
}


function Get-RedirectedUrl 
{
    $URL = "https://go.microsoft.com/fwlink/?linkid=839822"
 
    $request = [System.Net.WebRequest]::Create($url)
    $request.AllowAutoRedirect=$false
    $response=$request.GetResponse()
 
    If ($response.StatusCode -eq "Found")
    {
        $response.GetResponseHeader("Location")
    }
}

function Download-GatewayInstaller
{
    Param (
        [Parameter(Mandatory=$true)]
        [String]$version
    )

    Write-Host "Start to download MSI"
    $uri = Populate-Url $version
    $folder = New-TempDirectory
    $output = Join-Path $folder "DataManagementGateway.msi"
    (New-Object System.Net.WebClient).DownloadFile($uri, $output)

    $exist = Test-Path($output)
    if ( $exist -eq $false)
    {
        throw "Cannot download specified MSI"
    }

    $msg = "New gateway MSI has been downloaded to " + $output
    Write-Host $msg
    return $output
}

function Populate-Url
{
    Param (
        [Parameter(Mandatory=$true)]
        [String]$version
    )
    
    $uri = Get-RedirectedUrl
    $uri = $uri.Substring(0, $uri.LastIndexOf('/') + 1)
    $uri += "DataManagementGateway_$version ("
    
    $is64Bits = Is-64BitSystem
    if ($is64Bits)
    {
        $uri += "64-bit"
    }
    else
    {
        $uri += "32-bit"
    }
    $uri += ").msi"

    return $uri
}

function Install-Gateway
{
    Param (
        [Parameter(Mandatory=$true)]
        [String]$msi
    )

    $exist = Test-Path($msi)
    if ( $exist -eq $false)
    {
        throw 'there is no MSI found: $msi'
    }


    Write-Host "Start to install gateway ..."

    $arg = "/i " + $msi + " /quiet /norestart"
    Start-Process -FilePath "msiexec.exe" -ArgumentList $arg -Wait -Passthru -NoNewWindow
    
    Write-Host "Gateway has been successfully updated!"
}

function New-TempDirectory {
    $parent = [System.IO.Path]::GetTempPath()
    [string] $name = [System.Guid]::NewGuid()
    New-Item -ItemType Directory -Path (Join-Path $parent $name)
}


function Is-64BitSystem
{
     $computerName= $env:COMPUTERNAME
     $osBit = (get-wmiobject win32_processor -computername $computerName).AddressWidth
     return $osBit -eq '64'
}

$currentVersion = Get-CurrentGatewayVersion
if ($currentVersion -eq $null)
{
    Write-Host "There is no gateway found on your machine, exiting ..."
    exit 0
}

$versionToInstall = $version
if ([string]::IsNullOrEmpty($versionToInstall))
{
    $versionToInstall = Get-LatestGatewayVersion
}

if ([System.Version]$currentVersion -ge [System.Version]$versionToInstall)
{
    Write-Host "Your gateway is latest, no update need..."
}
else
{
    $msi = Download-GatewayInstaller $versionToInstall
    Install-Gateway $msi
    Remove-Item -Path $msi -Force
}