<#DESCRIPTION
   Author: Sebastian Schlesinger 
   Date: 10/6/2017
			Script that contains 2 functions. 

            1.- CreateSnapshot :This will create storage snapshot on the 3PAR storage array for a volume containing a database that is mapped to the Source Server.
            THe volume will then be mounted and resignatured at the VMware level. THe VMDK on the snap volume will then be mounted on the target server. Finally the database files on the VMDK will be
            attached to the SQL instance living on the target server.

              This function will specifically:
            - Create a virtual volume copy (snapshot) on a 3 par storage array.
            - Export the volume
            - Attach volume and mount as VFMS on VMware
            - Attach and mount the disk to a source VM 
            - Attach database at SQL level
          
          
           2.- RemoveSnapshot : This will perform the removal and cleanup tasks.
           This function will specifically:
           - Drop the database at the SQL level. 
           - Will then remove the disk at the OS and VMWAre level.
           - Dismount and deattach the snapshot datastore from VMware
           - Finally the snapshot will be deleted at the SAN level  
            
            
            This example was tested with:
            -hp 3 par 7400
            -Vsphere 6.0
            -SQL 2012
            -Windows Server 2012R2
            
            Pre-requirements:
            Module installation is not covered on this document.

            -PowerCli installed.
            -HPE3PARPSToolkit (HP Powershell for 3 par). -> Available ot the PSmodules folder
            -SqlServer PS Module (Powershell for SQL administration). -> Available ot the PSmodules folder
            -Datastore Mangement Powershell module. -> Available ot the PSmodules folder
            -Adjust the ConnectVmware funtion -> Adjust variables on PSModules\ConnectVMware\ConnectVMware.psm1     
            
                 
  Usage: Populate the varaibles and then run the CreateSnapshot or RemoveSnapshot function. 
          
#>




#####################SCRIPT VARIABLES#######################################################
#Storage Variables
$SANIP = "TYPE IP" 
$SANUser = "USERNAME"
$SANPwd = "PASSWORD"
$BaseVolume = "NAME OF BASE VOLUME"
$VirtualCopyName = "NAME FOR SNAPSHOT VOLUME"
$LunNumber = "NUMBER FOR LUN"
$HostSet = "HOST SET NAME"

#SQL Variables
$TargetVM = "TARGET SERVER NAME"
$SourceVM = "SOURCE SERVER NAME"
$SetOffline = 'ALTER DATABASE ReplicationTest SET OFFLINE WITH NO_WAIT'
$SetOnline = 'ALTER DATABASE ReplicationTest SET ONLINE WITH NO_WAIT'
$SAUser = "SA USER"
$SAPwd = "SA PASSWORD"
$MountDB = 'CREATE DATABASE ReplicationTest   
    ON (FILENAME = "S:\DataBase\MDF\ReplicationTest.mdf")   
    LOG ON (FILENAME = "S:\DataBase\LDF\ReplicationTest_log.ldf")   
    FOR ATTACH;
    '
$Drop = 'USE master ;  
GO  
DROP DATABASE ReplicationTest;  
GO  '

#Windows Variables
$LocalUser = "DOMAIN NAME\USER NAME"
$LocalPWord = ConvertTo-SecureString -String 'PASSWORD' -AsPlainText -Force
$LocalCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $LocalUser, $LocalPWord


#VMware Variables
$VMWareCluster = "VMWARE CLUSTER NAME"
$VMDKName = "SOURCE DISK VMDK NAME.VMDK"
$DiskNum = "DISK NUMBER ON DISK MANAGER" #Will be used when setting the disk online at the os level (line 159). Using the disk number as a way to ID the disk. This may need to be adjusted if this is not known beforehand.


#Logging Variables
$ErrorActionPreference = "Continue"
$date = get-date -f yyyy-MM-dd-hh-mm
$outPath = "\\YOUR PATH\StorageSnapshot$date.txt" # This is the path to save the log file




##################SET SCRIPT################################################################
Function CreateSnapshot {
###Start Trnscript
Start-Transcript -path $outPath -Append

###Set base databse offline - SQL
Write-Verbose "Setting source database offline on [$SourceVM]" -Verbose
Invoke-Sqlcmd -ServerInstance $SourceVM -Query $SetOffline -Username $SAUser  -Password $SAPwd  

###Connect to 3par instance
Write-Verbose "Connecting to 3PAR [$SANIP]" -Verbose
New-3ParPoshSshConnection -SANIPAddress $SANIP -SANUserName $SANUser -SANPassword $SANPwd

###Create Virtual Copy - 3Par 
Write-Verbose "Creating Virtual Copy named [$VirtualCopyName] from [$BaseVolume]" -Verbose
New-3parSnapVolume -svName $VirtualCopyName -vvName $BaseVolume

###Mount base Database - SQL
Write-Verbose "Setting source database Online on [$SourceVM]" -Verbose
Invoke-Sqlcmd -ServerInstance $SourceVM -Query $SetOnline -Username $SAUser -Password $SAPwd

###Create Virtual Lun - 3Par 
Write-Verbose "Creating Virtual LUN [$VirtualCopyName] with number: [$LunNumber]" -Verbose
New-3parVLUN -vvName $VirtualCopyName -LUNnumber $LunNumber -PresentTo $HostSet

###Disconenct from 3Par Array
Write-Verbose "Disconnecting from 3Par" -Verbose
Close-3PARConnection

###Connect to VMware
Write-Verbose "Connecting to VMware" -Verbose
Connect-VMware

###Scan HBAs - Vmware
Write-Verbose "Rescanning all HBAs on hosts that belong to cluster: [$VMWareCluster]" -Verbose
Get-Cluster $VMWareCluster | Get-VMHost | Get-VMHostStorage -RescanAllHBA

###Find Storage Snapshot UUID - Vmware
Write-Verbose "Getting the storage snapshot UUID" -Verbose
$hosts = Get-Cluster $VMWareCluster | Get-VMHost
$esxcli = $hosts[0] | get-esxcli -V2
$Uuid = $esxcli.storage.vmfs.snapshot.list.Invoke() | Select-Object -ExpandProperty VMFSUUID


###Resignature the snapshot - VMware ESXi
Write-Verbose "Resignaturing the Snapshot datastore" -Verbose
$hosts = Get-Cluster $VMWareCluster | Get-VMHost
$esxcli = $hosts[0] | get-esxcli -V2
$arguments = $esxcli.storage.vmfs.snapshot.resignature.CreateArgs()
$arguments.volumeuuid = $Uuid
$esxcli.storage.vmfs.snapshot.resignature.Invoke($arguments)

###Refresh Storage - Vmware
Write-Verbose "Refreshing storage on hosts that belong to cluster: [$VMWareCluster]" -Verbose
Get-Cluster $VMWareCluster | Get-VMHost | Get-VMHostStorage -Refresh
Start-Sleep -Seconds 10

###Mount Disk to VM - VMware
Write-Verbose "Mounting Existing disk on [$TargetVM]" -Verbose
$VMDKLun = get-datastore snap*$VirtualCopyName | Select-Object -ExpandProperty Name
$VMDKPath = "[$VMDKLun] $SourceVM/$VMDKName"
New-HardDisk -VM $TargetVM -DiskPath $VMDKPath -Persistence persistent -Confirm:$false

###Set disk online at the OS level - VMware OS
Write-Verbose -Message "Setting snap disk Online at the OS level on [$TargetVM] " -Verbose
icm -ComputerName $TargetVM -ScriptBlock {Get-Disk | where { $_.OperationalStatus -eq "Offline" } | Set-Disk -IsOffline $false}
icm -ComputerName $TargetVM -ScriptBlock {Set-Disk -Number $DiskNum -IsReadOnly $false}
 

###Mount copy database -  Vmware SQL
Write-Verbose "Mounting DB on [$TargetVM]" -Verbose
Invoke-Sqlcmd -ServerInstance $TargetVM -Query $MountDb -Username $SAUser -Password $SAPwd

##--- Transcript Ends
Stop-Transcript
}


##################CLEAN UP SCRIPT###########################################################

Function RemoveSnapshot {

###Start Trnscript
Start-Transcript -path $outPath -Append

###Set target databse offline - SQL
Write-Verbose "Setting database offline on [$TargetVM]" -Verbose
Invoke-Sqlcmd -ServerInstance $TargetVM -Query $SetOffline -Username $SAUser -Password $SAPwd

###Delete Database on Target
Write-Verbose "Dropping database on [$TargetVM]" -Verbose
Invoke-Sqlcmd -ServerInstance $TargetVM -Query $Drop -Username $SAUser -Password $SAPwd

###Set disk offline - VMware  OS
Write-Verbose -Message "Setting snap disk Offline at the OS level on [$TargetVM] " -Verbose
icm -ComputerName $TargetVM  -ScriptBlock {get-disk -Number $DiskNum | Set-Disk -IsOffline $true}


###Remove disk from VM - VMware
$VMDKLun = get-datastore snap*$VirtualCopyName | Select-Object -ExpandProperty Name
$VMDKPath = "[$VMDKLun] $SourceVM/$VMDKName"
Write-Verbose "Removing disk from [$TargetVM]" -Verbose
Get-VM $TargetVM | Get-HardDisk | where {$_.Filename -eq "$VMDKPath"} | Remove-HardDisk -Confirm:$false

###Deattach Datastore - VMware
Write-Verbose "Umounting snapshot datastore from VMware cluster" -Verbose
Get-Datastore $VMDKLun | Get-DatastoreMountInfo | Sort Datastore, VMHost | FT –AutoSize

do
{
$Test = (Get-Datastore $VMDKLun | Get-DatastoreMountInfo | Select-Object -ExpandProperty "Mounted")
Get-Datastore $VMDKLun | Unmount-Datastore 
} until ($test -eq "false")

do
{
$Test = (Get-Datastore $VMDKLun | Get-DatastoreMountInfo | Select-Object -ExpandProperty "Mounted")
Get-Datastore $VMDKLun | Unmount-Datastore 
} until ($test -eq "false")




Get-Datastore $VMDKLun | Get-DatastoreMountInfo | Sort Datastore, VMHost | FT –AutoSize
Write-Verbose "Deattaching snapshot datastore from cluster: [$VMWareCluster]"
Get-Datastore $VMDKLun | Detach-Datastore
Get-Datastore $VMDKLun | Get-DatastoreMountInfo | Sort Datastore, VMHost | FT –AutoSize
Write-Verbose "Rescanning HBAs on the cluster: [$VMWareCluster]" -Verbose
Get-Cluster $VMWareCluster | Get-VMHost | Get-VMHostStorage -RescanAllHBA


###Disconnect From Vcenter
Write-Verbose "Disconnecting from Vcenter" -Verbose
Disconnect-VIServer -Confirm:$false

###Connect 3Par
Write-Verbose "Connecting to 3 Par" -Verbose
New-3ParPoshSshConnection -SANIPAddress $SANIP -SANUserName $SANUser -SANPassword $SANPwd

###15 Remove Virtual LUN - 3PAR 
Write-Verbose "Removing the 3PAR Vlun: [$VirtualCopyName]" -Verbose
Get-3parVLUN $VirtualCopyName
Remove-3parVLUN -vvName $VirtualCopyName -force

###16 Remove Virtual Copy - 3PAR 
Write-Verbose "Removing Virtual Volume: [$VirtualCopyName]" -Verbose
Remove-3parVV -vvName $VirtualCopyName -Snaponly -force

###Disconenct from 3Par Array
Write-Verbose "Disconnecting from 3 PAR" -Verbose
Close-3PARConnection

##--- Transcript Ends
Stop-Transcript
}


 

