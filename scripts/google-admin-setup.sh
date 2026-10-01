#!/usr/bin/env bash
# HAL · Google Admin
# Run in Google Cloud Shell. Creates the HAL-Project project, the hal-admin-sa
# service account and the key file HAL reads Google Workspace with. Writes
# hal-google-admin.json; nothing is sent anywhere.
set -euo pipefail

# ── terminal UI (the same block in every HAL script) ────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  B=$'\033[1m'; D=$'\033[2m'; R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; C=$'\033[36m'; X=$'\033[0m'
else
  B=''; D=''; R=''; G=''; Y=''; C=''; X=''
fi
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
  *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) OK='✓'; NO='✗'; RC='─'; SPIN='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' ;;
  *) OK='+'; NO='x'; RC='-'; SPIN='|/-\' ;;
esac
LOG="$(mktemp)"
trap 'rm -f "$LOG"; printf "%s" "$X"' EXIT

banner() { # banner "<subtitle>"
  printf '\n'
  while IFS= read -r line; do
    line=${line//\{/$R}; line=${line//\}/$X}; line=${line//</$B}; line=${line//>/$X}
    printf '  %s%s\n' "$line" "$X"
  done <<EYE
      .-""""""""-.
   .-'  .------.  '-.
  /    /  .--.  \    \     <H  A  L>
 |    |  { (  ) }  |    |   $1
  \    \  '--'  /    /     ${D}read-only · nothing leaves this terminal${X}
   '-.  '------'  .-'
      '-........-'
EYE
  printf '\n'
}

# run "label" cmd args…   a step with a spinner; on failure shows the last lines
# (SOFT=1 keeps the failure quiet, for a step the script retries on its own).
run() {
  local label=$1 i=0; shift
  ( "$@" ) >"$LOG" 2>&1 &
  local pid=$!
  if [ -t 1 ]; then
    while kill -0 "$pid" 2>/dev/null; do
      printf '\r  %s%s%s %s' "$C" "${SPIN:$((i++ % ${#SPIN})):1}" "$X" "$label"
      sleep 0.1
    done
    printf '\r\033[K'
  fi
  if wait "$pid"; then
    printf '  %s%s%s %s\n' "$G" "$OK" "$X" "$label"
  else
    [ -n "${SOFT:-}" ] || { printf '  %s%s%s %s\n' "$R" "$NO" "$X" "$label"; shown "$LOG"; }
    return 1
  fi
}
shown() { grep -v '^[[:space:]]*$' "$1" | tail -n 12 | sed 's/^[[:space:]]*/      /'; }
ok()   { printf '  %s%s%s %s\n' "$G" "$OK" "$X" "$1"; }
note() { printf '  %s·%s %s\n' "$D" "$X" "$1"; }
die()  { printf '\n  %s%s%s %s\n\n' "$R" "$NO" "$X" "$1" >&2; exit 1; }
rule() { printf '  %s' "$D"; for _ in $(seq 1 52); do printf '%s' "$RC"; done; printf '%s\n' "$X"; }
fact() { printf '   %s%-19s%s %s\n' "$D" "$1" "$X" "$2"; }
# ────────────────────────────────────────────────────────────────────────────

NAME="HAL-Project"
BASE_ID="hal-project"
SA_NAME="hal-admin-sa"
OUT="hal-google-admin.json"
APIS="iam.googleapis.com admin.googleapis.com cloudidentity.googleapis.com licensing.googleapis.com alertcenter.googleapis.com"

banner "Google Admin · conta de serviço"
command -v gcloud >/dev/null || die "Abra este script no Google Cloud Shell: https://shell.cloud.google.com"

# The Cloud Shell token may be missing or expired; every later step would fail
# with a cut-off message. Check it first and sign in right here if needed.
if ! gcloud projects list --limit=1 >"$LOG" 2>&1; then
  if grep -qiE 'credential|reauth|log ?in|active account|authenticat' "$LOG"; then
    note "O Cloud Shell ainda não autorizou sua conta. Vou pedir o login."
    printf '\n'
    gcloud auth login --no-launch-browser --quiet || die "Login não concluído. Rode ./hal-google de novo."
    printf '\n'
    gcloud projects list --limit=1 >"$LOG" 2>&1 || { shown "$LOG"; die "Sem acesso ao Google Cloud com essa conta."; }
  else
    shown "$LOG"; die "Não consegui falar com o Google Cloud."
  fi
fi
ok "Conta $(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -n1)"

PROJECT_ID="$(gcloud projects list --filter="name=$NAME AND lifecycleState=ACTIVE" --format='value(projectId)' --limit=1 2>/dev/null || true)"
if [ -n "$PROJECT_ID" ]; then
  ok "Projeto $NAME já existe ($PROJECT_ID)"
else
  PROJECT_ID="$BASE_ID"
  if ! SOFT=1 run "Criando o projeto $NAME" gcloud projects create "$PROJECT_ID" --name="$NAME"; then
    # The id is global to Google; if somebody else holds it, take a suffixed one.
    PROJECT_ID="$BASE_ID-$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')"
    run "Criando o projeto $NAME ($PROJECT_ID)" gcloud projects create "$PROJECT_ID" --name="$NAME" || exit 1
  fi
fi
gcloud config set project "$PROJECT_ID" >/dev/null 2>&1

# shellcheck disable=SC2086
run "Ligando as APIs que o HAL lê" gcloud services enable $APIS --project="$PROJECT_ID" || exit 1

SA_EMAIL="$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com"
if gcloud iam service-accounts describe "$SA_EMAIL" >/dev/null 2>&1; then
  ok "Conta de serviço $SA_NAME já existe"
else
  run "Criando a conta de serviço $SA_NAME" gcloud iam service-accounts create "$SA_NAME" --display-name="HAL" --description="HAL reads Google Workspace, read-only" || exit 1
  sleep 5 # the account takes a moment to be visible to the key call
fi

rm -f "$OUT"
if ! SOFT=1 run "Gerando a chave ($OUT)" gcloud iam service-accounts keys create "$OUT" --iam-account="$SA_EMAIL"; then
  if grep -qiE 'FAILED_PRECONDITION|constraint|disableServiceAccountKeyCreation' "$LOG"; then
    printf '  %s%s%s %s\n' "$Y" "$NO" "$X" "Gerando a chave ($OUT)"
    cat <<MSG

  ${Y}Sua organização do Google bloqueia chaves de conta de serviço${X}
  (política iam.disableServiceAccountKeyCreation, ligada por padrão em
  organizações novas). Quem administra a organização libera SÓ este
  projeto com:

    ${B}gcloud resource-manager org-policies disable-enforce \\
      iam.disableServiceAccountKeyCreation --project=$PROJECT_ID${X}

  (precisa do papel "Administrador de política da organização").
  Depois rode este script de novo.

MSG
    exit 1
  fi
  printf '  %s%s%s %s\n' "$R" "$NO" "$X" "Gerando a chave ($OUT)"; shown "$LOG"
  exit 1
fi
chmod 600 "$OUT"
CLIENT_ID="$(jq -r .client_id "$OUT" 2>/dev/null || true)"

printf '\n'; rule
printf '   %sPronto.%s\n\n' "$B" "$X"
fact "Conta" "$SA_EMAIL"
fact "ID do cliente" "${CLIENT_ID:-veja no arquivo}"
fact "Arquivo" "$PWD/$OUT"
printf '\n   Devolva o arquivo ao HAL: botão %sSubir o arquivo .json%s.\n' "$B" "$X"
rule; printf '\n'

if command -v cloudshell >/dev/null; then
  cloudshell download "$OUT" || note "Se o download não começou: menu no alto à direita > Download > $OUT"
fi
