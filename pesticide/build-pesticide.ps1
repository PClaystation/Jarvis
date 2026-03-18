param(
  [string]$OutputPath = ".\dist\cordyceps-pesticide.exe",
  [string]$Version = "dev",
  [ValidateSet("amd64", "arm64")]
  [string]$Arch = "amd64",
  [switch]$Console
)

$ErrorActionPreference = "Stop"

$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $moduleRoot

try {
  $resolvedOutputPath =
    if ([System.IO.Path]::IsPathRooted($OutputPath)) {
      $OutputPath
    } else {
      Join-Path $moduleRoot $OutputPath
    }

  $resolvedOutputPath = [System.IO.Path]::GetFullPath($resolvedOutputPath)
  $outputDir = Split-Path -Parent $resolvedOutputPath
  New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

  $oldGoos = $env:GOOS
  $oldGoarch = $env:GOARCH
  $oldCgo = $env:CGO_ENABLED

  $env:GOOS = "windows"
  $env:GOARCH = $Arch
  $env:CGO_ENABLED = "0"

  $ldflags = @("-s", "-w", "-X", "main.version=$Version")
  if (-not $Console.IsPresent) {
    $ldflags += "-H=windowsgui"
  }

  go build `
    -trimpath `
    -ldflags ($ldflags -join " ") `
    -o $resolvedOutputPath `
    ./cmd/pesticide

  Write-Host "Built Cordyceps Pesticide: $resolvedOutputPath"
}
finally {
  $env:GOOS = $oldGoos
  $env:GOARCH = $oldGoarch
  $env:CGO_ENABLED = $oldCgo
  Pop-Location
}
