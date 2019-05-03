param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Solution,
    [string]$Output
)

if (!(Test-Path $Solution)) {
    Write-Error "Invalid path: $Solution"
    Exit
}

$solutionPath = Resolve-Path $Solution  
if (-Not [System.IO.Path]::GetExtension($solutionPath) -eq ".sln") {
    Write-Error "Please provide the full path of the solution"
    Exit
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
        Write-Host "File not found and will be ignored: $nuspecFile"
        $uniquePackages.Remove($packageName)
        continue
    }

    [xml]$nuspec = Get-Content $nuspecFile  
    $nuspec.package.metadata.dependencies.group.dependency | ForEach-Object {
        if ($_) {
            $dependency = "" | Select-Object "Name", "Version"
            $dependency.Name = $_.id
            $dependency.Version = $_.version.Trim('[()]')
        
            # Doesn't distinguish between same packages with different version numbers, the key should be a KeyValue with name and version
            if (!$uniquePackages.Contains($dependency.GetHashCode())) {
                $uniquePackages.Add($dependency.GetHashCode(), $dependency)
                GetSubdependencies $dependency.Name $dependency.Version
            } 
        }
    }
}

$expr = "dotnet list"
$command = "package"
$uniquePackages = [ordered]@{ }


# Get all packages form the Solution 
$packages = [ordered]@{ }
Invoke-Expression "$expr $solutionPath $command" | 
Where-Object { $_ -match ">" } |
ForEach-Object {
    $packageInfo = $_.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)
    # $Name = $packageInfo[1]
    # $Version = $packageInfo[3].Trim('[()]')

    $dependency = "" | Select-Object "Name", "Version"
    $dependency.Name = $packageInfo[1]
    $dependency.Version = $packageInfo[3].Trim('[()]')

    if (!$uniquePackages.Contains($dependency.GetHashCode())) {
        $uniquePackages.Add($dependency.GetHashCode(), $dependency)
    }
}

# For Logging later
$count = $uniquePackages.Count

# copy the keys in an array, otherwise exception will be thrown during the iteration, because hashtable changes in the loop
$keys = @($uniquePackages.Keys)

foreach ($key in $keys) {
    $dependency = $uniquePackages[$key]
    GetSubdependencies $dependency.Name $dependency.Version
}

# Logging
Write-Host "Direct dependencies found: $count"
Write-Host "Subdependencies found: $($uniquePackages.Count - $count)"

$packages = $uniquePackages.Values | Sort-Object -Property Name

# get licenseUrls for all packages (and subpackages) in solution
$licenses = (GetLicenses $packages)

if ($Output -eq "") {
    $outputPath = [System.IO.Path]::GetDirectoryName($solutionPath)
}
else {
    $outputPath = Resolve-Path $Output
}

# write licenses to file
$licenses.values | Out-File -FilePath "$outputPath\ThirdPartyLicenses.txt"






