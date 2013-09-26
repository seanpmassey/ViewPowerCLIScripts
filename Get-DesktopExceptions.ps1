<#
.SYNOPSIS
   Get-DesktopExceptions is a script that will locate VMware View Linked Clones that are not using the correct snapshot/image.  The script also contains an option to remediate any non-compliant desktops by deleting them and letting View recreate them.
.DESCRIPTION
   Get-DesktopExceptions will look in the View LDAP datastore to find the snapshot IDs used by the desktops and the pool. It compares these values to find any desktops that do not match the pool.  If the -Remediate switch is selected, the script will then remove them.  In order to run this script, the Quest Active Directory Cmdlets will need to be installed.
.PARAMETER ConnectionServer
   The View Connection server that you want to run this script against.
.PARAMETER Remediate
   Delete desktops that do not have the correct snapshots
.PARAMETER EmailRcpt
   Person or group who should receive the email report
.PARAMETER SMTPServer
   Email server
.EXAMPLE
   Get-DesktopExceptions -ConnectionServer connection.domain.com -Remediate -EmailRcpt user@domain.com -SMTPServer smtp.domain.com
#>
param($ConnectionServer,[switch]$Remediate,$EmailRcpt,$SMTPServer)

Function Send-Email
{
 Param([string]$SMTPBody,[string]$SMTPSubject = "View Snapshot Compliance Report",[string]$SMTPTo,$SMTPServer)
Send-MailMessage -To $SMTPTo -Body $SMTPBody -Subject $SMTPSubject -SmtpServer $SMTPServer -From "Notifications_noreply@gbdioc.org" -BodyAsHtml
}


Function Get-Pools
{
param($ConnectionServer)

$PoolList = @()

$arrIncludedProperties = "cn,name,pae-DisplayName,pae-MemberDN,pae-SVIVmParentVM,pae-SVIVmSnapshot,pae-SVIVmSnapshotMOID".Split(",")
$pools = Get-QADObject -Service $ConnectionServer -DontUseDefaultIncludedProperties -IncludedProperties $arrIncludedProperties -LdapFilter "(objectClass=pae-ServerPool)" -SizeLimit 0 | Sort-Object "pae-DisplayName" | Select-Object Name, "pae-DisplayName", "pae-SVIVmParentVM" , "pae-SVIVmSnapshot", "pae-SVIVmSnapshotMOID", "pae-MemberDN"

ForEach($pool in $pools)
{
$obj = New-Object PSObject -Property @{
           "cn" = $pool.cn
           "name" = $pool.name
           "DisplayName" = $pool."pae-DisplayName"
           "MemberDN" = $pool."pae-MemberDN"
           "SVIVmParentVM" = $pool."pae-SVIVmParentVM"
           "SVIVmSnapshot" = $pool."pae-SVIVmSnapshot"
           "SVIVmSnapshotMOID" = $pool."pae-SVIVmSnapshotMOID"
		  }
$PoolList += $obj
}
Return $PoolList
}

Function Get-Desktop
{
param($MemberDN, $ConnectionServer)

$arrIncludedProperties = "cn,name,pae-DisplayName,pae-MemberDN,pae-SVIVmParentVM,pae-SVIVmSnapshot,pae-SVIVmSnapshotMOID".Split(",")
$Desktop = Get-QADObject -Service $ConnectionServer -DontUseDefaultIncludedProperties -IncludedProperties $arrIncludedProperties -LdapFilter "(&(objectClass=pae-Server)(distinguishedName=$MemberDN))" -SizeLimit 0 | Sort-Object "pae-DisplayName" | Select-Object Name, "pae-DisplayName", "pae-SVIVmParentVM" , "pae-SVIVmSnapshot", "pae-SVIVmSnapshotMOID"

Return $Desktop
}


$DesktopExceptions = @()
$pools = Get-Pools -ConnectionServer $ConnectionServer

ForEach($pool in $pools)
{
$MemberDNs = $pool.memberdn
	ForEach($MemberDN in $MemberDNs)
	{
	$Desktop = Get-Desktop -MemberDN $MemberDN -ConnectionServer $ConnectionServer
	
	If($Desktop."pae-SVIVmSnapshotMOID" -ne $pool.SVIVmSnapshotMOID)
		{
		$obj = New-Object PSObject -Property @{
           "PoolName" = $pool.DisplayName
		   "DisplayName" = $Desktop."pae-DisplayName"
		   "PoolSnapshot" = $pool.SVIVmSnapshot
		   "PoolSVIVmSnapshotMOID" = $pool.SVIVmSnapshotMOID
           "DesktopSVIVmSnapshot" = $Desktop."pae-SVIVmSnapshot"
           "DesktopSVIVmSnapshotMOID" = $Desktop."pae-SVIVmSnapshotMOID"
		   "DesktopDN" = $MemberDN
		  }
$DesktopExceptions += $obj
		}
	}

}

If($DesktopExceptions -eq $null)
	{
	$SMTPBody = "All desktops are currently using the correct snapshots."
	}
Else
	{
	$SMTPBody = $DesktopExceptions | Select-Object DisplayName,PoolName,PoolSnapshot,DesktopSVIVmSnapshot | ConvertTo-HTML
	}

Send-Email -SMTPBody $SMTPBody -SMTPTo $EmailRcpt

If($Remediate -eq $true)
{
	ForEach($Exception in $DesktopExceptions)
	{
		Set-QADObject -Identity $Exception.DesktopDN -Service $ConnectionServer -IncludedProperties "pae-vmstate" -ObjectAttributes @{"pae-vmstate"="DELETING"}
	}
	
}
