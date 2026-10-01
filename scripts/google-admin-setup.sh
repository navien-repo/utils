#!/usr/bin/env bash
# HAL · Google Admin
# Run in Google Cloud Shell. Creates the HAL-Project project, the hal-admin-sa
# service account and the key file HAL reads Google Workspace with.
# Writes hal-google-admin.json; nothing is sent anywhere.
set -euo pipefail

NAME="HAL-Project"
BASE_ID="hal-project"
SA_NAME="hal-admin-sa"
OUT="hal-google-admin.json"
APIS="iam.googleapis.com admin.googleapis.com cloudidentity.googleapis.com licensing.googleapis.com alertcenter.googleapis.com"

step() { printf '\n[%s] %s\n' "$1" "$2"; }

command -v gcloud >/dev/null || { echo "Abra este comando no Google Cloud Shell: https://shell.cloud.google.com"; exit 1; }

step 1/5 "Procurando o projeto $NAME"
PROJECT_ID="$(gcloud projects list --filter="name=$NAME AND lifecycleState=ACTIVE" --format='value(projectId)' --limit=1 2>/dev/null || true)"
if [ -n "$PROJECT_ID" ]; then
  echo "Ja existe ($PROJECT_ID). Vou usar esse."
else
  PROJECT_ID="$BASE_ID"
  if ! gcloud projects create "$PROJECT_ID" --name="$NAME" 2>/dev/null; then
    # The id is global to Google; if somebody else holds it, take a suffixed one.
    PROJECT_ID="$BASE_ID-$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 5)"
    gcloud projects create "$PROJECT_ID" --name="$NAME"
  fi
  echo "Projeto criado ($PROJECT_ID)."
fi
gcloud config set project "$PROJECT_ID" >/dev/null

step 2/5 "Ligando as APIs que o HAL le"
# shellcheck disable=SC2086
gcloud services enable $APIS --project="$PROJECT_ID"

step 3/5 "Criando a conta de servico $SA_NAME"
SA_EMAIL="$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com"
if gcloud iam service-accounts describe "$SA_EMAIL" >/dev/null 2>&1; then
  echo "Ja existe. Vou usar essa."
else
  gcloud iam service-accounts create "$SA_NAME" --display-name="HAL" --description="HAL reads Google Workspace, read-only"
  sleep 5 # the account takes a moment to be visible to the key call
fi

step 4/5 "Gerando o arquivo da chave ($OUT)"
rm -f "$OUT"
if ! gcloud iam service-accounts keys create "$OUT" --iam-account="$SA_EMAIL" 2>"$OUT.err"; then
  if grep -qiE 'FAILED_PRECONDITION|constraint|disableServiceAccountKeyCreation' "$OUT.err"; then
    cat <<MSG

Sua organizacao do Google bloqueia a criacao de chaves de conta de servico
(politica iam.disableServiceAccountKeyCreation, ligada por padrao em contas novas).
Quem administra a organizacao pode liberar SO este projeto com:

  gcloud resource-manager org-policies disable-enforce iam.disableServiceAccountKeyCreation --project=$PROJECT_ID

(precisa do papel "Administrador de politica da organizacao"). Depois rode este comando de novo.
MSG
  else
    cat "$OUT.err"
  fi
  rm -f "$OUT.err" "$OUT"
  exit 1
fi
rm -f "$OUT.err"
chmod 600 "$OUT"

step 5/5 "Pronto"
CLIENT_ID="$(jq -r .client_id "$OUT" 2>/dev/null || true)"
cat <<MSG

Conta de servico : $SA_EMAIL
ID do cliente    : ${CLIENT_ID:-veja no arquivo}
Arquivo          : $PWD/$OUT

Falta so devolver o arquivo ao HAL (botao "Subir o arquivo .json").
O HAL mostra o ID do cliente e os escopos para voce autorizar no Admin console.
MSG

if command -v cloudshell >/dev/null; then
  cloudshell download "$OUT" || echo "Se o download nao comecou: menu no alto a direita > Download > $OUT"
fi
