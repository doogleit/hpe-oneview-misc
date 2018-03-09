<#
.SYNOPSIS
    Configures a HP OA for a new deployment.

.DESCRIPTION
    Configures a HP OA including:
        Enclosure Name
        Alert Mail - recipient email address
        Date and Time - local NTP and timezone
        Enclosure TCP/IP Settings - OAs, enable IP mode, disable IPv6
        Link Loss Failover - enabled
        SNMP Settings - enable and set read community name
        Enclosure Bay IP Addressing - first 4 interconnects and first 1-16 blades
        Users/Authentication - local user, directory services, 'ESX Admins' group
    You must provide an OA IP address to connect to.  This is assumed to be OA1.  The next 21 consecutive
    IP addresses will be used for OA2, the interconnects (4 IPs), and iLOs (up to 16 IPs).  If you specify
    the last slot number that is populated (-LastSlot) fewer IPs will be used for the iLOs.
	
.PARAMETER EnclosureName
    The name of the enclosure.  This is set in the Enclosure Information section and used as the sender name
    for Alert Mail.
	
.PARAMETER OAIP
    The IP address of OA1.  This is used to connect to the OA and as a starting IP address for configuring the
    remaining IP addresses (OA2, interconnects, iLOs).
	
.PARAMETER User
    The administrator user to login to the OA.  Default is Administrator.
	
.PARAMETER Password
    The administrator password.
	
.PARAMETER LastSlot
    The last slot that is populated in the chassis.  This determines the number of iLO IP addresses assigned.
    By default this is 16 and every slot is configured.  Empty slots or slots subsumed by a full height blade
    can still be configured when not in use.
	
.EXAMPLE
    New-OASetup.ps1 -EnclosureName "MyEnclosure" -OAIP "10.0.0.1" -Password "xxxxxxxxxxx"

    This example has all required parameters so no prompts are displayed.  The password is enclosed in
    quotes to prevent any special characters from being misinterpreted by powershell.

.NOTES
	Tested on c7000 enclosures.

.LINK
	https://www.hpe.com/servers/powershell

.LINK
	https://github.com/doogleit/hpe-oneview-misc
 #>
#Requires -version 3
#Requires -modules HPOACmdlets
 param (
    $EnclosureName = $(Read-Host "Enter the enclosure name"),
    $OAIP = $(Read-Host "Enter the OA IP address"),
    $User = 'Administrator',
    $Password = $(Read-Host "Enter the Administrator password"),
    [int]$LastSlot = 16,
 )

# Global mail settings (change these)
$emailTo = 'admin@domain.local'
$smtpServer = 'smtp.domain.local'
$senderDomain = 'domain.local'

# Optional local admin - to create an additional account other than the default 'Administrator'
$OAUsername = ''
$OAPwd = ''

# Location settings for multiple datacenters (change these)
switch -wildcard ($OAIP) {
    "10.0.*" {
        $location = 'DC1'
        $netmask = '255.255.255.0'
        $gateway = '10.0.0.254'
        $dns1 = '10.0.0.2'
        $dns2 = ''
        $dns3 = ''
        $domain = 'domain.local'
        $ntp = 'ntp.domain.local'
        $snmpCommunity = 'notpublic'
        $ldapServer = 'ldap.domain.local'
        $ldapSearch = 'OU=Users,OU=Admin,DC=domain,DC=local'
        $tz = 'EST'
    }
    "10.1.*" {
        $location = 'DC2'
        $netmask = '255.255.255.0'
        $gateway = '10.1.0.254'
        $dns1 = '10.1.0.2'
        $dns2 = ''
        $dns3 = ''
        $domain = 'domain.local'
        $ntp = 'ntp.domain.local'
        $snmpCommunity = 'notpublic'
        $ldapServer = 'ldap.domain.local'
        $ldapSearch = 'OU=Users,OU=Admin,DC=domain,DC=local'
        $tz = 'CST'
    }
}

# Start logging
$logFile = "OASetup_$(Get-Date -UFormat "%Y%m%d%H%M%S").log"
Start-Transcript $logFile
Write-Host "Location is: $location"

# Get IP Addresses -
# Starting with the OA1 IP get consecutive IP addresses for OA2, interconnects, and iLOs
$octets = $OAIP.split('.')  # split the address into octets
$baseIP = $octets[0..2] -join '.'  # use first 3 octets for the base IP
[int]$lastOctet = $octets[3]  # the last octet is defined as an integer [int] so it can be easily incremented using ++

# OA2 IP
$OA2IP = "$($baseIP).$((++$lastOctet))" # the 2nd OA IP
Write-Host "OA2 IP address: $OA2IP"

# Interconnect IPs - next 4 addresses
$interconnectIPs = @()
ForEach ($bay in 1..4) {
    $interconnectIPs += "$($baseIP).$((++$lastOctet))"
}
Write-Host "Interconnect IPs: $interconnectIPs"

# iLO IPs - next 16 addresses (or less if $lastSlot was specified)
$iloIPs = @()
ForEach ($bay in 1..$lastSlot) {
    $iloIPs += "$($baseIP).$((++$lastOctet))"
}
Write-Host "iLO IPs: $iloIPs"

# Connect to the Onboard Administrator
$OA = Connect-HPOA -OA $OAIP -Username $user -Password $password

# Enclosure Settings
$enclInfo = Get-HPOAEnclosureInfo -Connection $OA
If ($enclInfo.EnclosureName -ne $EnclosureName) {
    Write-Host "Setting enclosure name"
    Set-HPOAEnclosure -Connection $OA -Name $EnclosureName
}

# AlertMail - can't get existing settings, just configure it
Write-Host "Configuring Alert Mail"
Set-HPOAAlertmail -Connection $OA -Email $emailTo -SMTPServer $smtpServer -Domain $senderDomain # No option to set sender
# Enable AlertMail once chassis is in production
#Set-HPOAAlertmail -Connection $OA -State Enable

# Device Power Sequence - these should be disabled by default, but we will check each one anyway
# and disable if necessary
ForEach ($item in (Get-HPOAServerPowerDelay -Connection $OA).PowerDelayDetail) {
    If ($item.PowerDelayState -ne 'Disabled') {
        Write-Host "Disabling device power delay for bay $($item.bay)"
        Set-HPOAPowerDelay -Connection $OA -Target Server -Bay $item.bay -Delay 0
    }
}

# Date and Time - can't get existing settings, just configure it
Write-Host "Configuring Date/Time"
Set-HPOANTP -Connection $OA -PrimaryHost $ntp -PollInterval 28800
Set-HPOATimezone -Connection $OA  -Timezone $tz
Set-HPOANTP -Connection $OA -State Enable


# Enclosure TCP/IP Settings
Write-Host "Setting enclosure TCP/IP settings"
Write-Host "Enabling IP mode"
Set-HPOAEnclosureIPMode -Connection $OA -State Enable
Write-Host "Disabling IPv6 - this will produce a warning if it is already disabled"
Set-HPOAIPv6 -Connection $OA -State Disable
# NIC link setting - this is auto by default
#Write-Host "Setting OA NIC to Auto-Negotiate"
#Set-HPOANIC -Connection $OA -LinkSetting Auto
Write-Host "Setting OA names"
Set-HPOAName -Connection $OA -Bay 1 -Name "$EnclosureName-OA1"
Set-HPOAName -Connection $OA -Bay 2 -Name "$EnclosureName-OA2"

# OA IP settings should already be configured.  Commands below for reference.
#Set-HPOAIPConfig -Connection $OA -Bay 1 -Mode Static -IP $OA1IP -Netmask $netmask -Gateway $gateway -DNS1 $dns1 -DNS2 $dns2
#Set-HPOAIPConfig -Connection $OA -Bay 2 -Mode Static -IP $OA2IP -Netmask $netmask -Gateway $gateway -DNS1 $dns1 -DNS2 $dns2

# Enclosure Network Access - these are set by default
#Set-HPOAHTTPS -Connection $OA -State Enable
#Set-HPOASecureSh -Connection $OA -State Enable
#Set-HPOATelnet -Connection $OA -State Disable
#Set-HPOAXMLReply -Connection $OA -State Enable
#Set-HPOAEnclosureiLOFederationSupport -Connection $OA -State Enable

# Link Loss Failover
Write-Host "Enabling Link Loss Failover"
Set-HPOALLF -Connection $OA -State Enable

# SNMP Settings
Write-Host "Enabling SNMP and setting read community name"
Set-HPOASNMP -Connection $OA -State Enable -Type Read -CommunityName $snmpCommunity


# Enclosure Bay IP Addressing
Write-Host "Configuring Interconnect IPs"
ForEach ($bay in 1..4) {  # interconnect bays
    Set-HPOAEBIPA -Connection $OA -Target Interconnect -IP $interconnectIPs[$bay-1] -Netmask $netmask -Gateway $gateway -Domain $domain -Bay $bay
    Add-HPOAEBIPA -Connection $OA -Target Interconnect -Bay $bay -IP $dns1
    Add-HPOAEBIPA -Connection $OA -Target Interconnect -Bay $bay -IP $dns2
    Add-HPOAEBIPA -Connection $OA -Target Interconnect -Bay $bay -IP $dns3
    Set-HPOAEBIPA -Connection $OA -State Enable -Target Interconnect -Bay $bay
}
Write-Host "Configuring iLO IPs"
ForEach ($bay in 1..$lastSlot) {  # device bays
    Set-HPOAEBIPA -Connection $OA -Target Server -IP $iloIPs[$bay-1] -Netmask $netmask -Gateway $gateway -Domain $domain -Bay $bay
    Add-HPOAEBIPA -Connection $OA -Target Server -Bay $bay -IP $dns1
    Add-HPOAEBIPA -Connection $OA -Target Server -Bay $bay -IP $dns2
    Add-HPOAEBIPA -Connection $OA -Target Server -Bay $bay -IP $dns3
    Set-HPOAEBIPA -Connection $OA -State Enable -Target Server -Bay $bay
}

# Users/Authentication
# Local Users
If ($OAUsername) {
    Write-Host "Creating Admin user: $OAUsername"
    Add-HPOAUser -Connection $OA -Username $OAUsername -Password $OAPwd
    Set-HPOAUser -Connection $OA -Username $OAUsername -Access Administrator
    Add-HPOAUserPrivilege -Connection $OA -Username $OAUsername # Grant access to OA
    Add-HPOAUserBay -Connection $OA -Username $OAUsername -Target Interconnect -Bay ALL # Grant access to all Interconnects
    Add-HPOAUserBay -Connection $OA -Username $OAUsername -Target Server -Bay ALL # Grant access to all server bays
}

# Directory Settings
Write-Host "Setting directory/LDAP settings"
Set-HPOALDAPSetting -Connection $OA -Server $ldapServer -Port 636
Set-HPOALDAPSetting -Connection $OA -SearchPriority 1 -SearchContent $ldapSearch
# To set additional LDAP search paths:
#Set-HPOALDAPSetting -Connection $OA -SearchPriority 2 -SearchContent $ldapSearch
Set-HPOALDAP -Connection $OA -State Enable -LocalUser Enable

# Directory Groups
Write-Host "Adding 'ESX Admins' directory group"
Add-HPOALDAPGroup -Connection $OA -Group 'ESX Admins'
Set-HPOALDAPSetting -Connection $OA -Group 'ESX Admins' -Access Administrator
Add-HPOALDAPPrivilege -Connection $OA -Group 'ESX Admins'  # Grant access to OA
Add-HPOALDAPBay -Connection $OA -Group 'ESX Admins' -Target Interconnect -Bay ALL # Grant access to all Interconnects
Add-HPOALDAPBay -Connection $OA -Group 'ESX Admins' -Target Server -Bay ALL # Grant access to all server bays

# Save Config
$oaconfig = get-hpoaconfig -Connection $OA
$oaconfig.Config | Out-File ".\OAConfig_$($oaconfig.Hostname)_$(Get-Date -UFormat "%Y%m%d").txt"

# Disconnect from OA
Write-Host "Disconnecting from OA"
Disconnect-HPOA $OA

# Stop logging
Stop-Transcript
