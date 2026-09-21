# Okta companion guide

This guide configures Okta as the external identity provider for the NetBird embedded identity provider created by this module. It is written for the split-host deployment shown in the module example:

- Dashboard: `https://dashboard.netbird.example.com`
- Management and embedded IdP: `https://management.netbird.example.com`
- Embedded IdP issuer: `https://management.netbird.example.com/oauth2`
- Okta organization issuer: `https://example.okta.com`

Replace these names when using the module with different endpoints. Keep `local_auth_disabled = false` until the Okta-backed Owner account and client login have both been tested.

## What the Okta application provides

Create one confidential OIDC web application in Okta. NetBird uses its Authorization Code flow as an upstream identity provider. NetBird discovers Okta's authorization, token, and signing-key endpoints from the issuer.

This integration does not require:

- Okta Device Authorization grant
- Okta Client Credentials grant
- Okta API token or API scopes
- Implicit grant
- A custom Okta authorization server
- Trusted Origin or Sign-In Widget configuration

The optional discovery check below should return `https://example.okta.com` as the issuer:

```shell
curl -fsS "https://example.okta.com/.well-known/openid-configuration" |
  jq '{issuer, authorization_endpoint, token_endpoint, device_authorization_endpoint, jwks_uri}'
```

Enter only the issuer, `https://example.okta.com`, in NetBird. NetBird discovers the other endpoints. The presence of `device_authorization_endpoint` in discovery does not mean it must be enabled for this application; NetBird's embedded IdP handles the NetBird client login flow.

## Before creating the application

1. Confirm Management and Dashboard are healthy.
2. Open `https://dashboard.netbird.example.com` and sign in as the initial local Owner.
3. Keep that Owner session open until the Okta-backed account has been approved and tested.
4. In Okta, create dedicated assignment groups such as `NetBird-Users` and `NetBird-Administrators`.
5. Add only the initial test administrator to the appropriate group or groups.

## Open the two configuration forms

In the Okta Admin Console:

1. Open **Applications → Applications**.
2. Select **Create App Integration**.
3. Select **OIDC - OpenID Connect** and **Web Application**.
4. Continue to the **New Web App Integration** form, but do not save it yet.

In the existing local Owner session in NetBird:

1. Open **Settings → Identity Providers**.
2. Select **Add Identity Provider**.
3. Set **Provider Type** to **Okta**.
4. Set **Name** to `Okta`.
5. Set **Issuer URL** to `https://example.okta.com`.
6. Leave the NetBird dialog open. It displays the exact callback and logout URLs needed by Okta.

For the example deployment, the NetBird dialog displays:

```text
Redirect / Callback
https://management.netbird.example.com/oauth2/callback

Logout
https://management.netbird.example.com/oauth2/logout/callback
```

The Management hostname is intentional. The embedded IdP and its callback handlers run in Management; the Dashboard hostname is not the callback host.

If Okta shows an **Issuer** choice under the application's **Sign On** or **OpenID Connect ID Token** settings, select the fixed **Okta URL** or **Org URL** value `https://example.okta.com`. Do not select **Dynamic**. The issuer in Okta's tokens must exactly match the issuer configured in NetBird.

## Complete the current Okta form

On **New Web App Integration**, use these values:

| Okta field | Value |
| --- | --- |
| App integration name | `NetBird` |
| Require Demonstrating Proof of Possession (DPoP) | Unchecked |
| Core grants: Authorization Code | Checked |
| Core grants: Refresh Token | Unchecked |
| Allow wildcard `*` in sign-in URI redirect | Unchecked |
| Sign-in redirect URIs | `https://management.netbird.example.com/oauth2/callback` |
| Sign-out redirect URIs | `https://management.netbird.example.com/oauth2/logout/callback` |
| Trusted Origins: Base URIs | Empty |
| Controlled access | **Limit access to selected groups** |
| Selected group(s) | `NetBird-Users` and, if used separately, `NetBird-Administrators` |

Do not configure anything under **Advanced** for the initial integration. Use the callback and logout values copied from NetBird verbatim; do not add wildcards or change trailing slashes.

Select **Save**.

## Complete the NetBird provider

After Okta saves the application:

1. Open its **General** tab if Okta did not take you there automatically.
2. Find **Client Credentials**.
3. Copy the **Client ID**.
4. Copy the active **Client Secret**.
5. Return to the open NetBird **Add Identity Provider** dialog.
6. Enter the Client ID and Client Secret.
7. Recheck that **Issuer URL** is exactly `https://example.okta.com`, without `/.well-known/openid-configuration` or `/oauth2/default`.
8. Select **Add Provider**.

The client secret is stored by NetBird as embedded IdP connector data in PostgreSQL. It is not a Terraform or Secrets Manager input.

## Test and transfer ownership

1. Keep the original local Owner session open.
2. Open a private browser window and visit `https://dashboard.netbird.example.com`.
3. Select **Okta** and authenticate as the assigned test administrator.
4. Confirm Okta applies the expected MFA policy.
5. If NetBird reports that the user requires approval, return to the local Owner session.
6. Open **Team → Users**, approve the pending Okta-backed user, open that user, and transfer the Owner role to it.
7. Sign out of the private session and sign in again through Okta.
8. Confirm the Okta-backed user now has Owner access.
9. Enroll a test NetBird client and confirm its Management, Signal, and Relay connections.

Do not disable local authentication if any of these checks fail.

### User approval policy

For the first Okta login, return to the still-open local Owner session, leave **Settings**, and open **Team → Users**. The new Okta-backed user appears as pending; select **Approve** on that row. Complete the Owner transfer and verify a fresh Okta login before changing approval policy.

To rely on Okta assignment instead of approving every new user:

1. Sign in as the verified Okta-backed Owner.
2. Open **Settings → Authentication**.
3. Disable **User Approval Required** and save.
4. Keep the Okta application assigned only to the approved `NetBird-Users` and `NetBird-Administrators` groups.

The existing pending user may still require the one-time manual approval. Disabling approval controls subsequent users; do not depend on it to repair the bootstrap account.

Okta application assignment is the primary admission gate. After local authentication is disabled, optionally list `NetBird-Users` and `NetBird-Administrators` under **Settings → Groups → JWT allow groups** as a second gate. Do not enable that second gate during local-owner bootstrap because a local account has no Okta `groups` claim.

## Add an Okta groups claim

Group synchronization is optional for the first login. Configure it after the basic login works.

1. In Okta, open **Applications → Applications → NetBird**.
2. Open **Sign On**.
3. Find **Token claims** and expand **Show legacy configuration**.
4. Under **Group Claims**, select **Edit**.
5. Set **Groups claim type** to **Filter**.
6. In **Groups claim filter**, set the claim name to `groups`.
7. Select **Matches regex** and enter `^NetBird-.*`.
8. Save the group-claim configuration.
9. Do not add a separate expression under **Token claims**; the legacy **Group Claims** control creates the standard OIDC `groups` array expected here.
10. In NetBird, open **Settings → Groups**.
11. Enable **JWT group sync** and set **JWT claim** to `groups`.
12. Leave **JWT allow groups** empty during bootstrap. It is an access gate, not a synchronization filter: once populated, a user must carry at least one listed group in the JWT to access NetBird. The local Owner does not receive Okta group claims.
13. Enable **user group propagation** when Okta-synchronized groups should also be assigned to the user's peers for NetBird policy evaluation. Leave it disabled if peer groups will be managed independently. The example deployment enables it.
14. Select **Save Changes**.
15. Sign out and back in through Okta to obtain a new ID token, then verify the expected groups in NetBird.

The narrow prefix avoids disclosing unrelated Okta group memberships and reduces the chance of exceeding Okta's 100-group claim limit. Synchronized groups do not grant the NetBird Owner or Admin role; manage privileged NetBird roles explicitly.

After the Okta-backed Owner is verified and local authentication is disabled, optionally add `NetBird-Users` and `NetBird-Administrators` under **JWT allow groups** as a second access gate. Okta application assignment already restricts who can authenticate, so this is defense in depth rather than a prerequisite.

## Apply the Okta authentication policy

Use the organization's normal Okta policy process. In Okta Identity Engine, application policies are under **Security → Authentication Policies → App sign-in**. Apply a policy to `NetBird` that meets the required authentication strength, MFA, reauthentication, device, and risk requirements. Test the policy with the initial administrator before assigning more users.

## Disable local authentication

Only after the Okta-backed Owner and client login are working, set:

```hcl
local_auth_disabled = true
```

Plan and apply the Terragrunt configuration. Management restarts with the local email/password choice hidden. Verify Okta Owner login and client login once more.

Local accounts remain in PostgreSQL. Break-glass recovery requires setting `local_auth_disabled = false` and redeploying Management before a local account can sign in. Preserve the local credentials and the ability to perform that deployment.

## Owner continuity

NetBird permits exactly one Owner. IdP group synchronization does not assign NetBird roles, and an Admin cannot promote itself or another user to Owner. The Owner role adds two important powers beyond Admin: transferring ownership and deleting the organization. Admins otherwise have full operational access.

Do not leave ownership dependent on an ordinary employee account without an ownership-transfer control. Use one of these governance models:

1. **Named role holder:** assign Owner to a named Okta user, maintain at least two other named Admins, and make ownership transfer a mandatory step before that Owner is offboarded. This preserves individual attribution and is generally the cleaner audit model.
2. **Governed functional identity:** assign Owner to a dedicated Okta identity such as `netbird-owner@example.com`, use it only for Owner-only actions, protect it with phishing-resistant MFA, and control access through an audited privileged-access or credential-checkout process. Use this only if the organization's identity policy permits functional accounts.

Keep the original local bootstrap user as an additional break-glass Admin after ownership is transferred. With local authentication disabled, using it requires a reviewed Terraform change that re-enables local authentication and redeploys Management. It can restore normal administration, but as an Admin it cannot transfer ownership.

Review quarterly that the Owner identity is active and recoverable, at least two Okta-backed Admins can sign in, the local break-glass procedure still works, and the ownership-transfer procedure is part of offboarding.

## Lifecycle and audit considerations

This OIDC connector provides authentication and group claims, not SCIM provisioning. Removing an Okta assignment prevents future Okta authentication but does not automatically remove the NetBird user or its peers.

For offboarding:

1. Remove the user from the Okta application assignment group.
2. Revoke the user's Okta sessions as required by policy.
3. Block or remove the NetBird user.
4. Remove or expire associated peers and reusable setup keys where appropriate.
5. Retain Okta System Log and NetBird activity records according to the audit policy.

For client-secret rotation, create a replacement secret in Okta, update the provider in NetBird, test a new login, and retire the old secret only after the test succeeds.

## References

- [NetBird: Okta SSO with embedded IdP](https://docs.netbird.io/selfhosted/identity-providers/managed/okta)
- [NetBird: disable local authentication](https://docs.netbird.io/selfhosted/identity-providers/disable-local-authentication)
- [Okta: create an OIDC app integration](https://help.okta.com/en-us/content/topics/apps/apps_app_integration_wizard_oidc.htm)
- [Okta: assign an application to groups](https://help.okta.com/oie/en-us/Content/Topics/users-groups-profiles/usgp-assign-app-group.htm)
- [Okta: application sign-in policy rules](https://help.okta.com/oie/en-us/content/topics/identity-engine/policies/add-app-sign-on-policy-rule.htm)
