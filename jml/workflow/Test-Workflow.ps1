# Offline mock checks: all GUIDs below are synthetic fixtures, not tenant IDs.
$ErrorActionPreference = 'Stop'
$global:ntMock_tenant = '11111111-1111-4111-8111-111111111111'
$global:ntMock_support = '22222222-2222-4222-8222-222222222222'
$global:ntMock_developers = '33333333-3333-4333-8333-333333333333'
$global:ntMock_target = '44444444-4444-4444-8444-444444444444'
$global:ntMock_passed = 0
function Reset-State {
    $global:ntMock_roleStatus=@{}; $global:ntMock_roleStatus[$global:ntMock_support]=$false; $global:ntMock_roleStatus[$global:ntMock_developers]=$false
    $global:ntMock_writes=0; $global:ntMock_wrongTenant=$false; $global:ntMock_wrongGroup=$false
    $global:ntMock_failRemoval=$false; $global:ntMock_failRevoke=$false; $global:ntMock_failDisable=$false
    $global:ntMock_user=[pscustomobject]@{Id=$global:ntMock_target;DisplayName='Jordan Ellis';UserPrincipalName='jordan.ellis@example.invalid';Department='IT Support';AccountEnabled=$true;UserType='Member';OnPremisesSyncEnabled=$null}
    $global:ntMock_members=@{}; $global:ntMock_members[$global:ntMock_support]=@($global:ntMock_target); $global:ntMock_members[$global:ntMock_developers]=@()
}
function Get-MgContext { [pscustomobject]@{TenantId=$(if($global:ntMock_wrongTenant){$global:ntMock_support}else{$global:ntMock_tenant});AuthType='Delegated';Environment='Global'} }
function Get-MgGroup {
    [CmdletBinding()]param($GroupId,$Property)
    [pscustomobject]@{Id=$GroupId;DisplayName=$(if($global:ntMock_wrongGroup){'Unexpected'}elseif($GroupId -eq $global:ntMock_support){'SG-IT-Support'}else{'SG-Developers'});SecurityEnabled=$true;MailEnabled=$false;GroupTypes=@();IsAssignableToRole=$global:ntMock_roleStatus[$GroupId];OnPremisesSyncEnabled=$null}
}
function Get-MgUser { [CmdletBinding()]param($Filter,$Property,$UserId,[switch]$All) $global:ntMock_user }
function Get-MgGroupMember { [CmdletBinding()]param($GroupId,[switch]$All) foreach($id in $global:ntMock_members[$GroupId]){[pscustomobject]@{Id=$id}} }
function Remove-MgGroupMemberByRef {
    [CmdletBinding()]param($GroupId,$DirectoryObjectId)
    $global:ntMock_writes++; if($global:ntMock_failRemoval){throw 'Injected remove failure'}
    $global:ntMock_members[$GroupId]=@($global:ntMock_members[$GroupId] | Where-Object {$_ -ne $DirectoryObjectId})
}
function New-MgGroupMemberByRef { [CmdletBinding()]param($GroupId,$BodyParameter) $global:ntMock_writes++; $global:ntMock_members[$GroupId]+=($BodyParameter['@odata.id'].Split('/')[-1]) }
function Update-MgUser {
    [CmdletBinding()]param($UserId,$Department,[bool]$AccountEnabled)
    $global:ntMock_writes++
    if($PSBoundParameters.ContainsKey('AccountEnabled')) { if($global:ntMock_failDisable){throw 'Injected disable failure'}; $global:ntMock_user.AccountEnabled=$AccountEnabled }
    if($PSBoundParameters.ContainsKey('Department')) {$global:ntMock_user.Department=$Department}
}
function Revoke-MgUserSignInSession { [CmdletBinding()]param($UserId) $global:ntMock_writes++; if($global:ntMock_failRevoke){throw 'Injected revoke failure'}; $true }
function Read-Host { param($Prompt,[switch]$AsSecureString) if(-not $AsSecureString){throw 'Unexpected prompt'}; ConvertTo-SecureString 'Offline-fixture-password!726' -AsPlainText -Force }
function New-MgUser {
    [CmdletBinding()]param($BodyParameter)
    $global:ntMock_writes++
    if(-not $BodyParameter.PasswordProfile.ForceChangePasswordNextSignIn){throw 'Missing password policy'}
    $global:ntMock_user=[pscustomobject]@{Id=$global:ntMock_target;DisplayName=$BodyParameter.DisplayName;UserPrincipalName=$BodyParameter.UserPrincipalName;Department=$BodyParameter.Department;AccountEnabled=$BodyParameter.AccountEnabled;UserType='Member';OnPremisesSyncEnabled=$null}
    $global:ntMock_user
}
function Run($stage,[switch]$Apply,[switch]$Fresh,[switch]$PortalVerifiedNonRoleAssignableGroups) {
    $p=@{Stage=$stage;ExpectedTenantId=$global:ntMock_tenant;ApprovedDomain='example.invalid';UserPrincipalName='jordan.ellis@example.invalid';ExpectedDisplayName='Jordan Ellis';SupportGroupId=$global:ntMock_support;DevelopersGroupId=$global:ntMock_developers;Apply=$Apply}
    if(-not $Fresh){$p.ExpectedUserId=$global:ntMock_target}
    $p.PortalVerifiedNonRoleAssignableGroups=$PortalVerifiedNonRoleAssignableGroups
    & (Join-Path $PSScriptRoot 'Invoke-NovaTechJml.ps1') @p 2>$null
}
function Check($condition,$label) {if(-not $condition){throw "FAILED: $label"}; $global:ntMock_passed++; "PASS: $label"}
Reset-State
$r=@(Run Mover)
Check ($global:ntMock_writes -eq 0 -and @($r | Where-Object Status -eq 'Planned').Count -eq 3) 'Mover dry run issues zero writes'
$r=@(Run Mover -Apply)
Check ($global:ntMock_writes -eq 3 -and $global:ntMock_user.Department -eq 'Development' -and $global:ntMock_members[$global:ntMock_support].Count -eq 0 -and $global:ntMock_members[$global:ntMock_developers].Count -eq 1) 'Mover applies and verifies three changes'
$r=@(Run Mover -Apply)
Check ($global:ntMock_writes -eq 3 -and @($r | Where-Object Status -eq 'AlreadyComplete').Count -eq 3) 'Mover repeat issues no writes'
Reset-State; $global:ntMock_wrongTenant=$true
$r=@(Run Mover -Apply)
Check ($global:ntMock_writes -eq 0 -and $r.Status -contains 'Failed') 'Wrong tenant rejected before writes'
Reset-State; $global:ntMock_wrongGroup=$true
$r=@(Run Mover -Apply)
Check ($global:ntMock_writes -eq 0 -and $r.Status -contains 'Failed') 'Wrong approved group rejected'
Reset-State; $global:ntMock_user.Id=$global:ntMock_support
$r=@(Run Leaver -Apply)
Check ($global:ntMock_writes -eq 0 -and $r.Status -contains 'Failed') 'Wrong target object ID rejected'
Reset-State; $global:ntMock_failRemoval=$true
$r=@(Run Mover -Apply)
Check ($global:ntMock_writes -eq 1 -and $global:ntMock_members[$global:ntMock_developers].Count -eq 0 -and $global:ntMock_user.Department -eq 'IT Support') 'Mover stops dependent writes after removal failure'
Reset-State; $global:ntMock_failRevoke=$true; $global:ntMock_members[$global:ntMock_developers]=@($global:ntMock_target)
$r=@(Run Leaver -Apply)
Check ($global:ntMock_user.AccountEnabled -eq $false -and $global:ntMock_members[$global:ntMock_support].Count -eq 0 -and $global:ntMock_members[$global:ntMock_developers].Count -eq 0 -and $r.Status -contains 'Failed') 'Leaver continues membership removal after revocation failure'
Reset-State; $global:ntMock_failDisable=$true
$r=@(Run Leaver -Apply)
Check ($global:ntMock_user.AccountEnabled -eq $true -and $global:ntMock_members[$global:ntMock_support].Count -eq 0 -and $r.Status -contains 'Failed') 'Leaver reports disable failure and continues other containment'
Reset-State
$r=@(Run Leaver)
Check ($global:ntMock_writes -eq 0) 'Leaver dry run issues zero writes'
$r=@(Run Leaver -Apply); $before=$global:ntMock_writes
$r=@(Run Leaver -Apply)
Check ($global:ntMock_writes -eq $before+1 -and @($r | Where-Object Status -eq 'AlreadyComplete').Count -eq 3) 'Leaver repeat only reissues revocation'
Reset-State; $global:ntMock_user=$null; $global:ntMock_members[$global:ntMock_support]=@()
$r=@(Run Joiner -Fresh)
Check ($global:ntMock_writes -eq 0 -and $r.Count -eq 2) 'Fresh joiner dry run avoids password prompt and writes'
$r=@(Run Joiner -Fresh -Apply)
Check ($global:ntMock_writes -eq 2 -and $global:ntMock_user.Department -eq 'IT Support' -and $global:ntMock_members[$global:ntMock_support] -contains $global:ntMock_target) 'Fresh joiner creates with password policy and adds membership'
$r=@(Run Joiner -Apply)
Check ($global:ntMock_writes -eq 2 -and $r.Status -contains 'AlreadyComplete') 'Pinned joiner repeat does not recreate or reset password'
$r=@(Run Joiner -Fresh -Apply)
Check ($global:ntMock_writes -eq 2 -and $r.Status -contains 'Failed') 'Existing joiner requires independently pinned ID'
# Exercise each pinned group independently; the other group remains explicit false.
# Each case uses the complete workflow entry point with in-memory Graph mocks.
foreach ($groupId in @($global:ntMock_support,$global:ntMock_developers)) {
    foreach ($roleCase in @('False','True','Null')) {
        foreach ($applyCase in @($false,$true)) {
            foreach ($portalCase in @($false,$true)) {
                Reset-State
                $global:ntMock_roleStatus[$groupId] = switch ($roleCase) {
                    'False' { $false }; 'True' { $true }; 'Null' { $null }
                }
                $r=@(Run Mover -Apply:$applyCase -PortalVerifiedNonRoleAssignableGroups:$portalCase)
                $shouldPass = $roleCase -eq 'False' -or ($roleCase -eq 'Null' -and (-not $applyCase -or $portalCase))
                $failed=@($r | Where-Object Status -eq 'Failed').Count -gt 0
                $expectedWrites=if($shouldPass -and $applyCase){3}else{0}
                $correctState=if($shouldPass -and $applyCase){$global:ntMock_user.Department -eq 'Development'}else{$global:ntMock_user.Department -eq 'IT Support'}
                $label="Role check group=$groupId value=$roleCase apply=$applyCase portal=$portalCase"
                Check ($failed -eq (-not $shouldPass) -and $global:ntMock_writes -eq $expectedWrites -and $correctState) $label
            }
        }
    }
}
"$global:ntMock_passed checks passed. Offline mocks only."


