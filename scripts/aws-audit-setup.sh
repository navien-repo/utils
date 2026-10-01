#!/usr/bin/env bash
# HAL · AWS
# Run in AWS CloudShell. Creates the read-only audit user hal-admin-sa and its
# access key. Writes hal-aws.json; nothing is sent anywhere.
set -euo pipefail

USER_NAME="hal-admin-sa"
OUT="hal-aws.json"
POLICIES="arn:aws:iam::aws:policy/SecurityAudit arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"

step() { printf '\n[%s] %s\n' "$1" "$2"; }

command -v aws >/dev/null || { echo "Abra este comando no AWS CloudShell: https://console.aws.amazon.com/cloudshell"; exit 1; }

step 1/4 "Criando o usuario $USER_NAME"
if aws iam get-user --user-name "$USER_NAME" >/dev/null 2>&1; then
  echo "Ja existe. Vou usar esse."
else
  aws iam create-user --user-name "$USER_NAME" --tags Key=Purpose,Value=HAL >/dev/null
fi

step 2/4 "Dando so permissao de leitura e auditoria"
for arn in $POLICIES; do
  aws iam attach-user-policy --user-name "$USER_NAME" --policy-arn "$arn"
done

step 3/4 "Gerando a chave de acesso ($OUT)"
if [ "$(aws iam list-access-keys --user-name "$USER_NAME" --query 'length(AccessKeyMetadata)' --output text)" -ge 2 ]; then
  cat <<MSG
O usuario $USER_NAME ja tem 2 chaves de acesso (o maximo da AWS).
Apague uma em IAM > Usuarios > $USER_NAME > Credenciais de seguranca e rode de novo.
MSG
  exit 1
fi
rm -f "$OUT"
( umask 077; aws iam create-access-key --user-name "$USER_NAME" --output json > "$OUT" )

step 4/4 "Pronto"
cat <<MSG

Usuario : $USER_NAME (SecurityAudit + ViewOnlyAccess, somente leitura)
Arquivo : $PWD/$OUT

Baixe o arquivo: no CloudShell, Actions > Download file > $OUT.
Depois devolva-o ao HAL (botao "Subir o arquivo .json").
MSG
