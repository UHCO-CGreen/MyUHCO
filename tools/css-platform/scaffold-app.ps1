[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [Parameter(Mandatory = $true)]
  [string]$AppName,

  [string]$DisplayName = "",

  [string]$BodyId = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-NormalizedSlug {
  param([string]$Value)

  $slug = $Value.Trim().ToLowerInvariant()
  $slug = [regex]::Replace($slug, "[^a-z0-9]+", "-")
  $slug = $slug.Trim("-")

  if ([string]::IsNullOrWhiteSpace($slug)) {
    throw "AppName must contain at least one letter or number."
  }

  return $slug
}

function New-BodyIdValue {
  param(
    [string]$ProvidedBodyId,
    [string]$Slug
  )

  if (-not [string]::IsNullOrWhiteSpace($ProvidedBodyId)) {
    return $ProvidedBodyId.Trim()
  }

  $parts = $Slug.Split("-", [System.StringSplitOptions]::RemoveEmptyEntries)
  if ($parts.Count -eq 0) {
    return "PortalApp"
  }

  return ($parts | ForEach-Object {
    if ($_.Length -eq 1) {
      $_.ToUpperInvariant()
    } else {
      $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1)
    }
  }) -join ""
}

function Write-ScaffoldFile {
  param(
    [string]$Path,
    [string]$Content
  )

  $targetDir = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $targetDir)) {
    if ($PSCmdlet.ShouldProcess($targetDir, "Create directory")) {
      New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }
  }

  if (Test-Path -LiteralPath $Path) {
    Write-Host "Skipping existing file: $Path"
    return
  }

  if ($PSCmdlet.ShouldProcess($Path, "Create file")) {
    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
  }
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$slug = New-NormalizedSlug -Value $AppName
$resolvedDisplayName = if ([string]::IsNullOrWhiteSpace($DisplayName)) { $AppName.Trim() } else { $DisplayName.Trim() }
$resolvedBodyId = New-BodyIdValue -ProvidedBodyId $BodyId -Slug $slug

$themeDir = Join-Path $repoRoot "assets\css\src\themes\$slug"
$appDir = Join-Path $repoRoot "assets\css\src\apps\$slug"
$distDir = Join-Path $repoRoot "assets\css\dist\$slug"

foreach ($dir in @($themeDir, $appDir, $distDir)) {
  if (-not (Test-Path -LiteralPath $dir)) {
    if ($PSCmdlet.ShouldProcess($dir, "Create directory")) {
      New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
  }
}

$tokensContent = @"
4primary: #0d6efd;
4primary-dark: #0a58ca;
4secondary: #6c757d;
4success: #198754;
4danger: #dc3545;
4info: #0dcaf0;
4warning: #ffc107;

4portal-ink: #1f2630;
4portal-muted: #5d6675;
4portal-surface: #ffffff;
4portal-surface-soft: #f4f6f9;
4portal-border: #dbe1ea;
"@

$themeContent = @"
@use "./tokens";

:root {
  --uhco-primary: #{tokens.4primary};
  --uhco-primary-dark: #{tokens.4primary-dark};
  --uhco-ink: #{tokens.4portal-ink};
  --uhco-muted: #{tokens.4portal-muted};
  --uhco-surface: #{tokens.4portal-surface};
  --uhco-surface-soft: #{tokens.4portal-surface-soft};
  --uhco-border: #{tokens.4portal-border};
}

body#$resolvedBodyId {
  margin: 0;
  min-height: 100vh;
  color: var(--uhco-ink);
  background: var(--uhco-surface-soft);
}
"@

$appContent = @"
// App-specific styles for $resolvedDisplayName.
// Intentionally empty until this application needs custom styling.
"@

$adminOverridesContent = @"
// Admin-only styles for $resolvedDisplayName.
"@

$pagesOverridesContent = @"
// Page-platform styles for $resolvedDisplayName.
"@

$portalEntryContent = @"
@use "../../themes/$slug/tokens" as brand;
@use "bootstrap/scss/bootstrap" with (
  4primary: brand.4primary,
  4secondary: brand.4secondary,
  4success: brand.4success,
  4danger: brand.4danger,
  4info: brand.4info,
  4warning: brand.4warning
);

@use "../../shared/base";
@use "../../shared/mixins";
@use "../../themes/$slug/theme";
@use "../../platform/header";
@use "../../platform/content";
@use "../../platform/sidebar";
@use "./app";
"@

$adminEntryContent = @"
@use "./portal";
@use "./admin-overrides";
"@

$pagesEntryContent = @"
@use "./portal";
@use "./pages-overrides";
"@

Write-ScaffoldFile -Path (Join-Path $themeDir "_tokens.scss") -Content $tokensContent
Write-ScaffoldFile -Path (Join-Path $themeDir "_theme.scss") -Content $themeContent
Write-ScaffoldFile -Path (Join-Path $appDir "_app.scss") -Content $appContent
Write-ScaffoldFile -Path (Join-Path $appDir "_admin-overrides.scss") -Content $adminOverridesContent
Write-ScaffoldFile -Path (Join-Path $appDir "_pages-overrides.scss") -Content $pagesOverridesContent
Write-ScaffoldFile -Path (Join-Path $appDir "portal.scss") -Content $portalEntryContent
Write-ScaffoldFile -Path (Join-Path $appDir "admin.scss") -Content $adminEntryContent
Write-ScaffoldFile -Path (Join-Path $appDir "pages.scss") -Content $pagesEntryContent

Write-Host "Scaffold ready for app slug '$slug'."
Write-Host "Theme: $themeDir"
Write-Host "App:   $appDir"
Write-Host "Dist:  $distDir"