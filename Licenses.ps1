function GetLicenses {
    param (
        $packages
    )
    
    $hash = [ordered]@{ }

    foreach ($package in $packages.GetEnumerator()) {
        # $packageName = $package.Name.ToLower()
        # $packageVersion = $package.Version

        $packageName = $package.key.ToLower()
        $packageVersion = $package.value

        $nuspecFile = "$env:USERPROFILE\.nuget\packages\$packageName\$packageVersion\$packageName.nuspec"        

        if (!(Test-Path $nuspecFile)) {
            Write-Host "File not found: $nuspecFile"
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
            Write-Host "GetLicenses: ignored duplicate package: $($data.Name, $data.Version)"
        }
    }

    return $hash
}

function GetSubdependencies {
    param (
        $package
    )
    
    $dependencies = [ordered]@{ }

    $packageName = $package.Key.ToLower()
    $packageVersion = $package.Value

    $nuspecFile = "$env:USERPROFILE\.nuget\packages\$packageName\$packageVersion\$packageName.nuspec"        

    if (!(Test-Path $nuspecFile)) {
        Write-Host "File not found: $nuspecFile"
        continue
    }

    [xml]$nuspec = Get-Content $nuspecFile  
    $nuspec.package.metadata.dependencies.group.dependency | ForEach-Object {
        if ($_) {
            $dependency = "" | Select-Object "Name", "Version"
            $dependency.Name = $_.id
            $dependency.Version = $_.version.Trim('[()]')
        
            try {
                $dependencies.Add($dependency.Name, $dependency.Version)
            }
            catch {
                # Write-Host "GetSubdependencies: ignored duplicate package: $($dependency.Name, $dependency.Version)"
            }    
        }
    }

    # Get dependecies of Subdependencies
    $subDependencies = [ordered]@{ }
    if ($dependencies) {
        foreach ($dep in $dependencies.GetEnumerator()) {
            # Write-Host "$($pack.Name): $($pack.Value)"
            $subDep = GetSubdependencies $dep
            try {
                $subDependencies = $subDependencies + $subDep
            }
            catch {
                # Write-Host "ignored duplicate package: $($Name, $Version)"
            }
        }
    }

    # Remove duplicate packages in hashtables, otherwise a merge is not possible
    foreach ($dep in $dependencies.Keys) {
        if ($subDependencies.Contains($dep)) {
            $subDependencies.Remove($dep)
        }
    }
    # merging all packages in on table
    $dependencies = $dependencies + $subDependencies

    return $dependencies
}

$expr = "dotnet list"
$command = "package"
$solution = "C:\Project\WindowsSoftware\DeviceExplorer\latest\DeviceExplorer.sln"

# Get all packages form the Solution 
$packages = [ordered]@{ }
Invoke-Expression "$expr $solution $command" | 
Where-Object { $_ -match ">" } |
ForEach-Object {
    $packageInfo = $_.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)
    $Name = $packageInfo[1]
    $Version = $packageInfo[3].Trim('[()]')
    try {
        $packages.Add($Name, $Version)    
    }
    catch {
        # Write-Host "ignored duplicate package: $($Name, $Version)"
    }
    
}

$dependencies = [ordered]@{ }

foreach ($pack in $packages.GetEnumerator()) {
    # Write-Host "$($pack.Name): $($pack.Value)"
    $subDep = GetSubdependencies $pack
    try {
        $dependencies = $dependencies + $subDep
    }
    catch {
        # Write-Host "ignored duplicate package: $($Name, $Version)"
    }
}

# Remove duplicate packages in hashtables, otherwise a merge is not possible
foreach ($dep in $dependencies.Keys) {
    if ($packages.Contains($dep)) {
        $packages.Remove($dep)
    }
}
# merging all packages in on table
$packages = $packages + $dependencies

$packages = $packages.GetEnumerator() | Sort-Object -Property Name

# get licenseUrls for all packages (and subpackages) in solution
$licenses = (GetLicenses $packages)

# write licenses to file
$licenses.values | Out-File -FilePath "ThirdPartyLicenses.txt"






