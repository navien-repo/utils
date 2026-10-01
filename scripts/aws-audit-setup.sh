#!/usr/bin/env bash
# HAL · AWS
# Run in AWS CloudShell. Creates the read-only audit user hal-admin-sa and its
# access key. Writes hal-aws.json; nothing is sent anywhere.
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
    printf '  %s%s%s\n' "$B" "$line" "$X"
  done <<'HAL'
 _   _    _    _
| | | |  / \  | |
| |_| | / _ \ | |
|  _  |/ ___ \| |___
|_| |_/_/   \_\_____|
HAL
  printf '\n  %s%s%s\n  %ssomente leitura · nada sai deste terminal%s\n\n' "$B" "$1" "$X" "$D" "$X"
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
    [ -n "${SOFT:-}" ] || { printf '  %s%s%s %s\n' "$R" "$NO" "$X" "$label"; tail -n 8 "$LOG" | sed 's/^/      /'; }
    return 1
  fi
}
ok()   { printf '  %s%s%s %s\n' "$G" "$OK" "$X" "$1"; }
note() { printf '  %s·%s %s\n' "$D" "$X" "$1"; }
die()  { printf '\n  %s%s%s %s\n\n' "$R" "$NO" "$X" "$1" >&2; exit 1; }
rule() { printf '  %s' "$D"; for _ in $(seq 1 52); do printf '%s' "$RC"; done; printf '%s\n' "$X"; }
fact() { printf '   %s%-19s%s %s\n' "$D" "$1" "$X" "$2"; }
# ────────────────────────────────────────────────────────────────────────────

USER_NAME="hal-admin-sa"
OUT="hal-aws.json"
POLICIES="arn:aws:iam::aws:policy/SecurityAudit arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"

banner "AWS · usuário de auditoria"
command -v aws >/dev/null || die "Abra este script no AWS CloudShell: https://console.aws.amazon.com/cloudshell"

if aws iam get-user --user-name "$USER_NAME" >/dev/null 2>&1; then
  ok "Usuário $USER_NAME já existe"
else
  run "Criando o usuário $USER_NAME" aws iam create-user --user-name "$USER_NAME" --tags Key=Purpose,Value=HAL || exit 1
fi

attach() { for arn in $POLICIES; do aws iam attach-user-policy --user-name "$USER_NAME" --policy-arn "$arn" || return 1; done; }
run "Dando só permissão de leitura e auditoria" attach || exit 1

KEYS="$(aws iam list-access-keys --user-name "$USER_NAME" --query 'length(AccessKeyMetadata)' --output text)"
if [ "${KEYS:-0}" -ge 2 ]; then
  die "O usuário $USER_NAME já tem 2 chaves (o máximo da AWS). Apague uma em IAM > Usuários > $USER_NAME > Credenciais de segurança e rode de novo."
fi
rm -f "$OUT"
mkkey() { ( umask 077; aws iam create-access-key --user-name "$USER_NAME" --output json > "$OUT" ); }
run "Gerando a chave de acesso ($OUT)" mkkey || exit 1

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
if [ -n "${ACCOUNT:-}" ] && SOFT=1 run "Preparando um link de download temporário" prepare_link; then
  LINK="$(aws s3 presign "s3://$BUCKET/$OUT" --expires-in 3600 2>/dev/null || true)"
fi

printf '\n'; rule
printf '   %sPronto.%s\n\n' "$B" "$X"
fact "Identidade" "$USER_NAME"
fact "Acesso" "SecurityAudit · ViewOnlyAccess"
if [ -n "$LINK" ]; then
  printf '\n   %s1. Baixe a chave neste link%s %s(expira em 1h; o arquivo some em 1 dia)%s:\n\n' "$B" "$X" "$D" "$X"
  printf '      %s%s%s\n' "$C" "$LINK" "$X"
  printf '\n   %s2. Volte ao HAL%s e suba o %s baixado.\n' "$B" "$X" "$OUT"
else
  printf '   %sArquivo:%s %s\n' "$D" "$X" "$PWD/$OUT"
  printf '\n   %s1. Baixe o arquivo:%s Actions > Download file > %s%s%s\n' "$B" "$X" "$C" "$OUT" "$X"
  printf '   %s2. Volte ao HAL%s e suba o %s.\n' "$B" "$X" "$OUT"
fi
rule; printf '\n'
