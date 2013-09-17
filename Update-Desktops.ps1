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

Param([string]$VCServer = "applvc01",[string]$Folder = "VDI Templates",$ParentVM,$SnapshotType = "Windows Updates")

add-pssnapin VMware.VimAutomation.Core

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
	Start-VM -VM $vm | Wait-Tools -Timeoutseconds 300
	Invoke-VMScript -VM $vm -ScriptText "C:\Scripts\PSWindowsUpdate\Get-WUInstall -AcceptAll -Verbose" -GuestUser gbcdnt\Administrator -GuestPassword drar8ZAF
	
	Restart-VMGuest $vm
	
	Start-Sleep -Seconds 30
	
	Wait-Tools -VM $vm -TimeoutSeconds 300 | Shutdown-VMGuest
	
	New-Snapshot -VM $vm -Name $snapshotname
	}
