<#
.SYNOPSIS
   <A brief description of the script>
.DESCRIPTION
   <A detailed description of the script>
.PARAMETER <paramName>
   <Description of script parameter>
.EXAMPLE
   <An example of using the script>
#>

Function Send-Email
{
 Param([string]$SMTPBody,[string]$SMTPSubject = "View Snapshot Compliance Report",[string]$SMTPTo)
Send-MailMessage -To $SMTPTo -Body $SMTPBody -Subject $SMTPSubject -SmtpServer smtp.gbdioc.org -From "Notifications_noreply@gbdioc.org" -BodyAsHtml
}


Function Get-Pools
{
param($ConnectionServer,[switch]$Remediate,$EmailRcpt)

$PoolList = @()

$arrIncludedProperties = "cn,name,pae-DisplayName,pae-MemberDN,pae-SVIVmParentVM,pae-SVIVmSnapshot,pae-SVIVmSnapshotMOID".Split(",")
$pools = Get-QADObject -Service applvcs03.gbcdnt.com -DontUseDefaultIncludedProperties -IncludedProperties $arrIncludedProperties -LdapFilter "(objectClass=pae-ServerPool)" -SizeLimit 0 | Sort-Object "pae-DisplayName" | Select-Object Name, "pae-DisplayName", "pae-SVIVmParentVM" , "pae-SVIVmSnapshot", "pae-SVIVmSnapshotMOID", "pae-MemberDN"

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
param($MemberDN, $PoolSnapshotMOID)

$arrIncludedProperties = "cn,name,pae-DisplayName,pae-MemberDN,pae-SVIVmSnapshot,pae-VmState".Split(",")
$Desktop = Get-QADObject -Service applvcs03.gbcdnt.com -DontUseDefaultIncludedProperties -IncludedProperties $arrIncludedProperties -LdapFilter "(&(objectClass=pae-Server)(distinguishedName=$MemberDN))" -SizeLimit 0 | Sort-Object "pae-DisplayName" | Select-Object Name, "pae-DisplayName", "pae-SVIVmParentVM" , "pae-SVIVmSnapshot", "pae-SVIVmSnapshotMOID"

Return $Desktop
}


$DesktopExceptions = @()
$pools = Get-Pools

ForEach($pool in $pools)
{
$MemberDNs = $pool.memberdn
	ForEach($MemberDN in $MemberDNs)
	{
	$Desktop = Get-Desktop -MemberDN $MemberDN
	
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

Send-Email -SMTPBody $SMTPBody -SMTPTo "smassey@gbdioc.org"

If($Remediate -eq $true)
{
	ForEach($Exception in $DesktopExceptions)
	{
		Set-QADObject -Identity $Exception.DesktopDN -Service applvcs03.gbcdnt.com -IncludedProperties "pae-vmstate" -ObjectAttributes @{"pae-vmstate"="DELETING"}
	}
	
}
