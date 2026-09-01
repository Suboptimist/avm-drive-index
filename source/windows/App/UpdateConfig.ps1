# UpdateConfig.ps1 -- version and update source for the Windows app.
#
# "Release Update.command" rewrites the AppVersion line below, so keep it on
# one line in exactly this shape.
#
# The repository is public, so no key is needed and nothing secret ships inside
# the app. GitHub's unauthenticated API allows 60 requests an hour per address,
# against a once-a-day check.
#
# NOTE: keep this file ASCII-only (see Common.ps1 for why).

$script:AppVersion  = '1.7.0'

$script:UpdateOwner = 'Suboptimist'
$script:UpdateRepo  = 'avm-drive-index'
$script:UpdateAsset = 'AVM-Drive-Index-Windows.zip'

# The folder inside the zip. Everything under it replaces the installed copy.
$script:UpdateRoot  = 'AVM Drive Index (Windows)'

function Get-UpdateApiUrl {
    "https://api.github.com/repos/$script:UpdateOwner/$script:UpdateRepo/releases/latest"
}

function Get-UpdatePageUrl {
    "https://github.com/$script:UpdateOwner/$script:UpdateRepo/releases/latest"
}
