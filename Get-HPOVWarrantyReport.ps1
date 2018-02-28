<#
.SYNOPSIS
    Gets warranty information (Remote Support Entitlements) for one or more compute objects in OneView.

.DESCRIPTION
    Gets one or more compute objects (Servers/Enclosures) in OneView and reports their warranty/entitlement
    information.  Remote Support must be enabled.

.PARAMETER Appliance
    Name of the OneView appliance.  This parameter is optional if there is already a connected session in
    $global:ConnectedSessions.

.PARAMETER Enclosure
    Optional name of an enclosure to get warranty info for.  Using a wildcard (*) is supported.

.PARAMETER Server
    Optional name of a server to get warranty info for.  Using a wildcard (*) is supported.

.PARAMETER Output
    Output file name.  Results will be written to this file in CSV format.

.EXAMPLE
    Get warranty info for all servers and enclosures in a OneView appliance:

    Get-HPOVWarrantyReport.ps1 -Appliance oneview.mydomain.local

.EXAMPLE
    Get warranty info for servers with a matching name:

    Get-HPOVWarrantyReport.ps1 -Server 'server*' -Appliance oneview.mydomain.local

.NOTES
    Requires HPOneView module, version 3.10 or higher
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory=$false,ValueFromPipeline=$true)]
    [string]$Appliance,
    [string]$Enclosure,
    [string]$Server,
    [string]$Output
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
        Write-Verbose "Using existing connection: $($ovw.Name)"
    }
    Else {
        Write-Warning "You must specify an appliance name using '-Appliance' or already be connected using Connect-HPOVMgmt."
        Throw "No OneView appliance connection."
    }
    $results = @()  # array containing the results
}

Process {
    $ovwHardware = @()
    If ($Server) {
        $ovwHardware += Get-HPOVServer -Name $Server -ApplianceConnection $ovw
    }
    ElseIf ($Enclosure) {
        $ovwHardware += Get-HPOVEnclosure -ApplianceConnection $ovw -Name $Enclosure
    }
    Else {
        $ovwHardware += Get-HPOVServer -ApplianceConnection $ovw
        $ovwHardware += Get-HPOVEnclosure -ApplianceConnection $ovw
    }
    Write-Verbose "Number of compute objects retrieved: $($ovwHardware.Count)"

    ForEach ($ovwObject in $ovwHardware) {
        Write-Verbose "Getting entitlement for: $($ovwObject.name)"
        $entitlement = $ovwObject | Get-HPOVRemoteSupportEntitlementStatus
        
        If ($ovwObject.Model){
            $model = $ovwObject.Model
        }
        Else {
            $model = $ovwObject.enclosureModel
        }

        $warrantyStats = New-Object -TypeName PSObject -Prop ([ordered]@{
                    'Name' = $ovwObject.Name;
                    'Model' = $model;
                    'ProductNumber' = $ovwObject.partNumber;
                    'SerialNumber' = $ovwObject.serialNumber;
                    'ObligationID' = $entitlement.ObligationId;
                    'ObligationEndDate' = $entitlement.ObligationEndDate
         })
         $results += $warrantyStats
    }
} # end process block

End {
    If ($Output) {
        # Save results to CSV
        $results | Export-Csv -Path $Output -NoTypeInformation
    }
    Else {
        $results
    }
}
