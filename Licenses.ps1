$global:uniquePackages = [ordered]@{}

function MergeHashTables {
    param (
        $table1, $table2
    )

    #!!!!!!!!!!! Changing the order of tables changes the result !!!!!!!!!!!!!!!
    # Remove duplicate keys in hashtables, otherwise a merge is not possible
    foreach ($key in $table1.Keys) {
        if ($table2.Contains($key)) {
            $table2.Remove($key)
        }
    }

    # merging all entries in on table
    $table2 = $table2 + $table1

    return $table2
}

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
        $packageName, $packageVersion
    )
    
    $dependencies = [ordered]@{ }
    $packageName = $packageName.ToLower()
    $nuspecFile = "$env:USERPROFILE\.nuget\packages\$packageName\$packageVersion\$packageName.nuspec"        

    if (!(Test-Path $nuspecFile)) {
        Write-Host "GETSUB: File not found: $nuspecFile"
        continue
    }

    [xml]$nuspec = Get-Content $nuspecFile  
    $nuspec.package.metadata.dependencies.group.dependency | ForEach-Object {
        if ($_) {
            $dependency = "" | Select-Object "Name", "Version"
            $dependency.Name = $_.id
            $dependency.Version = $_.version.Trim('[()]')
        
            if (!$dependencies.Contains($dependency.Name)) {
                $dependencies.Add($dependency.Name, $dependency.Version)
            }

            # try {
            #     $dependencies.Add($dependency.Name, $dependency.Version)
            # }
            # catch {
            #     Write-Host "GetSubdependencies: ignored duplicate package: $($dependency.Name, $dependency.Version)"
            # }    
        }
    }

    if ($dependencies.Count -gt 0) {
        $keys = $dependencies.Keys

        foreach ($key in $keys) {
            $subDep = GetSubdependencies $key $dependencies[$key]

            $dependencies = MergeHashTables $dependencies $subDep
        }
    }

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
        Write-Host "ignored duplicate package: $($Name, $Version)"
    }
    
}

$dependencies = [ordered]@{ }

foreach ($pack in $packages.GetEnumerator()) {
    $subDep = GetSubdependencies $pack.Name $pack.Value

    $dependencies = MergeHashTables $dependencies $subDep
}

$packages = MergeHashTables $dependencies $packages 
$packages = $packages.GetEnumerator() | Sort-Object -Property Name

# get licenseUrls for all packages (and subpackages) in solution
$licenses = (GetLicenses $packages)

# write licenses to file
$licenses.values | Out-File -FilePath "ThirdPartyLicenses.txt"






