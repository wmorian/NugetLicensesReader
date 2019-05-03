param(
    [string]$Solution = 'C:\Project\WindowsSoftware\DeviceExplorer\latest\DeviceExplorer.sln', [string]$Output = '.'
)


$global:uniquePackages = [ordered]@{ }

function GetLicenses {
    param (
        $packages
    )
    
    $hash = [ordered]@{ }

    foreach ($package in $packages.GetEnumerator()) {
        $packageName = $package.key.ToLower()
        $packageVersion = $package.value

        $nuspecFile = "$env:USERPROFILE\.nuget\packages\$packageName\$packageVersion\$packageName.nuspec"        

        if (!(Test-Path $nuspecFile)) {
            # Should not happen, because missing packages are filtered already
            Write-Host "Error: File not found: $nuspecFile"
            continue
        }

        [xml]$nuspec = Get-Content $nuspecFile

        $data = "" | Select-Object "Name", "Version", "LicenseUrl"
        $data.Name = $nuspec.package.metadata.id
        $data.Version = $nuspec.package.metadata.version
        $data.LicenseUrl = $nuspec.package.metadata.licenseUrl
    
        try {
            $hash.Add($data.Name, $data) 
        }
        catch {
            # Should not happen, because there shouldn't be any duplicate packages anymore at this stage
            Write-Host "Error: ignored duplicate package: $($data.Name, $data.Version)"
        }
    }

    return $hash
}

function GetSubdependencies {
    param (
        $packageName, $packageVersion
    )

    $packageName = $packageName.ToLower()
    $nuspecFile = "$env:USERPROFILE\.nuget\packages\$packageName\$packageVersion\$packageName.nuspec"        

    if (!(Test-Path $nuspecFile)) {
        Write-Host "File not found: $nuspecFile"
        $global:uniquePackages.Remove($packageName)
        continue
    }

    [xml]$nuspec = Get-Content $nuspecFile  
    $nuspec.package.metadata.dependencies.group.dependency | ForEach-Object {
        if ($_) {
            $dependency = "" | Select-Object "Name", "Version"
            $dependency.Name = $_.id
            $dependency.Version = $_.version.Trim('[()]')
        
            if (!$global:uniquePackages.Contains($dependency.Name)) {
                $global:uniquePackages.Add($dependency.Name, $dependency.Version)

                GetSubdependencies $dependency.Name $dependency.Version
            } 
        }
    }
}

$expr = "dotnet list"
$command = "package"
$solutionPath = Resolve-Path $Solution

# Get all packages form the Solution 
$packages = [ordered]@{ }
Invoke-Expression "$expr $solutionPath $command" | 
Where-Object { $_ -match ">" } |
ForEach-Object {
    $packageInfo = $_.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)
    $Name = $packageInfo[1]
    $Version = $packageInfo[3].Trim('[()]')

    if (!$global:uniquePackages.Contains($Name)) {
        $global:uniquePackages.Add($Name, $Version)
    }
}

$keys = @($global:uniquePackages.Keys)

foreach ($key in $keys) {
    GetSubdependencies $key $global:uniquePackages[$key]
}

$packages = $global:uniquePackages.GetEnumerator() | Sort-Object -Property Name

# get licenseUrls for all packages (and subpackages) in solution
$licenses = (GetLicenses $packages)

# write licenses to file
$licenses.values | Out-File -FilePath "ThirdPartyLicenses.txt"






