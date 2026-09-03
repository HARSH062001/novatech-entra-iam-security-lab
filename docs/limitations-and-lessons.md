# Limitations and Lessons Learned

- Native Identity Governance Access Reviews were unavailable in the tenant; manual access review was used instead.
- Conditional Access implementation is not claimed as completed evidence.
- PowerShell/Graph inventory automation, Jira approvals, separation-of-duties workflows, and emergency-access design remain future enhancements.
- SAML troubleshooting showed that ACS/Reply URL, sign-on URL, NameID format, and user assignment must align with the service provider's exact requirements.
- Activity Log and change history were treated as authoritative evidence for confirmed saved administrative changes.
- A production design should separate daily and administrative identities and use just-in-time privileged access where licensing permits.

