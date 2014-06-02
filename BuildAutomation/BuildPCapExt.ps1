$ErrorActionPreference = "Stop"

$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
. "$scriptPath\BuildUtils.ps1"

$ENV:PATH += ";$ENV:ProgramFiles\7-Zip"
$ENV:PATH += ";${ENV:ProgramFiles(x86)}\Git\bin"
$ENV:PATH += ";C:\Tools\AlexFTPS-1.1.0"

$vsVersion = "12.0"
SetVCVars $vsVersion

$basePath = "C:\OpenStack\build\PCapExt"
$buildDir = "$basePath\Build"
$outputPath = "$buildDir\PCapExt"

# Needed for SSH
$ENV:HOME = $ENV:USERPROFILE

$sign_cert_thumbprint = "65c29b06eb665ce202676332e8129ac48d613c61"
$ftpsCredentials = GetCredentialsFromFile "$ENV:UserProfile\ftps.txt"

CheckDir $basePath
pushd .
try
{
    CheckRemoveDir $buildDir
    mkdir $buildDir
    cd $buildDir
    mkdir $outputPath

    $pcapExtDir = "HyperVPCapExt"

    ExecRetry {
        GitClonePull $pcapExtDir "https://github.com/cloudbase/HyperVPCapExt.git"
    }

    $sysFileName = "PCapExt.sys"
    $infFileName = "PCapExt.inf"
    $catFileName = "PCapExt.cat"

    pushd .
    try
    {
        cd $pcapExtDir
        $buildConfig = "Win8.1 Release"

        &msbuild  HyperVPCapExt.sln /p:Configuration="$buildConfig"
        if ($LastExitCode) { throw "MSBuild failed" }

        $buildConfigDir = $buildConfig.Replace(' ', '')

        copy -Force ".\x64\$buildConfigDir\package\$sysFileName" $outputPath
        copy -Force ".\x64\$buildConfigDir\package\$infFileName" $outputPath
        copy -Force ".\PCapExt\x64\$buildConfigDir\PCapExt.pdb" $outputPath
    }
    finally
    {
        popd
    }

    ExecRetry {
        &signtool.exe sign /sha1 $sign_cert_thumbprint /t http://timestamp.verisign.com/scripts/timstamp.dll /v "$outputPath\$sysFileName"
        if ($LastExitCode) { throw "signtool failed" }
    }

    &inf2cat.exe /driver:$outputPath /os:8_x64 /USELOCALTIME
    if ($LastExitCode) { throw "inf2cat failed" }

    ExecRetry {
        &signtool.exe sign /sha1 $sign_cert_thumbprint /t http://timestamp.verisign.com/scripts/timstamp.dll /v "$outputPath\$catFileName"
        if ($LastExitCode) { throw "signtool failed" }
    }

    copy -Force "$pcapExtDir\PCapExt\install.cmd" $outputPath
    copy -Force "$pcapExtDir\PCapExt\uninstall.cmd" $outputPath

    $zipPath = "$buildDir\PCapExt.zip"

    cd $buildDir
    &7z a -r -tzip $zipPath PCapExt\*

    $ftpsUsername = $ftpsCredentials.UserName
    $ftpsPassword = $ftpsCredentials.GetNetworkCredential().Password

    ExecRetry {
        &ftps -h www.cloudbase.it -ssl All -U $ftpsUsername -P $ftpsPassword -sslInvalidServerCertHandling Accept -p $zipPath /cloudbase.it/main/downloads/HyperV-PCapExt.zip
        if ($LastExitCode) { throw "ftps failed" }
    }
}
finally
{
    popd
}
