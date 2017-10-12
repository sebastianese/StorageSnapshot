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
            -SQL 2012 and 2016
            -Windows Server 2012R2
            
            Pre-requirements:
            Module installation is not covered on this document.

            -PowerCli installed.
            -HPE3PARPSToolkit (HP Powershell for 3 par). -> Available ot the PSmodules folder
            -SqlServer PS Module (Powershell for SQL administration). -> Available ot the PSmodules folder
            -Datastore Mangement Powershell module. -> Available ot the PSmodules folder
            -Adjust the ConnectVmware funtion -> Adjust variables on PSModules\ConnectVMware\ConnectVMware.psm1     
            
                 
  Usage: Populate the varaibles and then run the CreateSnapshot or RemoveSnapshot function. 