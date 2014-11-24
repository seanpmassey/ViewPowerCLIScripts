<#
.SYNOPSIS
   Start-Recompose is a script to schedule a recompose action for all VMware View Pools that use a specific Parent VM.
.DESCRIPTION
   The script locates all View Desktop Pools that use a certain Parent VM and schedules a recompose action using 
.PARAMETER vCenter
   DNS name of vCenter server in your environment where the ParentVM is located. This parameter is mandatory.
.PARAMETER ConnectionServer
   DNS name of a connection broker in your environment.  This parameter is mandatory.
.PARAMETER ParentVM
   The name of the ParentVM.  This should be the name of the VM as it appears in the vCenter inventory.  This parameter is mandatory.
.PARAMETER Poolname
   The name of the Horizon View Desktop Pool to be recomposed.  This value should match the Horizon View Pool's Unique ID in View Administrator.  This value is optional, and if a pool name is not entered, all pools that utilize the parent VM will be recomposed.
.EXAMPLE
   Start-Recompose.ps1 -vCenter vcenter.domain.com -View view.domain.com -ParentVM Win7-Base
.EXAMPLE
   Start-Recompose.ps1 -vCenter vcenter.domain.com -View view.domain.com -ParentVM Win7-Base -Poolname Win7-Pool1
#>

### Must be run from the View Connection Server ###

### Based on http://gregcarriger.wordpress.com/2011/06/08/powershell-powercli-snapshot-and-recompose-script/

Param([Parameter(Mandatory=$true)][string]$VCenter,[Parameter(Mandatory=$true)][string]$ConnectionServer,[Parameter(Mandatory=$true)][string]$ParentVM,[string]$Poolname,$SMTPServer)

Function Send-Email
{
 Param([string]$SMTPBody,[string]$SMTPSubject = "Recompose Operation Cancelled",[string]$SMTPTo,$SMTPServer)
Send-MailMessage -To $SMTPTo -Body $SMTPBody -Subject $SMTPSubject -SmtpServer $SMTPServer -From "Notifications_noreply@gbdioc.org" -BodyAsHtml -Priority High
}

Function Build-SnapshotPath
{
Param($ParentVM)
## Create Snapshot Path
$Snapshots = Get-Snapshot -VM $ParentVM

$SnapshotPath = ""
$PreviousSnapshot = $Null
ForEach($Snapshot in $Snapshots)
{
	$SnapshotName = $Snapshot.name
	
	If($Snapshot.ParentSnapshot.Name -eq $null)
	{
	$SnapshotPath = $SnapshotPath + "/"+$snapshotname
	$PreviousSnapshot = $SnapshotName
	}
	ElseIf($Snapshot.ParentSnapshot.Name -eq $PreviousSnapshot)
	{
	$SnapshotPath = $SnapshotPath + "/"+$snapshotname
	$PreviousSnapshot = $SnapshotName
	}
	
}

Return $snapshotpath
}

Function Get-Pools
{
param($ConnectionServer,[switch]$Remediate,$EmailRcpt,$ParentVM="")

$PoolList = @()

#based on http://www.thescriptlibrary.com/Default.asp?Action=Display&Level=Category3&ScriptLanguage=Powershell&Category1=Active%20Directory&Category2=User%20Accounts&Title=Scripting%20Ldap%20Searches%20using%20PowerShell
$LDAPDom = "LDAP://$connectionserver`:389/OU=Server Groups,dc=vdi,dc=vmware,dc=int"
$root = New-Object System.DirectoryServices.DirectoryEntry $LDAPDom
$query = new-Object System.DirectoryServices.DirectorySearcher
$query.searchroot = $root
$query.Filter = "(&(objectClass=pae-ServerPool)(pae-SVIVmParentVM=*$ParentVM))"
$result = $query.findall()

$pools = $result.getdirectoryentry()

ForEach($pool in $pools)
{
	$attributes = $pool.properties
	
	$obj = New-Object PSObject -Property @{
		"cn" = $attributes.cn
		"name" = $attributes.name
		"DisplayName" = $attributes."pae-DisplayName"
		"MemberDN" = $attributes."pae-MemberDN"
		"SVIVmParentVM" = $attributes."pae-SVIVmParentVM"
		"SVIVmSnapshot" = $attributes."pae-SVIVmSnapshot"
		"SVIVmSnapshotMOID" = $attributes."pae-SVIVmSnapshotMOID"
		"SVIVmDatastore" = $attributes."pae-SVIVmDatastore"
	}
	$PoolList += $obj
}
Return $PoolList
}

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

Try
{

#Enable Line for Debugging Only
#Write-Host $strSnapshotPath -ForegroundColor Yellow
$snapshotpath = Build-SnapshotPath -ParentVM $ParentVM
Write-EventLog –LogName Application –Source “VMware View” –EntryType Information –EventID 9000 –Message "Pools based on $ParentVM will use $SnapshotPath when the recompose is complete."

#Discover Pools Used by Base Image if Pool Name not provided

If($poolname -eq $null)
{
	$Pools = Get-Pools -ConnectionServer $ConnectionServer | Where {$_.ParentVMPath -like "*$ParentVM*"}
}
Else
{
	$pools = Get-Pools -ConnectionServer $ConnectionServer | Where {$_.name -like "*$poolname*"}
}

#Set Recompose Time - adds five minutes to allow recompose to be set on all pools, which can take a few minutes
#This ensures that all pools with the same parent VM start their recompose at the same time
$Time = ((Get-Date).AddMinutes(15))

ForEach($Pool in $Pools)
{
	$PoolName = $Pool.name
	$ParentVMPath = [string]$Pool.SVIVmParentVM
	$Datastores = $pool.SVIVmDatastore
	
	ForEach($Datastore in $Datastores)
	{
		Write-Host $Datastore
		If($Datastore.Contains("type=replica"))
		{
			$DatastoreLines = $Datastore.split(";")
			ForEach($DatastoreLine in $DatastoreLines)
			{
				If($DatastoreLine.Contains("path="))
				{
					$ReplicaDataStoreElements = $DatastoreLine.trimstart("path=")
					$ReplicaDataStoreElements = $ReplicaDatastoreElements.split("/")
					$ReplicaDatastore = $ReplicaDataStoreElements[4]
				}
			}
		}
	}

	#Check Replica Disk for Space
	$freespace = (Get-Datastore -Name $ReplicaDatastore).FreeSpaceGB

	#Get space used by ParentVM
	$usedspace = (get-vm -Name $ParentVM).UsedSpaceGB

	If($usedspace -lt $freespace)
	{
		#Update Base Image for Pool
		Update-AutomaticLinkedClonePool -pool_id $Poolname -parentVMPath $ParentVMPath -parentSnapshotPath "$SnapshotPath"

		## Recompose
		##Stop on Error set to false.  This will allow the pool to continue recompose operations after hours if a single vm encounters an error rather than leaving the recompose tasks in a halted state.
		Get-DesktopVM -pool_id $Poolname | Send-LinkedCloneRecompose -schedule $Time -parentVMPath $ParentVMPath -parentSnapshotPath $SnapshotPath -forceLogoff:$true -stopOnError:$false
		Write-EventLog –LogName Application –Source “VMware View” –EntryType Information –EventID 9000 –Message "Pool $Poolname will start to recompose at $Time using $snapshotpath."
	}
	Else
	{
		#$SMTPTo = "Email Address"
		#$SMTPSubject = "Recompose operations for pool $Poolname have been cancelled:  Insufficient Space."
		#$SMTPBody = "The Recompose operation for desktop pool $Poolname has been cancelled.  There is not enough space available on $ReplicaDatastore to successfully complete cloning operations.  Please verify that there are no other cloning operations being conducted and that all recompose operations have completed successfully before rescheduling this job."
		#Send-Email -SMTPBody $SMTPBody -SMTPTo $SMTPTo -SMTPSubject $SMTPSubject
		Write-EventLog –LogName Application –Source “VMware View” –EntryType Error –EventID 9000 –Message "There is not enough space availabe on $ReplicaDatastore to recompose pool $Poolname.  This recompose job has been cancelled."
	}

}

}
Finally
{
##Disconnect from vCenter Server after recompose operations scheduled.
Disconnect-VIServer -Confirm:$false
}