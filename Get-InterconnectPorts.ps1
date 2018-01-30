<#
.SYNOPSIS
    Gets Interconnect uplink port information from OneView.

.DESCRIPTION
    Gets the uplink port information for one or more interconnects in OneView.  Only FlexFabric interconnects
    (not FiberChannel) and Ethernet ports are retrieved.  The corrensponding uplink set from the Logical
    Interconnect Group is also retrieved for each port and the VLANs that should be configured are listed.

.PARAMETER Appliance
    Name of the OneView appliance.  This parameter is optional if there is already a connected session in
    $global:ConnectedSessions.

.PARAMETER Enclosure
    Optional name of an enclosure to get interconnects for.  If omitted all interconnects for all enclosures
    are retrieved.

.PARAMETER Interconnect
    Optional name of a specific interconnect to retrieve info for.  The name should match the one shown in
    OneView.

.EXAMPLE
    Get info for all interconnects in a OneView appliance:

    Get-InterconnectPorts.ps1 -Appliance oneview.mydomain.local

.EXAMPLE
    Get info for a single interconnect:

    Get-InterconnectPorts.ps1 -Interconnect 'MyEnclosure, interconnect 1' -Appliance oneview.mydomain.local

.EXAMPLE
    Get info for all interconnects in an enclosure:

    Get-InterconnectPorts.ps1 -Enclosure 'MyEnclosure'

.NOTES
    Requires HPOneView module

#>
[CmdletBinding()]
param (
    [Parameter(Mandatory=$false,ValueFromPipeline=$true)]
    [string]$Appliance,
    [string]$Enclosure,
    [string]$Interconnect
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
    If ($Interconnect) {
        Write-Host "Getting interconnect: $Interconnect"
        $ovwInterconnects = Get-HPOVInterconnect -Name $Interconnect -ApplianceConnection $ovw
        $output = "UplinkInfo-$Interconnect-$(Get-Date -format 'yyyy.MM.dd.HHmm').csv"
    }
    ElseIf ($Enclosure) {
        Write-Host "Getting interconnects for enclosure: $Enclosure"
        $ovwEncl = Get-HPOVEnclosure -ApplianceConnection $ovw -Name $Enclosure
        $ovwInterconnects = @()
        ForEach ($bay in $ovwEncl.interconnectBays) {
            If ($bay.interconnectModel -Match 'FlexFabric') {
                $ovwInterconnects += (Send-HPOVRequest -Uri $bay.interconnectUri -Hostname $ovw.Name)
            }
        }
        $output = "UplinkInfo-$Enclosure-$(Get-Date -format 'yyyy.MM.dd.HHmm').csv"
    }
    Else {
        Write-Host "Getting interconnects from appliance: $($ovw.Name)"
        $ovwInterconnects = Get-HPOVInterconnect -ApplianceConnection $ovw | where 'Model' -match 'FlexFabric'
        $output = "UplinkInfo-$($ovw.Name)-$(Get-Date -format 'yyyy.MM.dd.HHmm').csv"
    }
    Write-Host "Number of interconnects retrieved: $($ovwInterconnects.Count)"

    ForEach ($ovwInterconnect in $ovwInterconnects) {
        Write-Host "Getting ports for $($ovwInterconnect.Name)"
        $ports = $ovwInterconnect.ports | where 'portType' -eq 'Uplink' | where 'portStatus' -eq 'Linked' `
            | where 'capability' -contains 'Ethernet'
        ForEach ($port in $ports) {
            $uplinkSet = Send-HPOVRequest -Uri $port.associatedUplinkSetUri -Hostname $ovw.Name
            $networkUris = $uplinkSet.networkUris
            $vlans = @()
            ForEach ($netUri in $networkUris) {
                $vlans += (Send-HPOVRequest $netUri -Hostname $ovw.Name).vlanId
            }
            $portInfo = New-Object -TypeName PSObject -Prop ([ordered]@{
                'Interconnect Name' = $ovwInterconnect.Name;
                'Interconnect Port' = $port.portName;
                'Switch Port' = $port.neighbor.remotePortId;
                'Port Description' = $port.neighbor.remotePortDescription;
                'Address Type' = $port.neighbor.remoteMgmtAddressType;
                'Switch Address' = $port.neighbor.remoteMgmtAddress;
                'Switch Name' = $port.neighbor.remoteSystemName
                'Vlans' = ($vlans -join ', ')
            })
            $results += $portInfo
        }
    }
} # end process block

End {
    # Save results to CSV
    $results | Export-Csv -Path $output -NoTypeInformation

    # Write results to the console
    $results | Format-Table -AutoSize
}
