# Reusable JML workflow

**Live lab validation completed on 22 November 2026.** Harsh ran preview and apply for Joiner, Mover and Leaver with Jordan Ellis, one fictional identity, and two pinned groups. The run used PowerShell 7.7.0, delegated Graph access and Microsoft.Graph.Users.Actions 2.41.2 for session revocation. See the [results and evidence](../jordan-live-validation.md). This follow-up is separate from Maya's earlier hybrid workflow. First-sign-in behaviour and active application-session termination were outside scope; one successful lab run does not establish production readiness.

## Behaviour

[Invoke-NovaTechJml.ps1](Invoke-NovaTechJml.ps1) defaults to dry run. It reads Graph state but issues no directory writes without `-Apply`. It uses an already authenticated delegated Global-cloud context; it does not authenticate, consent, install modules or change Security Defaults.

Every run requires the expected tenant GUID, approved domain, exact display name and UPN, and approved object IDs for SG-IT-Support and SG-Developers. It checks both groups' exact names, assigned security-group type and cloud-only state, then checks role-assignability as described below. IDs must come from your independent approval record, not from a display-name lookup during the run. Group assignments and downstream permissions still require manual review before granting access.

### Null group role-assignability and portal verification

In Jordan's run, `isAssignableToRole` was null for both groups, including in a direct Graph request. The earlier requirement for an explicit false blocked the run. Harsh verified both pinned Object IDs in the portal and confirmed neither group could be assigned an Entra role. The tested copy adds `-PortalVerifiedNonRoleAssignableGroups`.

| Returned value | Preview | Apply |
|---|---|---|
| Explicit false | Allowed after other checks | Allowed after other checks |
| Explicit true | Blocked | Blocked even with the switch |
| Null / blank | Allowed; no writes | Requires the portal-verification switch and all other checks |

The switch records the operator's attestation in the invocation; it does not perform a portal lookup or write a separate verification log. Before supplying it, independently verify **both** group Object IDs and their non-role-assignable state in the correct tenant, and retain that approval privately. Do not infer safe role status from null alone. The switch never overrides a true response or another preflight failure.

Mover and Leaver require a pinned user object ID. An existing Joiner also requires its verified ID; a name match alone is never adopted. Existing disabled users are never re-enabled. Run stages separately in order. This is a two-group lab workflow, not an organization-wide entitlement cleanup tool.

Joiner submits a password-change-at-first-sign-in policy. Password entry happens only during apply, via a secure prompt; Graph's password profile temporarily needs a plain string in process memory. Do not enable transcription or capture password entry. No password is written to source or results. Creation success checks identity, department and enabled state; an actual first-sign-in test remains separate. Record the created object ID privately in the portal before subsequent runs.

Mover removes old membership first, then adds the new one and updates the department. Failure of a prerequisite stops dependent steps. This can leave the account without either lab membership; investigate and rerun with the same pinned target. There is no automatic rollback or membership restoration.

Leaver attempts disablement, session revocation and removal from both approved groups independently. A revocation failure therefore does not stop membership removal. Already-completed membership, department and disable changes are reported without rewriting them. Revocation is intentionally repeated on each leaver apply; its acknowledgement does not establish termination of all active access tokens. Results show Planned, AlreadyComplete, Verified, Skipped or Failed; any failure produces exit code 1. Successful writes followed by stale read-back can appear as failures: inspect state before retrying.

## Prepare a future lab run

Jordan has already been offboarded. For any future, separately authorized live run, use a fresh fictional identity such as **Taylor Reed**, preserving both Jordan and Maya's evidence. Review and supply identifiers locally; the repository contains no real tenant identifiers. Keep local configuration and logs private.

Review the installed SDK and import Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Groups and Microsoft.Graph.Users.Actions. Confirm `Get-Command Revoke-MgUserSignInSession` resolves before testing. Microsoft documents the command and module here: [Revoke-MgUserSignInSession](https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.users.actions/revoke-mgusersigninsession?view=graph-powershell-1.0).

Authenticate separately using an approved interactive method and the expected tenant. Review delegated consent and administrator roles for each stage. User creation/department changes require User.ReadWrite.All; group changes use GroupMember.ReadWrite.All, with Group.Read.All for group-property inspection. Account disablement can use User.EnableDisableAccount.All plus User.Read.All; session revocation uses User.RevokeSessions.All. Permissions alone do not grant the administrator every sensitive action. See [update user permissions](https://learn.microsoft.com/en-us/graph/api/user-update?view=graph-rest-1.0) and [session revocation](https://learn.microsoft.com/en-us/graph/api/user-revokesigninsessions?view=graph-rest-1.0). The workflow validates context and resources; API authorization remains enforced by Graph.

In PowerShell, from this directory:

```powershell
# Enter independently checked values privately. Nothing is stored to a file.
$settings = @{
    ExpectedTenantId = [guid](Read-Host 'Approved lab tenant GUID')
    ApprovedDomain = Read-Host 'Verified lab domain'
    UserPrincipalName = Read-Host 'Fresh Taylor Reed lab UPN'
    ExpectedDisplayName = 'Taylor Reed'
    SupportGroupId = [guid](Read-Host 'Approved SG-IT-Support GUID')
    DevelopersGroupId = [guid](Read-Host 'Approved SG-Developers GUID')
}
# Default: read-only preview, with no password prompt.
./Invoke-NovaTechJml.ps1 -Stage Joiner @settings
# Examples only: after reviewing the preview and verifying both pinned groups
# in the portal, the switch explicitly attests that check for null Graph values:
./Invoke-NovaTechJml.ps1 -Stage Joiner @settings -Apply -PortalVerifiedNonRoleAssignableGroups

# Independently verify the new user's object ID in Entra.
$settings.ExpectedUserId = [guid](Read-Host 'Verified Taylor Reed object GUID')
./Invoke-NovaTechJml.ps1 -Stage Mover @settings
./Invoke-NovaTechJml.ps1 -Stage Mover @settings -Apply -PortalVerifiedNonRoleAssignableGroups
./Invoke-NovaTechJml.ps1 -Stage Leaver @settings
./Invoke-NovaTechJml.ps1 -Stage Leaver @settings -Apply -PortalVerifiedNonRoleAssignableGroups
```

Keep the account local part fresh, for example `taylor.reed.jmltest`; choose the real approved test domain only at runtime. Repeat dry runs and apply after each successful stage to check already-completed handling. For a creation request that may have succeeded before an error, inspect the portal and pin the resulting ID before retrying. Do not blindly create another account.

## Portal fallback for offboarding

1. Sign in through an approved portal method. Keep Security Defaults enabled. Verify the tenant and the target's UPN, object ID and display name against the private approval record.
2. Block sign-in/disable the target; refresh and confirm Disabled. If this fails, record the failure and escalate while continuing other authorized containment steps.
3. Select Revoke sessions. Record the portal result and check the audit timestamp. Do not interpret acknowledgement as proof that all active tokens or application sessions have ended.
4. Remove the target from each approved lab group, then refresh both direct-member lists. Review other memberships and direct/application grants separately under their owners' authorization.
5. Check audit events and record which actions succeeded, failed or remain pending. Validate application behaviour with a controlled fresh test session where appropriate. Do not report complete offboarding while a required step is unresolved.

## Offline regression checks and validation limits

The [mock harness](Test-Workflow.ps1) supplies in-memory fake Graph commands; it makes no network requests. Run `pwsh -NoProfile -File ./Test-Workflow.ps1` in a separate PowerShell process. The original 15 checks passed under PowerShell 7.6.9 before Jordan's run. The expanded harness now passes **39 checks**: those 15 plus 24 combinations testing false, true and null for each pinned group independently, preview/apply, and the portal switch present/absent. Blocked cases assert zero writes. No live Graph writes or repeat lifecycle run were performed while preparing this update.

Jordan's live evidence confirms the three stage outcomes and final disabled/no-membership state within this lab. It does not validate every tenant, administrator role, consent configuration, replication delay, failure path or application integration. First-sign-in password behaviour and active application-session termination remain outside scope. The portal fallback remains documented for future failures; Jordan's completed run used PowerShell for the lifecycle writes.
