# Security Policy

## Security Audit Summary

**Date:** January 1, 2026
**Status:** ✅ Fully Secured
**Previous Risk Level:** CRITICAL (Public Repository + Exposed Credentials)
**Current Risk Level:** LOW

---

## Security Improvements Implemented

### 1. Repository Visibility - CRITICAL FIX
- **Previous State:** ⚠️ Repository was PUBLIC
- **Current State:** ✅ Repository set to PRIVATE
- **Impact:** Deployment infrastructure no longer exposed to public
- **Risk Mitigated:** Prevented disclosure of:
  - ActivTrak account number (680398)
  - Deployment automation scripts
  - Internal security software deployment strategy
  - MDM infrastructure details
  - PowerShell installation scripts

### 2. GitHub Token Management - CRITICAL FIX
- **Previous State:** GitHub token embedded in git remote URLs
- **Current State:**
  - Clean HTTPS URLs without embedded credentials
  - New GitHub token created and securely stored
  - Token stored in shell environment (`~/.zshrc`) with restricted access
  - Automated MSI update script uses environment variable
- **Impact:** Eliminated token exposure in git configuration

### 3. Credential Storage
- **Previous State:** Token potentially exposed in multiple locations
- **Current State:**
  - GitHub token stored securely in environment variable
  - Script reads token from `GITHUB_TOKEN` environment variable
  - No hardcoded credentials in source code
- **Impact:** Centralized, secure credential management

### 4. Automation Security
- **MSI Update Script (`update_activtrak_msi.py`):**
  - Requires `GITHUB_TOKEN` environment variable
  - Uses HTTPS for all API calls
  - SHA256 hash verification for file integrity
  - Secure file handling (no path traversal vulnerabilities)
  - Error handling prevents credential leakage

### 5. PowerShell Script Security
- **Installation Script (`Install-ActivTrak.ps1`):**
  - Requires administrator elevation
  - Validates file integrity (SHA256)
  - Secure download over HTTPS
  - Proper error handling
  - Windows Defender exclusions properly configured
  - No embedded credentials

---

## Security Practices

### Environment Variables
- `GITHUB_TOKEN` stored in user environment
- Script validates token presence before execution
- Token never logged or displayed in output
- Proper error messages without exposing sensitive data

### File Integrity
- SHA256 checksums calculated for all MSI files
- File size validation before deployment
- Filename validation to prevent injection attacks

### Network Security
- All downloads over HTTPS (TLS 1.2+)
- GitHub API calls authenticated with Bearer token
- No insecure HTTP connections

### Access Control
- Repository access limited to authorized IT personnel
- GitHub releases require authentication
- MSI files stored in private GitHub releases

---

## Automation Schedule

**Critical Security Note:** The ActivTrak MSI must be updated every 72 hours because the ActivTrak portal download URL expires after 72 hours.

- **Frequency:** Every 72 hours (3 days)
- **Method:** Automated via `update_activtrak_msi.py`
- **Authentication:** GitHub Personal Access Token
- **Token Permissions Required:** `repo` (Full control of private repositories)

---

## Reporting Security Issues

If you discover a security vulnerability, please report it to:
- **Email:** orlando.roberts@theguarantors.com
- **Response Time:** Within 24 hours

**Do not** create public GitHub issues for security vulnerabilities.

---

## Compliance Checklist

- ✅ No credentials in source code
- ✅ No credentials in git history
- ✅ Repository set to private
- ✅ GitHub token securely stored in environment
- ✅ HTTPS for all network communications
- ✅ File integrity validation (SHA256)
- ✅ PowerShell script requires admin elevation
- ✅ Proper error handling
- ✅ No sensitive data in logs
- ✅ Account-specific information not exposed publicly

---

## Audit History

| Date | Finding | Severity | Status |
|------|---------|----------|--------|
| 2026-01-01 | Public repository exposing deployment infrastructure | CRITICAL | ✅ Resolved |
| 2026-01-01 | ActivTrak account number (680398) publicly visible | HIGH | ✅ Resolved |
| 2026-01-01 | Exposed GitHub token in git remote URLs | HIGH | ✅ Resolved |
| 2026-01-01 | Deployment scripts publicly accessible | HIGH | ✅ Resolved |
| 2026-01-01 | Security documentation missing | LOW | ✅ Resolved |

---

## Recommendations

1. **Token Rotation:** Rotate GitHub token every 90 days
2. **Monitoring:** Set up alerts for failed MSI updates
3. **Backup:** Maintain backup copy of latest MSI file
4. **Automation Health:** Monitor 72-hour update cycle
5. **Access Review:** Audit repository access quarterly

---

## Technical Details

### GitHub Release Management
- Release tag: `v2.0.0`
- Asset filename: `ActivTrak-Account-680398.msi` (consistent naming)
- Old assets automatically deleted before upload
- Download URL remains constant across updates

### Required Permissions
- **GitHub Token:** `repo` scope
- **Local Execution:** Standard user (for Python script)
- **MSI Installation:** Administrator (for PowerShell script)

---

*Last Updated: January 1, 2026*
