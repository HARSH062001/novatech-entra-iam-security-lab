# Proposed reusable JML workflow

**Untested against live Entra.** This improvement was prepared after Maya's lab. Local mocks cannot establish Microsoft Graph compatibility, consent, administrator-role eligibility, replication timing or effective access removal.

## Behaviour

[Invoke-NovaTechJml.ps1](Invoke-NovaTechJml.ps1) defaults to dry run. It reads Graph state but issues no directory writes without `-Apply`. It uses an already authenticated delegated Global-cloud context; it does not authenticate, consent, install modules or change Security Defaults.

Every run requires the expected tenant GUID, approved domain, exact display name and UPN, and approved object IDs for SG-IT-Support and SG-Developers. It checks both groups' exact names, assigned security-group type, cloud-only state and absence of role-assignment capability. IDs must come from your independent approval record, not from a display-name lookup during the run. Group assignments and downstream permissions still require manual review before granting access.

Mover and Leaver require a pinned user object ID. An existing Joiner also requires its verified ID; a name match alone is never adopted. Existing disabled users are never re-enabled. Run stages separately in order. This is a two-group lab workflow, not an organization-wide entitlement cleanup tool.

Joiner submits a password-change-at-first-sign-in policy. Password entry happens only during apply, via a secure prompt; Graph's password profile temporarily needs a plain string in process memory. Do not enable transcription or capture password entry. No password is written to source or results. Creation success checks identity, department and enabled state; an actual first-sign-in test remains separate. Record the created object ID privately in the portal before subsequent runs.

Mover removes old membership first, then adds the new one and updates the department. Failure of a prerequisite stops dependent steps. This can leave the account without either lab membership; investigate and rerun with the same pinned target. There is no automatic rollback or membership restoration.

Leaver attempts disablement, session revocation and removal from both approved groups independently. A revocation failure therefore does not stop membership removal. Already-completed membership, department and disable changes are reported without rewriting them. Revocation is intentionally repeated on each leaver apply; its acknowledgement does not establish termination of all active access tokens. Results show Planned, AlreadyComplete, Verified, Skipped or Failed; any failure produces exit code 1. Successful writes followed by stale read-back can appear as failures: inspect state before retrying.

## Prepare a fresh fictional test

Use **Jordan Ellis**, a new fictional lab identity, not Maya or an administrator. Review and supply identifiers locally; the repository contains no real tenant identifiers. Keep local configuration and logs private.

Review the installed SDK and import Microsoft.Graph.Authentication, Microsoft.Graph.Users, Microsoft.Graph.Groups and Microsoft.Graph.Users.Actions. Confirm `Get-Command Revoke-MgUserSignInSession` resolves before testing. Microsoft documents the command and module here: [Revoke-MgUserSignInSession](https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.users.actions/revoke-mgusersigninsession?view=graph-powershell-1.0).

Authenticate separately using an approved interactive method and the expected tenant. Review delegated consent and administrator roles for each stage. User creation/department changes require User.ReadWrite.All; group changes use GroupMember.ReadWrite.All, with Group.Read.All for group-property inspection. Account disablement can use User.EnableDisableAccount.All plus User.Read.All; session revocation uses User.RevokeSessions.All. Permissions alone do not grant the administrator every sensitive action. See [update user permissions](https://learn.microsoft.com/en-us/graph/api/user-update?view=graph-rest-1.0) and [session revocation](https://learn.microsoft.com/en-us/graph/api/user-revokesigninsessions?view=graph-rest-1.0). The workflow validates context and resources; API authorization remains enforced by Graph.

In PowerShell, from this directory:

```powershell
# Enter independently checked values privately. Nothing is stored to a file.
$settings = @{
    ExpectedTenantId = [guid](Read-Host 'Approved lab tenant GUID')
    ApprovedDomain = Read-Host 'Verified lab domain'
    UserPrincipalName = Read-Host 'Fresh Jordan Ellis lab UPN'
    ExpectedDisplayName = 'Jordan Ellis'
    SupportGroupId = [guid](Read-Host 'Approved SG-IT-Support GUID')
    DevelopersGroupId = [guid](Read-Host 'Approved SG-Developers GUID')
}
# Default: read-only preview, with no password prompt.
./Invoke-NovaTechJml.ps1 -Stage Joiner @settings
# After reviewing the preview, explicit directory writes:
./Invoke-NovaTechJml.ps1 -Stage Joiner @settings -Apply

# Independently verify Jordan's newly created object ID in Entra.
$settings.ExpectedUserId = [guid](Read-Host 'Verified Jordan Ellis object GUID')
./Invoke-NovaTechJml.ps1 -Stage Mover @settings
./Invoke-NovaTechJml.ps1 -Stage Mover @settings -Apply
./Invoke-NovaTechJml.ps1 -Stage Leaver @settings
./Invoke-NovaTechJml.ps1 -Stage Leaver @settings -Apply
```

Keep the account local part fresh, for example `jordan.ellis.jmltest`; choose the real approved test domain only at runtime. Repeat dry runs and apply after each successful stage to check already-completed handling. For a creation request that may have succeeded before an error, inspect the portal and pin the resulting ID before retrying. Do not blindly create another account.

## Portal fallback for offboarding

1. Sign in through an approved portal method. Keep Security Defaults enabled. Verify the tenant and the target's UPN, object ID and display name against the private approval record.
2. Block sign-in/disable the target; refresh and confirm Disabled. If this fails, record the failure and escalate while continuing other authorized containment steps.
3. Select Revoke sessions. Record the portal result and check the audit timestamp. Do not interpret acknowledgement as proof that all active tokens or application sessions have ended.
4. Remove the target from each approved lab group, then refresh both direct-member lists. Review other memberships and direct/application grants separately under their owners' authorization.
5. Check audit events and record which actions succeeded, failed or remain pending. Validate application behaviour with a controlled fresh test session where appropriate. Do not report complete offboarding while a required step is unresolved.

## Local checks and next live test

The [mock harness](Test-Workflow.ps1) supplies in-memory fake Graph commands; it makes no network requests. Run `pwsh -NoProfile -File ./Test-Workflow.ps1`. It checks default no-write behaviour, apply paths, repeat runs, wrong context/identity/group rejection, and continuation after a failed offboarding step. All 15 offline checks passed under PowerShell 7.6.9; no live Entra test has been performed.

A fresh live lab test still needs SDK import/command binding, consent and role checks, joiner creation and first-sign-in password behaviour, mover state, leaver acknowledgement and audit review, reruns, replication delays and a portal fallback rehearsal. Use a separate fictional identity and preserve Maya's completed evidence.
