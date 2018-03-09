
<#
.SYNOPSIS
    Functions for getting and updating iLO firmware.

.DESCRIPTION
    Uses the HP OA Cmdlets to get and update iLO firmware. An image file (.bin) needs to be
    provided via a URL, e.g. "http://<my server>/hp/ilo4_242.bin".  Download the iLO firmware
    update from HPE's website and extract the contents to find a file with the .bin extension.

 .EXAMPLE
    Get firmware versions less than 2.42.

    Get-OAiLOFW -Chassis 10.0.0.1 | where 'Version' -lt '2.42'

 .EXAMPLE
    Get firmware versions from two chassis, passing the IPs in the pipeline, filter for the ones 
    less than 2.42 and update them:

    "10.0.0.1","10.0.0.2" | Get-OAiLOFW | where 'Version' -lt '2.42' | Update-OAiLOFW
	
.LINK
	https://www.hpe.com/servers/powershell

.LINK
	https://github.com/doogleit/hpe-oneview-misc
#>

Function Get-OAiLOFW {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$True,Position=0,ValueFromPipeline=$true)]
        [string]$Chassis,
		[string]$Usr,
		[string]$Pwd

    )
    begin {
        $devices = @()
    }
    process {
        # Connect to OA
        $connection = Connect-HPOA -OA $Chassis -Username $Usr -Password $Pwd

        # Get Chassis Firmware
        $chassisFW = Get-HPOAFWSummary $connection

        # Get Device Firmware
        Write-Verbose "Getting firmware for devices in chassis $Chassis"
        foreach ($device in $chassisFW.DeviceFirmwareInformation) {
            foreach ($item in $device.DeviceFWDetail) {
                if ($item.FirmwareComponent -match "iLO4") {
                    $deviceInfo = New-Object System.Object
                    $deviceInfo | Add-Member -Name Chassis -Value $Chassis -type NoteProperty
                    $deviceInfo | Add-Member -Name Bay -Value $device.Bay -type NoteProperty
                    $deviceInfo | Add-Member -Name Component -Value $item.FirmwareComponent -type NoteProperty
                    $deviceInfo | Add-Member -Name Version -Value $item.CurrentVersion -type NoteProperty
                    $devices += $deviceInfo
                }
            }
        }

        # Disconnect from OA
        Disconnect-HPOA $connection
    }
    end {
        return $devices
    }
}

Function Update-OAiLOFW {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$True,Position=0,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [string]$Chassis,
        [Parameter(Mandatory=$True,Position=1,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [string]$Bay,
        [Parameter(Mandatory=$false,Position=2)]
        [string]$FirmwareURL, # "http://<my server>/hp/ilo4_242.bin"
		[string]$Usr,
		[string]$Pwd
    )
    begin {
        $results = @()
    }
    process {
        # Connect to OA
        $connection = Connect-HPOA -OA $Chassis -Username $Usr -Password $Pwd

        # Update Device Firmware
        Write-Verbose "Updating firmware on $Chassis bay #$Bay"
        $results += Update-HPOAiLO -Connection $connection -Bay $Bay -url $FirmwareURL -Verbose

        # Disconnect from OA
        Disconnect-HPOA $connection
    }
    end {
        return $results
    }
}
