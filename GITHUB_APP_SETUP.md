# GitHub App Setup for Coder

## Correct Callback URLs

When configuring your GitHub App for Coder, use these **exact** callback URLs:

### Primary OAuth (User Authentication)

```
https://coderdemo.io/api/v2/users/oauth2/github/callback
```

### External Auth (Git Operations in Workspaces)

```
https://coderdemo.io/api/v2/external-auth/primary-github/callback
```

## Important Settings

1. **Request user authorization (OAuth) during installation**: ✅ **MUST be checked**
   - This allows users to log into Coder with their GitHub identity

2. **Permissions Required**:
   - **Account permissions**:
     - Email addresses: Read-only
   - **Repository permissions**:
     - Contents: Read and write
     - Metadata: Read-only (auto-required)
     - Pull requests: Read and write (optional, for PR creation)
     - Issues: Read and write (optional, for issue management)

3. **Installation**:
   - Install the app to your account/organization
   - Grant access to "All repositories" or specific repos

## Common Issues

### "redirect_uri is not associated with this application"

- **Cause**: Callback URLs don't match what Coder is sending
- **Solution**: Verify the URLs above are **exactly** correct (including `/api/v2/users/` and `/api/v2/`)

### "Not HTTPS Secure" warning

- **Cause**: Accessing `http://coderdemo.io` instead of `https://coderdemo.io`
- **Solution**: Always use `https://` when accessing Coder

## After Setup

Once configured, users can:

- Log into Coder using GitHub authentication
- Clone repositories in their workspaces
- Push/pull code
- Create pull requests (if permissions granted)
