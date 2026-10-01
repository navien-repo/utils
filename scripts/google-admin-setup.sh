#!/usr/bin/env bash
# HAL · Google Admin
# Run in Google Cloud Shell. Creates the HAL-Project project, the hal-admin-sa
# service account and the key file HAL reads Google Workspace with. Writes
# hal-google-admin.json; nothing is sent anywhere.
#
#   ./create_hal_service_account        Portuguese
#   ./create_hal_service_account en     English (or HAL_LANG=en)
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
# The language HAL's screen is in, passed as the first argument or HAL_LANG.
# The shell's own LANG says nothing about the person: Cloud Shell is en_US for all.
case "${1:-${HAL_LANG:-pt}}" in [Ee][Nn]*) L=en ;; *) L=pt ;; esac
LOG="$(mktemp)"
trap 'rm -f "$LOG"; printf "%s" "$X"' EXIT

banner() { # banner "<subtitle>" "<tagline>"
  printf '\n'
  while IFS= read -r line; do
    printf '  %s%s%s\n' "$B" "$line" "$X"
  done <<'HAL'
 _   _    _    _
| | | |  / \  | |
| |_| | / _ \ | |
|  _  |/ ___ \| |___
|_| |_/_/   \_\_____|
HAL
  printf '\n  %s%s%s\n  %s%s%s\n\n' "$B" "$1" "$X" "$D" "$2" "$X"
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
enter() { { read -r _ </dev/tty; } 2>/dev/null || true; }
# ────────────────────────────────────────────────────────────────────────────

NAME="HAL-Project"
BASE_ID="hal-project"
SA_NAME="hal-admin-sa"
OUT="hal-google-admin.json"
APIS="iam.googleapis.com admin.googleapis.com cloudidentity.googleapis.com licensing.googleapis.com alertcenter.googleapis.com"
# What keeps a service account from having a key: the managed constraint new
# organizations are born with (since 2024-05-03) and the legacy one before it.
KEY_CONSTRAINTS="iam.managed.disableServiceAccountKeyCreation iam.disableServiceAccountKeyCreation"
[ "$L" = en ] && RERUN="./create_hal_service_account en" || RERUN="./create_hal_service_account"

# ── words ───────────────────────────────────────────────────────────────────
if [ "$L" = en ]; then
  T_SUB="Google Admin · service account"
  T_TAG="read-only · nothing leaves this terminal"
  T_NO_GCLOUD="Open this script in Google Cloud Shell: https://shell.cloud.google.com"
  T_AUTHORIZE_1="Google needs to authorize this terminal to use your account."
  T_AUTHORIZE_2="In the %sAuthorize Cloud Shell%s window, click %sAuthorize%s."
  T_AUTHORIZE_3="Then press %sEnter%s here. "
  T_ACCOUNT="1/5  Google account: %s"
  T_PROJECT_EXISTS="2/5  Project %s already exists (%s)"
  T_PROJECT="2/5  Creating the project %s"
  T_APIS="3/5  Turning on the APIs HAL reads"
  T_SA_EXISTS="4/5  Service account %s already exists"
  T_SA="4/5  Creating the service account %s"
  T_KEY="5/5  Generating the key (%s)"
  T_DONE="STEP 1 done."
  T_DONE_REST="HAL's service account exists."
  T_F_ACCOUNT="Account"; T_F_CLIENT="Client ID"; T_F_FILE="File"; T_SEE_FILE="see the file"
  T_NEXT="Almost there"
  T_NEXT_2="2) Download the file %s%s%s. The download opens by itself:\n      click %sDownload%s in the window that appears."
  T_NEXT_3="3) Go back to HAL and click %sUpload the .json file%s."
  T_NEXT_4="4) Authorize the account in the Admin console. HAL shows the\n      client ID and the scopes once it has read the file."
  T_NO_DOWNLOAD="Download did not open? Three-dot menu at the top right > Download > %s"
  T_YES_NO="Type %sy%s for yes or %sn%s for no, then Enter: "
else
  T_SUB="Google Admin · conta de serviço"
  T_TAG="somente leitura · nada sai deste terminal"
  T_NO_GCLOUD="Abra este script no Google Cloud Shell: https://shell.cloud.google.com"
  T_AUTHORIZE_1="O Google precisa autorizar este terminal a usar a sua conta."
  T_AUTHORIZE_2="Na janela %sAuthorize Cloud Shell%s, clique em %sAuthorize%s."
  T_AUTHORIZE_3="Depois aperte %sEnter%s aqui. "
  T_ACCOUNT="1/5  Conta Google: %s"
  T_PROJECT_EXISTS="2/5  Projeto %s já existe (%s)"
  T_PROJECT="2/5  Criando o projeto %s"
  T_APIS="3/5  Ligando as APIs que o HAL lê"
  T_SA_EXISTS="4/5  Conta de serviço %s já existe"
  T_SA="4/5  Criando a conta de serviço %s"
  T_KEY="5/5  Gerando a chave (%s)"
  T_DONE="PASSO 1 concluído."
  T_DONE_REST="A conta de serviço do HAL existe."
  T_F_ACCOUNT="Conta"; T_F_CLIENT="ID do cliente"; T_F_FILE="Arquivo"; T_SEE_FILE="veja no arquivo"
  T_NEXT="Falta pouco"
  T_NEXT_2="2) Baixe o arquivo %s%s%s. O download abre sozinho:\n      clique em %sDownload%s na janela que aparecer."
  T_NEXT_3="3) Volte ao HAL e clique em %sSubir o arquivo .json%s."
  T_NEXT_4="4) Autorize a conta no Admin console. O HAL mostra o\n      ID do cliente e os escopos depois de ler o arquivo."
  T_NO_DOWNLOAD="O download não abriu? Menu de três pontos no alto à direita > Download > %s"
  T_YES_NO="Digite %sy%s para sim ou %sn%s para não, e Enter: "
fi
# shellcheck disable=SC2059
say() { local format=$1; shift; printf "$format" "$@"; }
# ────────────────────────────────────────────────────────────────────────────

banner "$T_SUB" "$T_TAG"
command -v gcloud >/dev/null || die "$T_NO_GCLOUD"

# The first gcloud call runs attached to the terminal, nothing redirected, the
# way the scripts this one follows do it (Elastic's cloudbeat): Cloud Shell asks
# for its Authorize click on the first credentialed call of a session, and a
# call hidden behind a log file never got it. Its own error stays on screen.
authed() { gcloud projects list --limit=1 --format=none; }
# A terminal still without the account is a stale Cloud Shell session: nothing
# to sign in to, only a session to close. Enter closes it — the script hangs up
# the shell that ran it, which only a Cloud Shell terminal is asked to do.
no_account() {
  if [ "$L" = en ]; then cat <<MSG

  ${Y}!${X} ${B}This terminal lost your Google account.${X}

    You do not need to sign in again. It is an old Cloud Shell
    session.

    Press ${B}Enter${X}: this session will be closed. Then just click
    ${B}Open Google Cloud Shell${X} in HAL again.

MSG
  else cat <<MSG

  ${Y}!${X} ${B}Este terminal ficou sem a sua conta Google.${X}

    Você não precisa fazer login de novo. É uma sessão antiga do
    Cloud Shell.

    Aperte ${B}Enter${X}: esta sessão será fechada. Depois é só clicar de
    novo em ${B}Abrir o Google Cloud Shell${X} no HAL.

MSG
  fi
  enter
  [ -n "${CLOUD_SHELL:-}" ] && [ -t 1 ] && kill -HUP "$PPID" 2>/dev/null
  exit 1
}
if ! authed; then
  printf '\n  %s!%s %s\n\n     ' "$Y" "$X" "$T_AUTHORIZE_1"
  say "$T_AUTHORIZE_2" "$B" "$X" "$B" "$X"; printf '\n     '
  say "$T_AUTHORIZE_3" "$B" "$X"
  enter
  printf '\n'
  authed || no_account
fi
ok "$(say "$T_ACCOUNT" "$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -n1)")"

PROJECT_ID="$(gcloud projects list --filter="name=$NAME AND lifecycleState=ACTIVE" --format='value(projectId)' --limit=1 2>/dev/null || true)"
if [ -n "$PROJECT_ID" ]; then
  ok "$(say "$T_PROJECT_EXISTS" "$NAME" "$PROJECT_ID")"
else
  PROJECT_ID="$BASE_ID"
  if ! SOFT=1 run "$(say "$T_PROJECT" "$NAME")" gcloud projects create "$PROJECT_ID" --name="$NAME"; then
    # The id is global to Google; if somebody else holds it, take a suffixed one.
    PROJECT_ID="$BASE_ID-$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')"
    run "$(say "$T_PROJECT" "$NAME") ($PROJECT_ID)" gcloud projects create "$PROJECT_ID" --name="$NAME" || exit 1
  fi
fi
gcloud config set project "$PROJECT_ID" >/dev/null 2>&1

# shellcheck disable=SC2086
run "$T_APIS" gcloud services enable $APIS --project="$PROJECT_ID" || exit 1

SA_EMAIL="$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com"
if gcloud iam service-accounts describe "$SA_EMAIL" >/dev/null 2>&1; then
  ok "$(say "$T_SA_EXISTS" "$SA_NAME")"
else
  run "$(say "$T_SA" "$SA_NAME")" gcloud iam service-accounts create "$SA_NAME" --display-name="HAL" --description="HAL reads Google Workspace, read-only" || exit 1
  sleep 5 # the account takes a moment to be visible to the key call
fi

# The organization forbids service account keys. With a yes, the script lifts
# the rule on this one project (an override; the organization keeps it) and
# stops: Google takes up to 15 minutes to apply it, and the next run only has
# the key left to make.
allow_keys() {
  local constraint file done=''
  gcloud services enable orgpolicy.googleapis.com --project="$PROJECT_ID" || true
  for constraint in $KEY_CONSTRAINTS; do
    file="$(mktemp)"
    printf 'name: projects/%s/policies/%s\nspec:\n  rules:\n  - enforce: false\n' "$PROJECT_ID" "$constraint" > "$file"
    if gcloud org-policies set-policy "$file"; then done=1; fi
    rm -f "$file"
  done
  [ -n "$done" ]
}
keys_already_allowed() {
  local constraint
  for constraint in $KEY_CONSTRAINTS; do
    gcloud org-policies describe "$constraint" --project="$PROJECT_ID" 2>/dev/null | grep -q 'enforce: false' && return 0
  done
  return 1
}
key_blocked() {
  printf '  %s%s%s %s\n' "$Y" "$NO" "$X" "$KEY_LABEL"
  if keys_already_allowed; then
    if [ "$L" = en ]; then cat <<MSG

  ${Y}!${X} ${B}Key creation is already authorized for this project,${X}
    but Google has not applied it yet (it takes up to 15 minutes).

    Wait a few minutes and run ${B}$RERUN${X} again.

MSG
    else cat <<MSG

  ${Y}!${X} ${B}A criação de chaves já está autorizada neste projeto,${X}
    mas o Google ainda não aplicou (leva até 15 minutos).

    Espere alguns minutos e rode ${B}$RERUN${X} de novo.

MSG
    fi
    exit 1
  fi
  if [ "$L" = en ]; then cat <<MSG

  ${Y}!${X} ${B}Your organization's policy blocks service account keys.${X}

    Authorize key creation? It is safe: the exception is for the
    ${B}$NAME${X} project only. The rest of your organization
    stays blocked.

MSG
  else cat <<MSG

  ${Y}!${X} ${B}A política da sua organização bloqueia chaves de conta de serviço.${X}

    Autoriza a criação? É seguro: a exceção vale só para o projeto
    ${B}$NAME${X}. O resto da sua organização continua bloqueado.

MSG
  fi
  local answer=''
  while :; do
    printf '    '; say "$T_YES_NO" "$B" "$X" "$B" "$X"
    { read -r answer </dev/tty; } 2>/dev/null || answer=n
    case "$answer" in [YySs]*) break ;; [Nn]*) answer=n; break ;; esac
  done
  printf '\n'
  if [ "$answer" = n ]; then
    [ "$L" = en ] && die "Nothing was changed. Without the key HAL cannot read Google Workspace; run $RERUN when you want to authorize it."
    die "Nada foi alterado. Sem a chave o HAL não lê o Google Workspace; rode $RERUN quando quiser autorizar."
  fi
  local label="Autorizando chaves só no projeto $NAME"
  [ "$L" = en ] && label="Authorizing keys on the $NAME project only"
  if ! run "$label" allow_keys; then
    if [ "$L" = en ]; then cat <<MSG

    Your account cannot change the organization's policy: it needs the
    ${B}Organization Policy Administrator${X} role (roles/orgpolicy.policyAdmin)
    on the organization. Whoever manages it in Google Cloud can grant you
    the role, or allow keys on project ${B}$PROJECT_ID${X} in
    IAM & Admin > Organization Policies > Disable service account key creation.
    Then run ${B}$RERUN${X} again.

MSG
    else cat <<MSG

    Sua conta não pode mudar a política da organização: falta o papel
    ${B}Administrador de políticas da organização${X} (roles/orgpolicy.policyAdmin)
    na organização. Quem a administra no Google Cloud pode dar o papel a
    você, ou liberar as chaves no projeto ${B}$PROJECT_ID${X} em
    IAM e administrador > Políticas da organização > Desativar a criação de
    chaves de contas de serviço. Depois rode ${B}$RERUN${X} de novo.

MSG
    fi
    exit 1
  fi
  if [ "$L" = en ]; then cat <<MSG

  ${G}$OK${X} ${B}Authorized.${X}

    Google takes up to ${B}15 minutes${X} to apply it. After that, run
    ${B}$RERUN${X} again: only the key is left to generate.

MSG
  else cat <<MSG

  ${G}$OK${X} ${B}Autorizado.${X}

    O Google leva até ${B}15 minutos${X} para aplicar. Depois disso, rode
    ${B}$RERUN${X} de novo: só falta gerar a chave.

MSG
  fi
  exit 0
}

KEY_LABEL="$(say "$T_KEY" "$OUT")"
rm -f "$OUT"
if ! SOFT=1 run "$KEY_LABEL" gcloud iam service-accounts keys create "$OUT" --iam-account="$SA_EMAIL"; then
  grep -qiE 'FAILED_PRECONDITION|constraint|disableServiceAccountKeyCreation' "$LOG" && key_blocked
  printf '  %s%s%s %s\n' "$R" "$NO" "$X" "$KEY_LABEL"; shown "$LOG"
  exit 1
fi
chmod 600 "$OUT"
CLIENT_ID="$(jq -r .client_id "$OUT" 2>/dev/null || true)"

printf '\n'; rule
printf '   %s%s%s %s\n\n' "$B" "$T_DONE" "$X" "$T_DONE_REST"
fact "$T_F_ACCOUNT" "$SA_EMAIL"
fact "$T_F_CLIENT" "${CLIENT_ID:-$T_SEE_FILE}"
fact "$T_F_FILE" "$PWD/$OUT"
printf '\n   %s%s%s\n\n   ' "$B" "$T_NEXT" "$X"
say "$T_NEXT_2" "$B" "$OUT" "$X" "$B" "$X"; printf '\n   '
say "$T_NEXT_3" "$B" "$X"; printf '\n   '
say "$T_NEXT_4"; printf '\n'
rule; printf '\n'

if command -v cloudshell >/dev/null; then
  cloudshell download "$OUT" || note "$(say "$T_NO_DOWNLOAD" "$OUT")"
fi
