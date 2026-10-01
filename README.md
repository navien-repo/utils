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

Both scripts speak Portuguese by default and English with `en` as the first
argument (or `HAL_LANG=en`): `./create_hal_service_account en`,
`bash <(curl …/aws-audit-setup.sh) en`. HAL passes the language of its own
screen; the shell's `LANG` is not read, Cloud Shell is `en_US` for everyone.
`print-google.txt` and `print-google.en.txt` are the two printed hints.

If the organization forbids service account keys (the default since 2024-05-03,
`iam.managed.disableServiceAccountKeyCreation`), the Google script asks y/n and
overrides the constraint on the HAL project only; Google takes up to 15 minutes
to apply it, so the script stops there and the next run generates the key.

The AWS user gets `SecurityAudit` and `ViewOnlyAccess` only. The Google service
account still needs domain-wide delegation, which a Workspace admin grants by
hand in the Admin console (HAL shows the client ID and scopes to authorize).
