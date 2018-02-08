<#
.SYNOPSIS
    Gets Interconnect uplink port statistics from OneView.

.DESCRIPTION
    Gets the uplink port statistics (Rx/Tx) for one or more interconnects in OneView.  Only FlexFabric interconnects
    (not FiberChannel) and Ethernet ports are retrieved.

.PARAMETER Appliance
    Name of the OneView appliance.  This parameter is optional if there is already a connected session in
    $global:ConnectedSessions.

.PARAMETER Enclosure
    Optional name of an enclosure to get interconnects for.  If omitted all interconnects for all enclosures
    are retrieved.

.PARAMETER Interconnect
    Optional name of a specific interconnect to retrieve info for.  The name should match the one shown in
    OneView.

.PARAMETER Mbps
    Displays output in Mbps (instead of Kbps)

.EXAMPLE
    Get statistics for all interconnects in a OneView appliance:

    Get-InterconnectPortStats.ps1 -Appliance oneview.mydomain.local

.EXAMPLE
    Get statistics for a single interconnect:

    Get-InterconnectPortStats.ps1 -Interconnect 'MyEnclosure, interconnect 1' -Appliance oneview.mydomain.local

.EXAMPLE
    Get statistics for all interconnects in an enclosure:

    Get-InterconnectPortStats.ps1 -Enclosure 'MyEnclosure'

.NOTES
    Requires HPOneView module

#>
[CmdletBinding()]
param (
    [Parameter(Mandatory=$false,ValueFromPipeline=$true)]
    [string]$Appliance,
    [string]$Enclosure,
    [string]$Interconnect,
    [switch]$Mbps
)
Begin {
    If ($Appliance) {
        Try {
            $ovw = Connect-HPOVMgmt -Appliance $Appliance
        }
        Catch {
            Throw "OneView appliance connection failed."
        }
    }
    ElseIf ($global:ConnectedSessions.Count -eq 1) {
        # use existing session
        $ovw = $global:ConnectedSessions[0]
        Write-Host "Using existing connection: $($ovw.Name)"
    }
    Else {
        Write-Warning "You must specify an appliance name using '-Appliance' or already be connected using Connect-HPOVMgmt."
        Throw "No OneView appliance connection."
    }
    $results = @()  # array containing the results
}

Process {
    $ovwInterconnects = @()
    If ($Interconnect) {
        Write-Host "Getting interconnect: $Interconnect"
        $ovwInterconnects += Get-HPOVInterconnect -Name $Interconnect -ApplianceConnection $ovw
        $output = "UplinkStats-$Interconnect-$(Get-Date -format 'yyyy.MM.dd.HHmm').csv"
    }
    ElseIf ($Enclosure) {
        Write-Host "Getting interconnects for enclosure: $Enclosure"
        $ovwEncl = Get-HPOVEnclosure -ApplianceConnection $ovw -Name $Enclosure
        ForEach ($bay in $ovwEncl.interconnectBays) {
            If ($bay.interconnectModel -Match 'FlexFabric') {
                $ovwInterconnects += (Send-HPOVRequest -Uri $bay.interconnectUri -Hostname $ovw.Name)
            }
        }
        $output = "UplinkStats-$Enclosure-$(Get-Date -format 'yyyy.MM.dd.HHmm').csv"
    }
    Else {
        Write-Host "Getting interconnects from appliance: $($ovw.Name)"
        $ovwInterconnects += Get-HPOVInterconnect -ApplianceConnection $ovw | where 'Model' -match 'FlexFabric'
        $output = "UplinkStats-$($ovw.Name)-$(Get-Date -format 'yyyy.MM.dd.HHmm').csv"
    }
    Write-Host "Number of interconnects retrieved: $($ovwInterconnects.Count)"

    ForEach ($ovwInterconnect in $ovwInterconnects) {
        Write-Host "Getting ports for $($ovwInterconnect.Name)"
        $ports = $ovwInterconnect.ports | where 'portType' -eq 'Uplink' | where 'portStatus' -eq 'Linked' `
            | where 'capability' -contains 'Ethernet'
        ForEach ($port in $ports) {
            $stats = Show-HPOVPortStatistics -Interconnect $ovwInterconnect -Port $port
            If ($Mbps) {
                $portStats = New-Object -TypeName PSObject -Prop ([ordered]@{
                    'Interconnect Name' = $ovwInterconnect.Name;
                    'Port' = $port.portName;
                    # Stats are colon separated, 5 min averages for the last hour, for example:
                    # receiveKilobitsPerSec = 151190:279679:629017:109710:91270:47977:65880:62032:67159:57164:61977:53091
                    # The first sample is the last 5 min average
                    'Rx Mb/s' = [math]::Round(($stats.advancedStatistics.receiveKilobitsPerSec.split(':')[0]/1024), 1)
                    'Tx Mb/s' = [math]::Round(($stats.advancedStatistics.transmitKilobitsPerSec.split(':')[0]/1024), 1)
                    'Rx Packets/s' = $stats.advancedStatistics.receivePacketsPerSec.split(':')[0]
                    'Tx Packets/s' = $stats.advancedStatistics.transmitPacketsPerSec.split(':')[0]
                })
            }
            Else {
                $portStats = New-Object -TypeName PSObject -Prop ([ordered]@{
                    'Interconnect Name' = $ovwInterconnect.Name;
                    'Port' = $port.portName;
                    # Stats are colon separated, 5 min averages for the last hour, for example:
                    # receiveKilobitsPerSec = 151190:279679:629017:109710:91270:47977:65880:62032:67159:57164:61977:53091
                    # The first sample is the last 5 min average
                    'Rx Kb/s' = $stats.advancedStatistics.receiveKilobitsPerSec.split(':')[0]
                    'Tx Kb/s' = $stats.advancedStatistics.transmitKilobitsPerSec.split(':')[0]
                    'Rx Packets/s' = $stats.advancedStatistics.receivePacketsPerSec.split(':')[0]
                    'Tx Packets/s' = $stats.advancedStatistics.transmitPacketsPerSec.split(':')[0]

                })
            }
            $results += $portStats
        }
    }
} # end process block

End {
    # Save results to CSV
    $results | Export-Csv -Path $output -NoTypeInformation

    # Write results to the console
    $results | Format-Table -AutoSize
}
