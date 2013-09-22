<#
.SYNOPSIS
   Start-Recompose is a script to schedule a recompose action for all VMware View Pools that use a specific Parent VM.
.DESCRIPTION
   The script locates all View Desktop Pools that use a certain Parent VM and schedules a recompose action using 
.PARAMETER vCenter
   DNS name of vCenter server in your environment where the ParentVM is located.  
.PARAMETER View
   DNS name of a connection broker in your environment.
.PARAMETER ParentVM
   The name of the ParentVM.  This should be the name of the VM as it appears in the vCenter inventory.
.EXAMPLE
   Start-Recompose.ps1 -vCenter vcenter.domain.com -View view.domain.com -ParentVM Win7-Base
#>
 
### Must be run from the View Connection Server ###
 
### Based on http://gregcarriger.wordpress.com/2011/06/08/powershell-powercli-snapshot-and-recompose-script/

Function Send-Email
{
 Param([string]$SMTPBody,[string]$SMTPSubject = "Recompose Operation Cancelled",[string]$SMTPTo)
Send-MailMessage -To $SMTPTo -Body $SMTPBody -Subject $SMTPSubject -SmtpServer smtp.gbdioc.org -From "Notifications_noreply@gbdioc.org" -BodyAsHtml -Priority High
}

Function Build-SnapshotPath
{
Param($ParentVM)
## Create Snapshot Path
$Snapshots = Get-Snapshot -VM $ParentVM
 
$SnapshotPath = ""
ForEach($Snapshot in $Snapshots)
{
$SnapshotName = $Snapshot.name
$SnapshotPath = $SnapshotPath+"/"+$snapshotname
}

Return $snapshotpath
}

Function Get-Pools
{
param($ConnectionServer,[switch]$Remediate,$EmailRcpt,$ParentVM="")

$PoolList = @()

$arrIncludedProperties = "cn,name,pae-DisplayName,pae-MemberDN,pae-SVIVmParentVM,pae-SVIVmSnapshot,pae-SVIVmSnapshotMOID,pae-SVIVmDatastore".Split(",")
$pools = Get-QADObject -Service applvcs03.gbcdnt.com -DontUseDefaultIncludedProperties -IncludedProperties $arrIncludedProperties -LdapFilter "(&(objectClass=pae-ServerPool)(pae-SVIVmParentVM=*$ParentVM))" | Sort-Object "pae-DisplayName" | Select-Object Name, "pae-DisplayName", "pae-SVIVmParentVM" , "pae-SVIVmSnapshot", "pae-SVIVmSnapshotMOID", "pae-MemberDN", @{Name="pae-SVIVmDatastore";expression={$_."pae-SVIVmDatastore" -match "replica"}}

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
		   "SVIVmDatastore" = $pool."pae-SVIVmDatastore"
		  }
$PoolList += $obj
}
Return $PoolList
}

Param([string]$VCenter = "vCenter Server",[string]$View = "Connection Broker",[string]$ParentVM,[string]$Poolname)
 
#Load Modules
if (!(get-pssnapin -name VMware.VimAutomation.Core -erroraction silentlycontinue)) 
	{
    add-pssnapin VMware.VimAutomation.Core
	}
 
if (!(get-pssnapin -name VMware.View.Broker -erroraction silentlycontinue)) 
	{
    add-pssnapin VMware.View.Broker
	}
 
 
## Connect to vCenter
Connect-VIServer –Server $VCenter –Protocol https


#Enable Line for Debugging Only
#Write-Host $strSnapshotPath -ForegroundColor Yellow
$snapshotpath = Build-SnapshotPath -ParentVM $ParentVM
Write-EventLog –LogName Application –Source “VMware View” –EntryType Information –EventID 9000 –Message “Pools based on $ParentVM will use $SnapshotName when the recompose is complete."
 
#Discover Pools Used by Base Image if Pool Name not provided
If($poolname -eq $null)
{
$Pools = Get-Pools | Where {$_.ParentVMPath -like "*$ParentVM*"}
}
Else
{
$pools = $poolname
}

#Set Recompose Time - adds five minutes to allow recompose to be set on all pools, which can take a few minutes
#This ensures that all pools with the same parent VM start their recompose at the same time
$Time = ((Get-Date).AddMinutes(5))
 
ForEach($Pool in $Pools)
{
$PoolName = $Pool.name
$ParentVMPath = $Pool.ParentVMPath
$ReplicaDatastore = $pool.SVIVmDatastore

#Check Replica Disk for Space
$ReplicaDatastore = ($pool.SVIVmDatastore).trimstart("path/")
$ReplicaDatastore = $ReplicaDatastore -replace ";,+",""
$freespace = (Get-Datastore -Name $ReplicaDatastore).FreeSpaceGB

#Get space used by ParentVM
$usedspace = (get-vm -Name $ParentVM).UsedSpaceGB

If($usedspace -lt $freespace)
{
#Update Base Image for Pool
Update-AutomaticLinkedClonePool -pool_id $Poolname -parentVMPath $ParentVMPath -parentSnapshotPath $SnapshotPath
 
## Recompose
##Stop on Error set to false.  This will allow the pool to continue recompose operations after hours if a single vm encounters an error rather than leaving the recompose tasks in a halted state.
Get-DesktopVM -pool_id $Poolname | Send-LinkedCloneRecompose -schedule $Time -parentVMPath $ParentVMPath -parentSnapshotPath $SnapshotPath -forceLogoff:$true -stopOnError:$false
Write-EventLog –LogName Application –Source “VMware View” –EntryType Information –EventID 9000 –Message “Pool $Poolname will start to recompose at $Time using $snapshotname."
}
Else
{
$SMTPTo = "smassey@gbdioc.org"
$SMTPSubject = "Recompose operations for pool $Poolname have been cancelled:  Insufficient Space."
$SMTPBody = "The Recompose operation for desktop pool $Poolname has been cancelled.  There is not enough space available on $ReplicaDatastore to successfully complete cloning operations.  Please verify that there are no other cloning operations being conducted and that all recompose operations have completed successfully before rescheduling this job."
Write-EventLog –LogName Application –Source “VMware View” –EntryType Error –EventID 9000 –Message "There is not enough space availabe on $ReplicaDatastore to recompose pool $Poolname.  This recompose job has been cancelled."
}

}

##Disconnect from vCenter Server after recompose operations scheduled.
Disconnect-VIServer 
