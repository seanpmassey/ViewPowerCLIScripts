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
 
Param([string]$VCenter = "vCenter Server",[string]$View = "Connection Broker",[string]$ParentVM)
 
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
 
#Discover Pools Used by Base Image
$Pools = Get-Pool | Where {$_.ParentVMPath -like "*$ParentVM*"}

#Set Recompose Time - adds five minutes to allow recompose to be set on all pools, which can take a few minutes
#This ensures that all pools with the same parent VM start their recompose at the same time
$Time = ((Get-Date).AddMinutes(5))
 
ForEach($Pool in $Pools)
{
$PoolName = $Pool.Pool_ID
$ParentVMPath = $Pool.ParentVMPath
 
#Update Base Image for Pool
Update-AutomaticLinkedClonePool -pool_id $Poolname -parentVMPath $ParentVMPath -parentSnapshotPath $SnapshotPath
 
## Recompose
##Stop on Error set to false.  This will allow the pool to continue recompose operations after hours if a single vm encounters an error rather than leaving the recompose tasks in a halted state.
Get-DesktopVM -pool_id $Poolname | Send-LinkedCloneRecompose -schedule $Time -parentVMPath $ParentVMPath -parentSnapshotPath $SnapshotPath -forceLogoff:$true -stopOnError:$false
Write-EventLog –LogName Application –Source “VMware View” –EntryType Information –EventID 9000 –Message “Pool $Poolname will start to recompose at $Time using $snapshotname."
}

##Disconnect from vCenter Server after recompose operations scheduled.
Disconnect-VIServer 
