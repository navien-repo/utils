#!/usr/bin/env bash
# HAL · AWS
# Run in AWS CloudShell. Creates the read-only audit user hal-admin-sa and its
# access key. Writes hal-aws.json; nothing is sent anywhere.
#
#   bash <(curl -fsSL …/aws-audit-setup.sh)        Portuguese
#   bash <(curl -fsSL …/aws-audit-setup.sh) en     English (or HAL_LANG=en)
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

USER_NAME="hal-admin-sa"
OUT="hal-aws.json"
POLICIES="arn:aws:iam::aws:policy/SecurityAudit arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"

# ── words ───────────────────────────────────────────────────────────────────
if [ "$L" = en ]; then
  T_SUB="AWS · audit user"
  T_TAG="read-only · nothing leaves this terminal"
  T_NO_AWS="Open this script in AWS CloudShell: https://console.aws.amazon.com/cloudshell"
  T_USER_EXISTS="User %s already exists"
  T_USER="Creating the user %s"
  T_ATTACH="Granting read and audit permission only"
  T_TWO_KEYS="The user %s already has 2 keys (the AWS maximum). Delete one in IAM > Users > %s > Security credentials and run this again."
  T_KEY="Generating the access key (%s)"
  T_DONE="Done."
  T_F_IDENTITY="Identity"; T_F_ACCESS="Access"; T_F_FILE="File"
  T_LINK="Preparing a temporary download link"
  T_LINK_1="1. Download the key from this link"
  T_LINK_NOTE="(expires in 1h; the file is gone in 1 day)"
  T_BACK="2. Go back to HAL"
  T_BACK_LINK="and upload the %s you downloaded."
  T_MENU_1="1. Download the file:"
  T_BACK_MENU="and upload %s."
else
  T_SUB="AWS · usuário de auditoria"
  T_TAG="somente leitura · nada sai deste terminal"
  T_NO_AWS="Abra este script no AWS CloudShell: https://console.aws.amazon.com/cloudshell"
  T_USER_EXISTS="Usuário %s já existe"
  T_USER="Criando o usuário %s"
  T_ATTACH="Dando só permissão de leitura e auditoria"
  T_TWO_KEYS="O usuário %s já tem 2 chaves (o máximo da AWS). Apague uma em IAM > Usuários > %s > Credenciais de segurança e rode de novo."
  T_KEY="Gerando a chave de acesso (%s)"
  T_DONE="Pronto."
  T_F_IDENTITY="Identidade"; T_F_ACCESS="Acesso"; T_F_FILE="Arquivo"
  T_LINK="Preparando um link de download temporário"
  T_LINK_1="1. Baixe a chave neste link"
  T_LINK_NOTE="(expira em 1h; o arquivo some em 1 dia)"
  T_BACK="2. Volte ao HAL"
  T_BACK_LINK="e suba o %s baixado."
  T_MENU_1="1. Baixe o arquivo:"
  T_BACK_MENU="e suba o %s."
fi
# shellcheck disable=SC2059
say() { local format=$1; shift; printf "$format" "$@"; }
# ────────────────────────────────────────────────────────────────────────────

banner "$T_SUB" "$T_TAG"
command -v aws >/dev/null || die "$T_NO_AWS"

if aws iam get-user --user-name "$USER_NAME" >/dev/null 2>&1; then
  ok "$(say "$T_USER_EXISTS" "$USER_NAME")"
else
  run "$(say "$T_USER" "$USER_NAME")" aws iam create-user --user-name "$USER_NAME" --tags Key=Purpose,Value=HAL || exit 1
fi

attach() { for arn in $POLICIES; do aws iam attach-user-policy --user-name "$USER_NAME" --policy-arn "$arn" || return 1; done; }
run "$T_ATTACH" attach || exit 1

KEYS="$(aws iam list-access-keys --user-name "$USER_NAME" --query 'length(AccessKeyMetadata)' --output text)"
if [ "${KEYS:-0}" -ge 2 ]; then
  die "$(say "$T_TWO_KEYS" "$USER_NAME" "$USER_NAME")"
fi
rm -f "$OUT"
mkkey() { ( umask 077; aws iam create-access-key --user-name "$USER_NAME" --output json > "$OUT" ); }
run "$(say "$T_KEY" "$OUT")" mkkey || exit 1

# A clickable one-time download instead of the Actions menu (the user,
# 2026-10-01): put the key in a per-account scratch bucket whose objects
# self-delete after a day, keep the bucket private, and presign a short-lived
# GET link. The person's own CloudShell identity does this — not the read-only
# key just created. If any step is refused, fall back to the Download-file menu.
prepare_link() {
  if ! aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
    if [ "$REGION" = "us-east-1" ]; then
      aws s3api create-bucket --bucket "$BUCKET" --region us-east-1
    else
      aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" --create-bucket-configuration "LocationConstraint=$REGION"
    fi
  fi
  aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  aws s3api put-bucket-lifecycle-configuration --bucket "$BUCKET" --lifecycle-configuration '{"Rules":[{"ID":"expire-1d","Status":"Enabled","Filter":{"Prefix":""},"Expiration":{"Days":1}}]}'
  # Content-Disposition: attachment so the presigned link downloads the file
  # instead of opening the JSON inline in the browser (the user, 2026-10-01).
  aws s3 cp "$OUT" "s3://$BUCKET/$OUT" --content-type application/json --content-disposition "attachment; filename=$OUT" >/dev/null
}

ACCOUNT="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
BUCKET="hal-dl-${ACCOUNT}"
LINK=""
if [ -n "${ACCOUNT:-}" ] && SOFT=1 run "$T_LINK" prepare_link; then
  LINK="$(aws s3 presign "s3://$BUCKET/$OUT" --expires-in 3600 2>/dev/null || true)"
fi

printf '\n'; rule
printf '   %s%s%s\n\n' "$B" "$T_DONE" "$X"
fact "$T_F_IDENTITY" "$USER_NAME"
fact "$T_F_ACCESS" "SecurityAudit · ViewOnlyAccess"
if [ -n "$LINK" ]; then
  printf '\n   %s%s%s %s%s%s:\n\n' "$B" "$T_LINK_1" "$X" "$D" "$T_LINK_NOTE" "$X"
  printf '      %s%s%s\n' "$C" "$LINK" "$X"
  printf '\n   %s%s%s %s\n' "$B" "$T_BACK" "$X" "$(say "$T_BACK_LINK" "$OUT")"
else
  fact "$T_F_FILE" "$PWD/$OUT"
  printf '\n   %s%s%s Actions > Download file > %s%s%s\n' "$B" "$T_MENU_1" "$X" "$C" "$OUT" "$X"
  printf '   %s%s%s %s\n' "$B" "$T_BACK" "$X" "$(say "$T_BACK_MENU" "$OUT")"
fi
rule; printf '\n'
