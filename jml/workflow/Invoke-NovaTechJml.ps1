#requires -Version 7.0
<#
    Preview and apply for all three stages were validated in the live NovaTech
    lab on 22 November 2026 with Jordan Ellis and two pinned groups.
    First-sign-in behaviour and active application-session termination were outside scope.
    Uses an existing delegated Microsoft Graph context.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Joiner','Mover','Leaver')][string]$Stage,
    [Parameter(Mandatory)][guid]$ExpectedTenantId,
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9.-]+$')][string]$ApprovedDomain,
    [Parameter(Mandatory)][ValidatePattern('^[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+$')][string]$UserPrincipalName,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ExpectedDisplayName,
    [Parameter(Mandatory)][guid]$SupportGroupId,
    [Parameter(Mandatory)][guid]$DevelopersGroupId,
    [guid]$ExpectedUserId = [guid]::Empty,
    [switch]$PortalVerifiedNonRoleAssignableGroups,
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$results = [Collections.Generic.List[object]]::new()

function Record($action, $status, $detail) {
    $results.Add([pscustomobject]@{
        Action = $action
        Status = $status
        Detail = $detail
    })
}

function Assert-Context {
    $ctx = Get-MgContext
    if (-not $ctx -or $ctx.TenantId -ne $ExpectedTenantId.ToString() -or
        $ctx.AuthType -ne 'Delegated' -or $ctx.Environment -ne 'Global') {
        throw 'Expected delegated Microsoft Graph Global tenant context is required.'
    }
}

function Change($action, [scriptblock]$operation, [scriptblock]$verify) {
    if (-not $Apply) {
        Record $action 'Planned' 'Dry run: no write issued.'
        return $true
    }

    try {
        Assert-Context
        & $operation | Out-Null
        if (-not (& $verify)) {
            throw 'Read-back did not confirm the expected state; recheck before retrying.'
        }

        $detail = if ($action -eq 'Revoke sign-in sessions') {
            'API acknowledgement only; active token termination not tested.'
        } else {
            'Write and read-back succeeded.'
        }
        Record $action 'Verified' $detail
        return $true
    } catch {
        # Raw service errors may include identifiers.
        Record $action 'Failed' 'Request or verification failed. Inspect privately and use the runbook.'
        return $false
    }
}

function Member($groupId, $userId) {
    return @(Get-MgGroupMember -GroupId $groupId -All -ErrorAction Stop |
        ForEach-Object { $_.Id }) -contains $userId
}

function Ensure-Member($groupId, $userId, [bool]$present, $label) {
    try {
        $current = Member $groupId $userId
        if ($current -eq $present) {
            Record $label 'AlreadyComplete' 'Direct membership matches.'
            return $true
        }

        if ($present) {
            return Change $label {
                New-MgGroupMemberByRef -GroupId $groupId -BodyParameter @{
                    '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$userId"
                } -ErrorAction Stop
            } { Member $groupId $userId }
        }

        return Change $label {
            Remove-MgGroupMemberByRef -GroupId $groupId -DirectoryObjectId $userId -ErrorAction Stop
        } { -not (Member $groupId $userId) }
    } catch {
        Record $label 'Failed' 'Membership read failed; no write attempted.'
        return $false
    }
}

try {
    if ($ExpectedTenantId -eq [guid]::Empty -or $SupportGroupId -eq [guid]::Empty -or
        $DevelopersGroupId -eq [guid]::Empty -or $SupportGroupId -eq $DevelopersGroupId) {
        throw 'Supply nonempty, distinct approved group IDs and a nonempty tenant ID.'
    }
    if ($UserPrincipalName.Split('@')[1] -ine $ApprovedDomain) {
        throw 'UPN is outside the approved domain.'
    }
    if ($Stage -ne 'Joiner' -and $ExpectedUserId -eq [guid]::Empty) {
        throw 'Mover and Leaver require an independently verified user ID.'
    }

    Assert-Context

    foreach ($pair in @(@($SupportGroupId, 'SG-IT-Support'), @($DevelopersGroupId, 'SG-Developers'))) {
        $grp = Get-MgGroup -GroupId $pair[0].ToString() `
            -Property Id,DisplayName,SecurityEnabled,MailEnabled,GroupTypes,IsAssignableToRole,OnPremisesSyncEnabled `
            -ErrorAction Stop

        if ($grp.Id -ne $pair[0].ToString() -or $grp.DisplayName -cne $pair[1] -or
            $grp.SecurityEnabled -ne $true -or $grp.MailEnabled -ne $false -or
            @($grp.GroupTypes).Count -ne 0 -or $grp.OnPremisesSyncEnabled -eq $true) {
            throw 'Approved group must be an exact-name cloud-only assigned security group.'
        }

        $roleAssignable = $grp.IsAssignableToRole
        $allowUnknownRoleStatus = -not $Apply -or $PortalVerifiedNonRoleAssignableGroups
        $roleStatusAccepted = ($false -eq $roleAssignable) -or
            ($null -eq $roleAssignable -and $allowUnknownRoleStatus)

        if (-not $roleStatusAccepted) {
            throw "Entra role-assignability check failed for $($grp.DisplayName)."
        }
    }

    $users = @(Get-MgUser -Filter "userPrincipalName eq '$UserPrincipalName'" `
        -Property Id,DisplayName,UserPrincipalName,Department,AccountEnabled,UserType,OnPremisesSyncEnabled `
        -All -ErrorAction Stop)

    if ($users.Count -gt 1) {
        throw 'Ambiguous target.'
    }

    $user = if ($users.Count -eq 1) { $users[0] } else { $null }
    if ($user) {
        if ($ExpectedUserId -eq [guid]::Empty -or $user.Id -ne $ExpectedUserId.ToString() -or
            $user.UserPrincipalName -ine $UserPrincipalName -or $user.DisplayName -cne $ExpectedDisplayName -or
            $user.UserType -ne 'Member' -or $user.OnPremisesSyncEnabled -eq $true) {
            throw 'Existing target must match the pinned ID, exact display name and UPN, and be a cloud-only Member.'
        }
    } elseif ($Stage -ne 'Joiner' -or $ExpectedUserId -ne [guid]::Empty) {
        throw 'Pinned target was not found.'
    }

    if (-not $user) {
        if (-not $Apply) {
            Record 'Create user' 'Planned' 'IT Support; enabled; password change required at first sign-in.'
            Record 'Add SG-IT-Support' 'Planned' 'After successful creation and target verification.'
        } else {
            $secret = Read-Host 'Temporary password for fresh fictional lab user' -AsSecureString
            $plain = [Net.NetworkCredential]::new('', $secret).Password
            try {
                Assert-Context
                $created = New-MgUser -BodyParameter @{
                    DisplayName       = $ExpectedDisplayName
                    UserPrincipalName = $UserPrincipalName
                    MailNickname      = $UserPrincipalName.Split('@')[0]
                    AccountEnabled    = $true
                    Department        = 'IT Support'
                    PasswordProfile   = @{
                        Password                      = $plain
                        ForceChangePasswordNextSignIn = $true
                    }
                } -ErrorAction Stop
                $user = Get-MgUser -UserId $created.Id `
                    -Property Id,DisplayName,UserPrincipalName,Department,AccountEnabled -ErrorAction Stop

                if ($user.UserPrincipalName -ine $UserPrincipalName -or
                    $user.DisplayName -cne $ExpectedDisplayName -or
                    $user.Department -ne 'IT Support' -or $user.AccountEnabled -ne $true) {
                    throw 'Creation read-back mismatch.'
                }

                Record 'Create user' 'Verified' 'Created and read back identity, department and enabled state; password policy was submitted.'
            } finally {
                $plain = $null
                $secret = $null
            }

            $null = Ensure-Member $SupportGroupId.ToString() $user.Id $true 'Add SG-IT-Support'
        }
    } elseif ($Stage -in @('Joiner', 'Mover')) {
        if ($user.AccountEnabled -ne $true) {
            throw 'Disabled account requires manual review; workflow never re-enables an existing account.'
        }

        if ($Stage -eq 'Joiner') {
            if ($user.Department -ne 'IT Support' -or (Member $DevelopersGroupId.ToString() $user.Id)) {
                throw 'Existing joiner has incompatible lifecycle state; review instead of moving backwards.'
            }
            $null = Ensure-Member $SupportGroupId.ToString() $user.Id $true 'Add SG-IT-Support'
        } else {
            $removed = Ensure-Member $SupportGroupId.ToString() $user.Id $false 'Remove SG-IT-Support'
            if ($removed) {
                $added = Ensure-Member $DevelopersGroupId.ToString() $user.Id $true 'Add SG-Developers'
                if ($added) {
                    if ($user.Department -eq 'Development') {
                        Record 'Set Development department' 'AlreadyComplete' 'Department matches.'
                    } else {
                        $null = Change 'Set Development department' {
                            Update-MgUser -UserId $user.Id -Department 'Development' -ErrorAction Stop
                        } {
                            (Get-MgUser -UserId $user.Id -Property Department -ErrorAction Stop).Department -eq 'Development'
                        }
                    }
                } else {
                    Record 'Set Development department' 'Skipped' 'Destination membership failed.'
                }
            } else {
                Record 'Add SG-Developers' 'Skipped' 'Source removal failed; avoid accumulating access.'
            }
        }
    } else {
        if ($user.AccountEnabled -eq $false) {
            Record 'Disable account' 'AlreadyComplete' 'Account is disabled.'
        } else {
            $null = Change 'Disable account' {
                Update-MgUser -UserId $user.Id -AccountEnabled:$false -ErrorAction Stop
            } {
                (Get-MgUser -UserId $user.Id -Property AccountEnabled -ErrorAction Stop).AccountEnabled -eq $false
            }
        }

        # Independent steps continue after failure to reduce remaining access.
        $null = Change 'Revoke sign-in sessions' {
            if (-not (Get-Command Revoke-MgUserSignInSession -ErrorAction SilentlyContinue)) {
                throw 'Actions module/cmdlet unavailable.'
            }

            $answer = Revoke-MgUserSignInSession -UserId $user.Id -ErrorAction Stop
            $ok = if ($answer -is [bool]) {
                $answer
            } elseif ($null -ne $answer -and $answer.PSObject.Properties['Value']) {
                $answer.Value -eq $true
            } else {
                $false
            }
            if (-not $ok) {
                throw 'Service did not confirm revocation.'
            }
        } { $true } # The operation checks the API acknowledgement.

        $null = Ensure-Member $SupportGroupId.ToString() $user.Id $false 'Remove SG-IT-Support'
        $null = Ensure-Member $DevelopersGroupId.ToString() $user.Id $false 'Remove SG-Developers'
    }
} catch {
    Record 'Preflight or execution' 'Failed' $_.Exception.Message
}

$results
if (@($results | Where-Object Status -eq 'Failed').Count) {
    Write-Error 'Workflow incomplete. Inspect step results and follow the portal fallback; no rollback was attempted.' -ErrorAction Continue
    exit 1
}
