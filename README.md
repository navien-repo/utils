# utils

Setup scripts HAL's integration screens point people to. Each one runs in the
cloud's own browser shell, creates a read-only identity for HAL, and writes a
single JSON file. Nothing is sent anywhere: the person uploads the file in HAL.

| Script | Run it in | Writes |
| --- | --- | --- |
| `scripts/google-admin-setup.sh` | Google Cloud Shell | `hal-google-admin.json` (service account key) |
| `scripts/aws-audit-setup.sh` | AWS CloudShell | `hal-aws.json` (`aws iam create-access-key` answer) |

Google: HAL opens Cloud Shell as a terminal only (no editor) with this repo
cloned and `print-google.txt` printed; the person types
`./create_hal_service_account` (`./hal-google` is the old name, kept as an alias).

The person has to check **Trust repo** in the dialog Cloud Shell shows before
opening: a repo Google does not own otherwise gets a temporary environment
without the person's credentials, and `gcloud` has no account there. Then
**Authorize** when Google asks. The script says so when it finds no account.
(Elastic's cloudbeat, ZenML and Langflow document the same two clicks.)

AWS CloudShell has no link with a script, so HAL shows the command to paste:

```bash
curl -fsSL https://raw.githubusercontent.com/navien-repo/utils/main/scripts/aws-audit-setup.sh | bash
```

The AWS user gets `SecurityAudit` and `ViewOnlyAccess` only. The Google service
account still needs domain-wide delegation, which a Workspace admin grants by
hand in the Admin console (HAL shows the client ID and scopes to authorize).
