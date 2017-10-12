
function Connect-VMware {
##This section contains the commands to connect to Vcenter Edit according to your enviroment---
.'C:\Program Files (x86)\VMware\Infrastructure\PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1'
# ------vSphere Targeting Variables tracked below------
$vCenterInstance = "VCENTER NAME OR IP"
$vCenterUser = "USER NAME"
$vCenterPass = "PASSWORD"
# This section logs on to the defined vCenter instance above
Connect-VIServer $vCenterInstance -User $vCenterUser -Password $vCenterPass -WarningAction SilentlyContinue
}