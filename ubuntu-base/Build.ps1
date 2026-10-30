#Requires -Version 5.1
<#
.SYNOPSIS
    Build the Ubuntu 24.04.5 x64 base image with Packer + VirtualBox on Windows.

.DESCRIPTION
    Produces artifacts\ubuntu-24.04.5-base-amd64-virtualbox.ova (+ .sha256).
    Put corporate root CAs (e.g. zscaler-ca.crt) in ..\certs\ first; they are
    trusted inside the guest before anything is downloaded.

    Secrets: set them as environment variables rather than on the command line:
        $s = Read-Host 'Build password' -AsSecureString
        $env:PKR_VAR_build_password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))
        $env:PKR_VAR_ssh_authorized_key = (Get-Content -Raw $HOME\.ssh\id_ed25519.pub).Trim()
    or put them in local.auto.pkrvars.hcl (git-ignored).

.EXAMPLE
    .\Build.ps1                                   # build the OVA
.EXAMPLE
    .\Build.ps1 -Action validate
.EXAMPLE
    .\Build.ps1 -PackerArgs '-var', 'cpus=4', '-var', 'headless=true'
#>
[CmdletBinding()]
param(
    [ValidateSet('virtualbox')]
    [string]$Target = 'virtualbox',

    [ValidateSet('build', 'validate')]
    [string]$Action = 'build',

    [string[]]$PackerArgs = @(),

    # Date stamp in output names (template-<date>-...). Default: today in UTC,
    # matching Packer's timestamp(). Set it to rebuild a given release.
    [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
    [string]$ImageDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd'),

    [string]$NamePrefix = 'template'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

if (-not $PackerArgs -or $PackerArgs.Count -eq 0) { $PackerArgs = @() }

$targets = @{
    virtualbox = @{ Only = 'ubuntu-base.virtualbox-iso.ubuntu-base-vbox'; VmName = "$NamePrefix-$ImageDate-ubuntu-24.04.5-base-amd64-virtualbox" }
}
$only   = $targets[$Target].Only
$vmName = $targets[$Target].VmName

function Assert-Command {
    param([string]$Name, [string]$Hint)
    if (-not (Get-Command -Name $Name -ErrorAction SilentlyContinue)) { throw "Missing '$Name'. $Hint" }
}

function Invoke-Packer {
    param([string[]]$Arguments)
    Write-Host "packer $($Arguments -join ' ')" -ForegroundColor DarkGray
    & packer @Arguments
    if ($LASTEXITCODE -ne 0) { throw "packer $($Arguments[0]) failed (exit $LASTEXITCODE)" }
}

# --- Prerequisites ------------------------------------------------------------
Assert-Command -Name 'packer' -Hint 'Install: winget install Hashicorp.Packer'

if (-not (Get-Command -Name 'VBoxManage' -ErrorAction SilentlyContinue)) {
    $vboxDir = if ($env:VBOX_MSI_INSTALL_PATH) { $env:VBOX_MSI_INSTALL_PATH } else { Join-Path $env:ProgramFiles 'Oracle\VirtualBox' }
    if (Test-Path -LiteralPath (Join-Path $vboxDir 'VBoxManage.exe')) {
        $env:PATH = "$vboxDir;$env:PATH"   # this session only
    } else {
        throw 'VirtualBox not found. Install VirtualBox 7.x (winget install Oracle.VirtualBox) or add VBoxManage to PATH.'
    }
}
$vboxVersion = (& VBoxManage --version).Trim()
Write-Host "VirtualBox $vboxVersion"
if ($vboxVersion -notmatch '^(7|8)\.') { Write-Warning 'VirtualBox 7.0+ is expected (the template uses --nat-localhostreachable1).' }

# Hyper-V / VBS: VirtualBox then runs on the Windows hypervisor - slower, still works.
$cs = Get-CimInstance -ClassName Win32_ComputerSystem
if ($cs.HypervisorPresent) {
    Write-Warning 'A Windows hypervisor is active (Hyper-V / VBS / WSL2). VirtualBox will run on top of it: expect a slower build (turtle icon in the VM window).'
}

# --- Line endings: these files are used inside the Linux guest ----------------
# (Packer itself is fine with CRLF in *.pkr.hcl / *.pkrvars.hcl.)
$lfFiles = @(
    @(Get-ChildItem -LiteralPath 'scripts', 'templates', 'files' -Recurse -File) +
    @(Get-Item -LiteralPath 'packages.txt')
)
$crlf = @($lfFiles | Where-Object { [IO.File]::ReadAllText($_.FullName).Contains("`r`n") })
if ($crlf.Count -gt 0) {
    $list = ($crlf | ForEach-Object { $_.FullName }) -join "`n  "
    throw "These files have Windows (CRLF) line endings and will break inside the Linux guest:`n  $list`nFix: git add --renormalize . ; git checkout -- .   (the repo's .gitattributes forces LF)"
}

# --- Corporate certificates -----------------------------------------------------
$certDir = Join-Path $PSScriptRoot '..\certs'
$certs = @(Get-ChildItem -LiteralPath $certDir -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in '.crt', '.pem', '.cer' })
if ($certs.Count -gt 0) {
    Write-Host "Corporate CA certificates to trust in the guest: $(($certs | ForEach-Object { $_.Name }) -join ', ')"
} else {
    Write-Warning "No certificates in $certDir. Behind Zscaler / TLS inspection, HTTPS downloads in the guest will fail."
}

# --- Packer ---------------------------------------------------------------------
# Pass the date explicitly so Packer and this script agree on the file names.
$PackerArgs = @('-var', "image_date=$ImageDate", '-var', "name_prefix=$NamePrefix") + $PackerArgs
Write-Host "Image name: $vmName"

Invoke-Packer -Arguments @('init', '.')
Invoke-Packer -Arguments (@('validate', "-only=$only") + $PackerArgs + @('.'))
if ($Action -eq 'validate') { Write-Host 'Validation passed.' -ForegroundColor Green; return }

$null = New-Item -ItemType Directory -Force -Path 'logs', 'artifacts'
$env:PACKER_LOG = '1'
$env:PACKER_LOG_PATH = Join-Path 'logs' ("packer-{0}-{1}.log" -f $Target, (Get-Date -Format 'yyyyMMdd-HHmmss'))
Write-Host "Detailed log: $env:PACKER_LOG_PATH"
try {
    Invoke-Packer -Arguments (@('build', '-on-error=ask', "-only=$only") + $PackerArgs + @('.'))
} finally {
    Remove-Item Env:\PACKER_LOG, Env:\PACKER_LOG_PATH -ErrorAction SilentlyContinue
}

# --- Publish the OVA to artifacts\ with a checksum --------------------------------
$ova = Join-Path $PSScriptRoot "output\$vmName\$vmName.ova"
if (-not (Test-Path -LiteralPath $ova)) { throw "Build finished but $ova was not found." }
$dest = Join-Path $PSScriptRoot "artifacts\$vmName.ova"
Copy-Item -LiteralPath $ova -Destination $dest -Force
$hash = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToLowerInvariant()
$hashLine = "$hash  $vmName.ova"
[IO.File]::WriteAllText("$dest.sha256", "$hashLine`n")
Write-Host "OVA:    $dest" -ForegroundColor Green
Write-Host "SHA256: $hash"
Write-Host "Import: VirtualBox > File > Import Appliance, or: VBoxManage import `"$dest`""
