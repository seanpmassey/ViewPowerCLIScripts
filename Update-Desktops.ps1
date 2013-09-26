<#
.SYNOPSIS
   Update-Desktops is a zero-touch method for installing Windows Updates on a VMware View Parent VM.
.DESCRIPTION
   This script utilizes the Windows Update Powershell Module (http://gallery.technet.microsoft.com/scriptcenter/2d191bcd-3308-4edd-9de2-88dff796b0bc)to install Windows Updates and other software deployed through WSUS to ParentVMs.  In order to use this script, the WSUS module will need to be installed on each VM, and the VMware VIX tools will need to be available in PowerCLI.
   This module must be run in a 32-bit PowerShell session as VIX is not 64-bit compatible as of vSphere 5.1.
.PARAMETER vCServer
   vCenter Server
.PARAMETER Folder
   vCenter Folder where templates are located
.PARAMETER ParentVM
   Name of a specific ParentVM that you want to update
.PARAMETER SnapshotType
   Type of updates that are being installed. This is used for building the snapshot name string.  Defaults to Windows Updates
.PARAMETER Administrator
   Account with local adminsitrator privileges on the ParentVM.  If using a domain account, use the domain\username format for account names
.PARAMETER Password
   Password of the local adminsitrator account.
.EXAMPLE
   Update-Desktops -vCServer vc1.domain.com -Folder "VDI Templates" -SnapshotType "Java Update" -Administrator domain\admin $Password 12345
.EXAMPLE
   Update-Desktops -vCServer vc1.domain.com -ParentVM Windows8VDI -SnapshotType "Java Update" -Administrator domain\admin $Password 12345

#>
Param([string]$VCServer = "vCenter",[string]$Folder = "Template Folder",$ParentVM,$SnapshotType = "Windows Updates",$Administrator,$Password)

add-pssnapin VMware.VimAutomation.Core


Function Get-VMwareToolsStatus
{
	Param($VM)
	$toolstatus = (Get-VM $vm | % { get-view $_.ID } | Select-Object @{ Name="ToolsStatus"; Expression={$_.guest.toolsstatus}}).ToolsStatus
	
	return $toolstatus
}

Connect-VIServer -Server $VCServer

#Build Snapshot Name String
$Month = Get-Date -Format MMMM
$Date = Get-Date -Format "M-dd-yyyy"
$snapshotname = "$Month $SnapshotType $Date"


If($ParentVM -eq $null)
{
$vms = get-vm -location $Folder
}
Else
{
$vms = $ParentVM
}

ForEach($vm in $vms)
	{
	Start-VM -VM $vm | Wait-Tools -TimeoutSeconds 300
	
	Invoke-VMScript -VM $vm -ScriptText "C:\Scripts\PSWindowsUpdate\Get-WindowsUpdates.ps1" -GuestUser $Administrator -GuestPassword $Password
	
	Restart-VMGuest $vm
	
	Do 
	{$RebootToolStatus = Get-VMwareToolsStatus -VM $vm}
	Until ($RebootToolStatus -ne "toolsOK")
	$RebootToolStatus = $null
	
	Start-Sleep -Seconds 5
		
	Do 
	{$RebootToolStatus = Get-VMwareToolsStatus -VM $vm}
	Until ($RebootToolStatus -eq "toolsOK")

	Shutdown-VMGuest -VM $vm -Confirm:$false
	
	Do
	{$VMPowerStatus = (Get-VM $vm).PowerState}
	Until ($VMPowerStatus -eq "PoweredOff")
	
	New-Snapshot -VM $vm -Name $snapshotname
	}
	
Disconnect-VIServer -Confirm:$false
