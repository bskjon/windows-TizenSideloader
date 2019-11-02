$sdbIsPresent = $false
$tizenIsPresent = $false
$sdb = $null
$tizen = $null
$package = $null


$targetPattern = '^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5]):[0-9]+'




function getInstallPackage()
{
    Write-Host "Supported packages is .wgt & .tpk"
    $inputPackage = Read-Host "Write or insert Tizen Package for install"
    $item = Get-Item -Path $inputPackage -ErrorAction Ignore
    if ($null -eq $item)
    {
        Clear-Host
        Write-Host "File does not exist" -ForegroundColor Red
        getInstallPackage
    }
    else {
        $script:package = $item.FullName
    }
    
}

if ($null -eq $package)
{
    getInstallPackage
}








$ContentObj = @"
public class Device
{
    public string Ip {get; set;}
    public string Port {get; set;}
    public string State {get; set;}
    public string Name {get; set;}

    public Device(string name, string ip, string port, string state)
    {
        this.Name = name;
        this.Ip = ip;
        this.Port = port;
        this.State = state;
    }

}
"@

Add-Type -TypeDefinition $ContentObj -ErrorAction SilentlyContinue;

$files = Get-ChildItem -Recurse -Path $pwd
#Write-Host $files;

foreach ($file in $files)
{
    if ($file.Name -match "sdb.exe")
    {
        $sdbIsPresent = $true;
        $sdb = $file.FullName
        continue
    }
    if ($file.Name -match "tizen.bat")
    {
        $tizenIsPresent = $true;
        $tizen = $file.FullName
        continue
    }
}

if ($sdbIsPresent -ne $true -or $tizenIsPresent -ne $true)
{
    Write-Host "Could not find sdb.exe or tizen.bat" -ForegroundColor Red;
    exit
}

$sdbConnectedDevices = @()


$potentialDevices = Get-NetNeighbor -AddressFamily IPv4 -State Reachable
foreach ($device in $potentialDevices)
{
    $ct = Invoke-Expression $($sdb + " connect " + $device.IPAddress);
    Write-Host "Returned -> " $ct -ForegroundColor Yellow
    if ($ct.Count -gt 1 -and $ct -ne $null)
    {
        for ($i = 0; $i -le $ct.Count; $i++)
        {
            if ($ct[$i].ToLower() -match "connected")
            {
                $sdbConnectedDevices += $device.IPAddress
            }
        }
    }
    else {
        if ($ct.ToLower() -match "connected")
        {
            $sdbConnectedDevices += $device.IPAddress
        }
    }
}


function manualIpInput()
{
    Write-Host "No Device could be found" -ForegroundColor Yellow
    Write-Host "Do you want to manually input the ip?" -ForegroundColor Yellow
    $czOption = Read-Host "Y/N"
    if ([regex]::Match($czOption, "[nN]").Success -eq $false)
    {
        # Wants to input
        $ip = Read-Host "IPv4 Address"

        $ct = Invoke-Expression $($sdb + " connect " + $ip);
        Write-Host "Returned -> " $ct -ForegroundColor Yellow
        if ($ct.Count -gt 1)
        {
            for ($i = 0; $i -le $ct.Count; $i++)
            {
                if ($ct[$i].ToLower() -match "connected")
                {
                    $sdbConnectedDevices += $device.IPAddress
                }
            }
        }
        else {
            if ($ct.ToLower() -match "connected")
            {
                $sdbConnectedDevices += $device.IPAddress
            }
        }
        
    }
    else {
        exit
    }
}

if ($sdbConnectedDevices.Count -eq 0)
{
    manualIpInput
}

<#
    Gets the targets with data
#>
$targets = New-Object System.Collections.ArrayList

$sdbDeviceList = Invoke-Expression $($sdb + " devices")

foreach ($fdl in $sdbDeviceList)
{
    if ($fdl -match $targetPattern)
    {
        $ipnport = $fdl.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)[0].Trim()
        $state = $fdl.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)[1].Trim()
        $name = $fdl.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)[2].Trim()

        $onlyIp = $ipnport.Substring(0, $ipnport.IndexOf(":"))
        $onlyPort = $ipnport.Substring($ipnport.IndexOf(":")+1)

        foreach ($sdbConnected in $sdbConnectedDevices)
        {
            
            if ($onlyIp -eq $sdbConnected)
            {
                ## Add to array
                $deviceItem = New-Object Device($name, $onlyIp, $onlyPort, $state)
                $targets.Add($deviceItem) | Out-Null
            }
            else 
            {
                Write-Host $onlyIp " does not match " $sdbConnected -ForegroundColor Red    
            }
        }
    }
    else {
        Write-Host "Non match for -> " $fdl -ForegroundColor Red
    }    


}

if ($targets.Count -eq 0)
{
    Write-Host "No Capable devices found" -ForegroundColor Yellow
    Write-Host "Please ensure that the device is powered on (it might take a while for it to be detected)" -ForegroundColor Yellow
    exit
}

Write-Host "Proceeding to Install on " $targets.Count " device(s)" -ForegroundColor Yellow
function installOnTizen()
{
    foreach ($device in $targets)
    {
        Write-Host $($tizen + " install -t " + $device.Name + " -n " + $package) -ForegroundColor Magenta
        Write-Host "Please Wait..." -ForegroundColor Cyan
        $response = Invoke-Expression $($tizen + " install -t " + $device.Name + " -n " + $package)
        $isSuccess = $false
        for($i = 0; $i -lt $response.Count; $i++)
        {
            if ($response[$i] -match "Tizen application is successfully installed")
            {
                $isSuccess = $true
            }
        }

        if ($isSuccess)
        {
            Write-Host "Sideload was successfull" -ForegroundColor Green
        }
        else {
            Write-Host "Sideload failed" -ForegroundColor Red
            Write-Host "Dumping output now" -ForegroundColor Yellow
            Write-Output $response
        }

    }
}

installOnTizen


<#
$Content = New-Object Content( $item.BaseName, $item.FullName)
#>
#Get-ChildItem -Recurse -Path $pwd