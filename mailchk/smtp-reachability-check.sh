#!/usr/bin/env bash

# Check whether a remote SMTP server accepts a recipient at the RCPT TO stage.
# No message body is sent. Acceptance is evidence, not proof, that a mailbox exists.

set -u
set -o pipefail
export LC_ALL=C

PROGRAM=${0##*/}
PORT=25
CONNECT_TIMEOUT=12
READ_TIMEOUT=12
HELO_NAME=""
MAIL_FROM=""
TARGET_EMAIL=""
SMTP_CODE=""

usage() {
  cat <<EOF
Usage: $PROGRAM [options] [email]

Resolve the recipient domain's MX records and perform an SMTP envelope probe.
If email is omitted, the script prompts for it.

Options:
  -f, --from ADDRESS       Envelope sender (default: empty reverse-path <>)
  -H, --helo HOSTNAME      EHLO/HELO name (default: this machine's FQDN)
  -c, --connect-timeout N  TCP connection timeout in seconds (default: 12)
  -r, --read-timeout N     Timeout for each SMTP response (default: 12)
  -h, --help               Show this help

Exit status:
  0  RCPT accepted (not proof that the mailbox exists)
  1  RCPT permanently rejected
  2  Inconclusive, temporary error, or no reachable SMTP server
  64 Invalid input or missing dependency
  69 Domain explicitly accepts no mail (Null MX) or has no mail endpoint
EOF
}

die_usage() {
  printf 'Error: %s\n' "$1" >&2
  printf 'Run %s --help for usage.\n' "$PROGRAM" >&2
  exit 64
}

valid_timeout() {
  [[ $1 =~ ^[1-9][0-9]*$ ]] && (( $1 <= 300 ))
}

valid_domain() {
  local domain=$1 label rest
  (( ${#domain} <= 253 )) || return 1
  [[ $domain =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || return 1
  [[ $domain != *..* ]] || return 1
  rest=$domain
  while :; do
    label=${rest%%.*}
    (( ${#label} >= 1 && ${#label} <= 63 )) || return 1
    [[ $label != -* && $label != *- ]] || return 1
    [[ $rest == *.* ]] || break
    rest=${rest#*.}
  done
}

parse_email() {
  local email=$1 localpart domain
  (( ${#email} <= 254 )) || return 1
  [[ $email != *[$'\r\n\t ']* && $email != *'<'* && $email != *'>'* ]] || return 1
  [[ $email == *@* ]] || return 1
  localpart=${email%@*}
  domain=${email##*@}
  [[ -n $localpart && $localpart != *@* && ${#localpart} -le 64 ]] || return 1
  [[ $localpart =~ ^[!-~]+$ ]] || return 1
  valid_domain "$domain" || return 1
  printf '%s\n' "${domain%.}"
}

while (( $# > 0 )); do
  case $1 in
    -f|--from)
      (( $# >= 2 )) || die_usage "$1 requires an address"
      MAIL_FROM=$2
      shift 2
      ;;
    -H|--helo)
      (( $# >= 2 )) || die_usage "$1 requires a hostname"
      HELO_NAME=$2
      shift 2
      ;;
    -c|--connect-timeout)
      (( $# >= 2 )) || die_usage "$1 requires a number"
      CONNECT_TIMEOUT=$2
      shift 2
      ;;
    -r|--read-timeout)
      (( $# >= 2 )) || die_usage "$1 requires a number"
      READ_TIMEOUT=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*) die_usage "unknown option: $1" ;;
    *)
      [[ -z $TARGET_EMAIL ]] || die_usage "only one recipient may be checked"
      TARGET_EMAIL=$1
      shift
      ;;
  esac
done

(( $# == 0 )) || die_usage "unexpected argument: $1"

command -v dig >/dev/null 2>&1 || die_usage "'dig' is required (package: dnsutils or bind-tools)"
command -v nc >/dev/null 2>&1 || die_usage "'nc' is required (package: netcat or nmap-ncat)"
(( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 1) )) || \
  die_usage "Bash 4.1 or newer is required"
valid_timeout "$CONNECT_TIMEOUT" || die_usage "connect timeout must be an integer from 1 to 300"
valid_timeout "$READ_TIMEOUT" || die_usage "read timeout must be an integer from 1 to 300"

if [[ -z $TARGET_EMAIL ]]; then
  read -r -p "Email address to probe: " TARGET_EMAIL
fi

DOMAIN=$(parse_email "$TARGET_EMAIL") || die_usage "invalid or unsupported ASCII email address"

if [[ -z $HELO_NAME ]]; then
  HELO_NAME=$(hostname -f 2>/dev/null || hostname 2>/dev/null || printf 'localhost')
fi
HELO_NAME=${HELO_NAME%.}
valid_domain "$HELO_NAME" || die_usage "EHLO/HELO name is not a valid ASCII hostname"

if [[ -n $MAIL_FROM ]]; then
  parse_email "$MAIL_FROM" >/dev/null || die_usage "envelope sender is not a valid supported ASCII email address"
  MAIL_FROM_CMD="<$MAIL_FROM>"
else
  MAIL_FROM_CMD="<>"
fi

printf 'Recipient : %s\n' "$TARGET_EMAIL"
printf 'Domain    : %s\n' "$DOMAIN"
printf 'HELO name : %s\n' "$HELO_NAME"
printf 'MAIL FROM : %s\n\n' "$MAIL_FROM_CMD"

MX_RECORDS=$(dig +time=5 +tries=1 +short MX "$DOMAIN" 2>/dev/null)
MX_HOSTS=()

if [[ -n $MX_RECORDS ]]; then
  while read -r preference host extra; do
    [[ -n ${preference:-} && -n ${host:-} && -z ${extra:-} ]] || continue
    [[ $preference =~ ^[0-9]+$ ]] || continue
    if [[ $host == "." ]]; then
      printf 'Result: domain publishes a Null MX and explicitly accepts no email.\n'
      exit 69
    fi
    host=${host%.}
    valid_domain "$host" || continue
    MX_HOSTS+=("$preference $host")
  done <<< "$(printf '%s\n' "$MX_RECORDS" | sort -n -k1,1)"
fi

if (( ${#MX_HOSTS[@]} == 0 )); then
  # RFC 5321 implicit-MX fallback: use the domain itself only when no MX exists.
  if [[ -n $(dig +time=5 +tries=1 +short A "$DOMAIN" 2>/dev/null) ||
        -n $(dig +time=5 +tries=1 +short AAAA "$DOMAIN" 2>/dev/null) ]]; then
    printf 'MX records: none; using RFC 5321 implicit MX (%s).\n' "$DOMAIN"
    MX_HOSTS+=("0 $DOMAIN")
  else
    printf 'Result: no MX record and no A/AAAA fallback endpoint.\n'
    exit 69
  fi
else
  printf 'MX records (lowest preference first):\n'
  printf '  %s\n' "${MX_HOSTS[@]}"
fi

read_smtp_reply() {
  local fd=$1 line separator first_code=""
  SMTP_CODE=""
  while IFS= read -r -t "$READ_TIMEOUT" -u "$fd" line; do
    line=${line%$'\r'}
    printf 'S: %s\n' "$line"
    if [[ $line =~ ^([0-9][0-9][0-9])([-\ ]) ]]; then
      [[ -n $first_code ]] || first_code=${BASH_REMATCH[1]}
      separator=${BASH_REMATCH[2]}
      if [[ $separator == " " ]]; then
        SMTP_CODE=${BASH_REMATCH[1]}
        return 0
      fi
    fi
  done
  SMTP_CODE=$first_code
  return 1
}

send_command() {
  local fd=$1 command=$2
  printf 'C: %s\n' "$command"
  printf '%s\r\n' "$command" >&"$fd"
}

probe_host() {
  local host=$1 smtp_read_fd smtp_write_fd smtp_pid result_code
  printf '\nConnecting to %s:%s ...\n' "$host" "$PORT"
  coproc SMTP_CONNECTION { nc -w "$CONNECT_TIMEOUT" "$host" "$PORT"; }
  smtp_read_fd=${SMTP_CONNECTION[0]}
  smtp_write_fd=${SMTP_CONNECTION[1]}
  smtp_pid=$SMTP_CONNECTION_PID

  read_smtp_reply "$smtp_read_fd" || { printf 'Connection failed or timed out waiting for SMTP greeting.\n' >&2; kill "$smtp_pid" 2>/dev/null || true; wait "$smtp_pid" 2>/dev/null || true; return 20; }
  [[ $SMTP_CODE == 220 ]] || { printf 'Unexpected SMTP greeting code: %s\n' "${SMTP_CODE:-none}" >&2; kill "$smtp_pid" 2>/dev/null || true; wait "$smtp_pid" 2>/dev/null || true; return 20; }

  send_command "$smtp_write_fd" "EHLO $HELO_NAME"
  read_smtp_reply "$smtp_read_fd" || { printf 'Timed out after EHLO.\n' >&2; kill "$smtp_pid" 2>/dev/null || true; wait "$smtp_pid" 2>/dev/null || true; return 20; }
  if [[ ! $SMTP_CODE =~ ^2 ]]; then
    send_command "$smtp_write_fd" "HELO $HELO_NAME"
    read_smtp_reply "$smtp_read_fd" || { printf 'Timed out after HELO.\n' >&2; kill "$smtp_pid" 2>/dev/null || true; wait "$smtp_pid" 2>/dev/null || true; return 20; }
    [[ $SMTP_CODE =~ ^2 ]] || { printf 'Server rejected EHLO and HELO.\n' >&2; kill "$smtp_pid" 2>/dev/null || true; wait "$smtp_pid" 2>/dev/null || true; return 20; }
  fi

  send_command "$smtp_write_fd" "MAIL FROM:$MAIL_FROM_CMD"
  read_smtp_reply "$smtp_read_fd" || { printf 'Timed out after MAIL FROM.\n' >&2; kill "$smtp_pid" 2>/dev/null || true; wait "$smtp_pid" 2>/dev/null || true; return 20; }
  [[ $SMTP_CODE =~ ^2 ]] || {
    printf 'Envelope sender rejected with SMTP %s; recipient status is inconclusive.\n' "${SMTP_CODE:-unknown}"
    send_command "$smtp_write_fd" "QUIT"
    kill "$smtp_pid" 2>/dev/null || true
    wait "$smtp_pid" 2>/dev/null || true
    return 20
  }

  send_command "$smtp_write_fd" "RCPT TO:<$TARGET_EMAIL>"
  read_smtp_reply "$smtp_read_fd" || { printf 'Timed out after RCPT TO.\n' >&2; kill "$smtp_pid" 2>/dev/null || true; wait "$smtp_pid" 2>/dev/null || true; return 20; }
  result_code=$SMTP_CODE

  # Reset the envelope and quit. Deliberately never issue DATA.
  send_command "$smtp_write_fd" "RSET"
  read_smtp_reply "$smtp_read_fd" >/dev/null 2>&1 || true
  send_command "$smtp_write_fd" "QUIT"
  read_smtp_reply "$smtp_read_fd" >/dev/null 2>&1 || true
  exec {smtp_write_fd}>&-
  exec {smtp_read_fd}<&-
  wait "$smtp_pid" 2>/dev/null || true

  case $result_code in
    2*) printf '\nResult: ACCEPTED at RCPT stage (SMTP %s). This is not proof the mailbox exists.\n' "$result_code"; return 0 ;;
    4*) printf '\nResult: INCONCLUSIVE temporary response (SMTP %s); retry later.\n' "$result_code"; return 20 ;;
    5*) printf '\nResult: PERMANENTLY REJECTED at RCPT stage (SMTP %s).\n' "$result_code"; return 10 ;;
    *)  printf '\nResult: INCONCLUSIVE unexpected response (SMTP %s).\n' "${result_code:-unknown}"; return 20 ;;
  esac
}

for mx_record in "${MX_HOSTS[@]}"; do
  MX_HOST=${mx_record#* }
  probe_host "$MX_HOST"
  PROBE_STATUS=$?

  case $PROBE_STATUS in
    0) exit 0 ;;
    10) exit 1 ;;
    *) printf 'Trying the next MX server, if available...\n' ;;
  esac
done

printf '\nResult: INCONCLUSIVE; no MX server completed the probe.\n'
exit 2
