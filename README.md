# utils

Setup scripts HAL's integration screens point people to. Each one runs in the
cloud's own browser shell, creates a read-only identity for HAL, and writes a
single JSON file. Nothing is sent anywhere: the person uploads the file in HAL.

| Script | Run it in | Writes |
| --- | --- | --- |
| `scripts/google-admin-setup.sh` | Google Cloud Shell | `hal-google-admin.json` (service account key) |
| `scripts/aws-audit-setup.sh` | AWS CloudShell | `hal-aws.json` (`aws iam create-access-key` answer) |

```bash
curl -fsSL https://raw.githubusercontent.com/navien-repo/utils/main/scripts/google-admin-setup.sh | bash
curl -fsSL https://raw.githubusercontent.com/navien-repo/utils/main/scripts/aws-audit-setup.sh | bash
```

The AWS user gets `SecurityAudit` and `ViewOnlyAccess` only. The Google service
account still needs domain-wide delegation, which a Workspace admin grants by
hand in the Admin console (HAL shows the client ID and scopes to authorize).
