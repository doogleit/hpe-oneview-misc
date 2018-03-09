# hpe-oneview-misc
Miscellaneous scripts for managing OneView and HPE servers.

## Get-HPOVInterconnectPorts.ps1
Gets the uplink port information for one or more interconnects in OneView.  Specifically it collects the information listed under "Remote connection" for each Interconnect port of type "Ethernet" typically the remote switch name, IP address, and port ID.  This is particularly useful for documenting all the upstream ports for a chassis or for providing this information to your network team.

## Get-HPOVInterconnectPortStats.ps1
Gets the uplink port statistics (Rx/Tx) for one or more interconnects in OneView.  This information is under the Statistics section for each interconnect port in OneView.  This allows you to easily collect bandwidth usage for every port in every enclosure.

## Get-HPOVWarrantyReport.ps1
Gets warranty information (Remote Support Entitlements) for one or more compute objects in OneView.

## New-OASetup.ps1
Sample script for configuring the OA in a c7000 enclosure.

## New-RackHostSetup.ps1
Sample script for configuring iLOs and booting from an ISO.