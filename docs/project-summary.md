# Project Summary

## Objective

Build and test a small enterprise identity and access management environment for NovaTech, with evidence-based controls for identity lifecycle, role-based access, SAML SSO, Azure resource authorization, auditing, monitoring, offboarding, and access review.

## Final outcome

The lab demonstrated separation between support, security-read, and full-administration privileges; direct enterprise-application assignment; successful SAML configuration and troubleshooting; Reader versus temporary Contributor testing on Azure Storage; administrative audit investigation; monitoring/alerting; leaver offboarding; and a manual review of all five lab identities.

## Identities reviewed

- Harsh Chaudhary - lab administrator; Global Administrator and subscription Owner for the lab
- Daniel Lee - IT support/helpdesk persona; Helpdesk Administrator, application access, and final Azure Reader
- Sophia Patel - security monitoring persona; Security Reader and security-team membership
- Alice Morgan - security-team member persona; security-team membership only
- Ethan Wilson - finance/leaver persona; disabled with residual access removed

## Key security observations

- The lab administrator's standing Global Administrator plus subscription Owner access is appropriate for this single-user lab but would be a high-risk privilege concentration in production.
- Daniel's temporary Contributor elevation was removed and the final state returned to Reader.
- Ethan's offboarding target state removed authentication and residual entitlements.
- Native Access Reviews were unavailable, so governance was performed manually and recorded as a limitation.

