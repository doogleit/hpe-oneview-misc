<#
.SYNOPSIS
    A script to setup new HPE rack servers.
    WARNING - It will POWER OFF/RESET the server(s).

.DESCRIPTION
    Configures a list of new HPE rack servers provided in a CSV file.
    - Configures iLO networking (Hostname, DNS, NTP)
    - Updates iLO Firmware
    - Configures BIOS power management
    - Configures BIOS boot order
    - Mounts the SPP ISO and boots it - this ISO will update all the firmware
    - Mounts the ESXi ISO and boots it - ideally this should be an unattended install

.PARAMETER CSVFile
    A CSV file containing the Hostname, iLO IP address, and credentials for each iLO.
    Headings/format: Hostname, iLOIP, Username, Password

.NOTES
    Tested with HPiLOCmdlets 1.3.0.1 and DL360s
#>
# -requires HPiLOCmdlets
[CmdletBinding()]
param (
    [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
    [string]$CSVFile
)
# Firmware and ISO options
[string]$iLOFirmware = 'C:\HP\ilo\ilo4_244.bin'
[string]$version = '2.44'
[string]$SPPISO = 'http://10.0.0.1/iso/864794_001_spp-2016.04.0-SPP2016040.2016_0317.20.iso'
[string]$ESXISO = 'http://10.0.0.1/iso/VMware-ESXi-6.0.0-Update2-3620759-HPE-600.U2.9.4.7.13-Mar2016.iso'
[string]$BootOder = 'Boot0008'  # UEFI USB device, for Legacy BIOS use 'CDROM,USB'
[int]$PowerSaver = 1            # 1 = OS controlled power management, 4 = high performance

# Global Parameters for the iLO network
$globalNetworkParams = @{
    Domain = 'domain.local'
    PrimDNSServer = '10.0.0.1'
    SecDNSServer = ''
    TerDNSServer = ''
    SNTPServer1 = ''
    SNTPServer2 = ''
    Timezone = 'EST5EDT'
}

# Supress the HP cmdlets annoying DNS warning
Set-Variable -Name 'WarningPreference'  -Value 'SilentlyContinue' -Scope Script

# Loop through each iLO, configure settings and boot to SPP ISO
$iLOs = Import-Csv $csvFile
ForEach ($iLO in $iLOs) {
    # Global parameters used by every HP cmdlet
    $globalParams = @{
        Server = $iLO.iLOIP
        Username = $iLO.Username
        Password = $iLO.Password
        DisableCertificateAuthentication = $true
    }

    # Parameters for the iLO network
    $networkParams = $null
    $networkParams = $globalNetworkParams + @{
        DNSName = $iLO.Hostname
    }

    # Set iLO Network Settings
    Write-Host "Configuring network settings for iLO: $($iLO.iLOIP)"
    Set-HPiLONetworkSetting @networkParams @globalParams

    # Wait for iLO to reset
    Do {
        Start-Sleep -Seconds 10
    } Until ((Find-HPiLO $iLO.iLOIP) -ne $null)

    # Update iLO firmware
    # This is done separately to avoid issues with OneView and because the latest version
    # is usually not in the SPP
    Write-Host "Checking iLO firmware for version: $version"
    If ((Get-HPiLOFirmwareVersion @globalParams).FIRMWARE_VERSION -lt $version) {
        Write-Host "Updating iLO firmware using $iLOFirmware"
        Update-HPiLOFirmware -Location $iLOFirmware @globalParams

        # Wait for iLO to update and reset
        Do {
            Start-Sleep -Seconds 10
            If ((Find-HPiLO $iLO.iLOIP) -ne $null) {
                $results = Get-HPiLOFirmwareVersion @globalParam
            }
        } Until ($results.FIRMWARE_VERSION -eq $version)
    }

    # Power off server - some BIOS changes cannot be made during POST
    #   (i.e. if no OS is installed and it is looping through the boot order)
    Write-Host "Powering OFF server, iLO: $($iLO.iLOIP)"
    Set-HPiLOVirtualPowerButton @globalParams -PressType HOLD | Out-Null

    # Set Power Management
    Write-Host "Setting BIOS power management"
    Set-HPiLOHostPowerSaver -PowerSaver $PowerSaver @globalParams

    # Set Persistent Boot Order
    Write-Host "Setting BIOS boot order"
    Set-HPiLOPersistentBootOrder -BootOrder $BootOder @globalParams

    # Mount SPP ISO and boot
    Write-Host "Mounting SPP ISO from $SPPISO"
    Mount-HPiLOVirtualMedia -Device CDROM -ImageURL $SPPISO @globalParams
    Set-HPiLOVMStatus -Device CDROM -VMBootOption BOOT_ONCE @globalParams
    Write-Host "Setting one time boot to CDROM"
    Set-HPiLOOneTimeBootOrder -Device CDROM @globalParams
    Write-Host "Powering ON server, iLO: $($iLO.iLOIP)"
    Set-HPiLOHostPower -HostPower On @globalParams

    # Wait for Power On
    Write-Host "Waiting for server to power ON"
    Do {
        Start-Sleep -Seconds 10
        $results = Get-HPiLOHostPower @globalParams
    } Until ($results.HOST_POWER -eq 'ON')
    Write-Host "The SPP should be booting now and will run automatically"
    Write-Host "`n" # insert blank line
}

# Loop through each iLO again and boot the ESXi ISO
# This could be included in the same foreach loop above, but getting all the SPPs started and running
# in parallel saves a lot of time. This loop will wait for the virtual media to disconnect, indicating
# the SPP has finished before continuing.
ForEach ($iLO in $iLOs) {
    # Global parameters used by every HP cmdlet
    $globalParams = @{
        Server = $iLO.iLOIP
        Username = $iLO.Username
        Password = $iLO.Password
        DisableCertificateAuthentication = $true
    }

    # Wait for Virtual Media disconnect
    Write-Host "Waiting for virtual media to disconnect on $($iLO.iLOIP)"
    Do {
        Start-Sleep -Seconds 10
        $results = Get-HPiLOVMStatus -Device CDROM @globalParams
    } Until ($results.IMAGE_INSERTED -eq 'NO')

    # Mount ESX ISO and reboot
    # Power off the server first.  If the server is in POST the one time boot order cannot be modified.
    Write-Host "Powering OFF server, iLO: $($iLO.iLOIP)"
    Set-HPiLOVirtualPowerButton @globalParams -PressType HOLD
    Write-Host "Mounting ESXi ISO from $ESXISO"
    Mount-HPiLOVirtualMedia -Device CDROM -ImageURL $ESXISO @globalParams    Set-HPiLOVMStatus -Device CDROM -VMBootOption BOOT_ONCE @globalParams
    Write-Host "Setting one time boot to CDROM"
    Set-HPiLOOneTimeBootOrder -Device CDROM @globalParams
    Write-Host "Powering ON server, iLO: $($iLO.iLOIP)"
    Set-HPiLOHostPower -HostPower On @globalParams

    Write-Host "ESXi should be booting up now"
    Write-Host "`n" # insert blank line
}
