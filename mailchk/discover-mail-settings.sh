#!/usr/bin/env bash

# Discover client-facing email settings from published DNS SRV records and
# provider-hosted Thunderbird autoconfiguration. Optional heuristics are kept
# separate and clearly labelled. No credentials are requested or transmitted.

set -u
set -o pipefail
export LC_ALL=C

PROGRAM=${0##*/}
TARGET=""
EMAIL=""
DOMAIN=""
LOCALPART=""
TIMEOUT_SECONDS=10
DO_PROBE=1
USE_HEURISTICS=0
USE_ISPDB=0
RESULTS_FILE=""
TEMP_DIR=""
TEMP_CREATED=0

usage() {
   cat << EOF
Usage: $PROGRAM [options] EMAIL_OR_DOMAIN

Discover IMAP, POP3, and SMTP submission settings without authenticating.

Options:
  --no-probe       Do not test TCP/TLS connectivity
  --heuristic      If published settings are incomplete, test common hostnames
  --ispdb          Also query Thunderbird's public ISP configuration database
  -t, --timeout N  Network timeout in seconds (default: 10)
  -h, --help       Show this help

Examples:
  $PROGRAM user@example.com
  $PROGRAM --heuristic --ispdb example.com

Required: Bash 4+, dig, curl, openssl
Optional: xmllint (provider XML), nc (plaintext TCP checks)
EOF
}

die() {
   printf 'Error: %s\n' "$1" >&2
   exit "${2:-64}"
}

cleanup() {
   if ((${TEMP_CREATED:-0} == 1)) && [[ -d ${TEMP_DIR:-} && ${TEMP_DIR##*/} == mail-discovery.* ]]; then
      rm -rf -- "$TEMP_DIR"
   fi
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

valid_domain() {
   local domain=$1 label rest
   ((${#domain} <= 253)) || return 1
   [[ $domain =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || return 1
   [[ $domain != *..* ]] || return 1
   rest=$domain
   while :; do
      label=${rest%%.*}
      ((${#label} >= 1 && ${#label} <= 63)) || return 1
      [[ $label != -* && $label != *- ]] || return 1
      [[ $rest == *.* ]] || break
      rest=${rest#*.}
   done
}

parse_target() {
   local input=$1
   input=${input%.}
   if [[ $input == *@* ]]; then
      EMAIL=$input
      LOCALPART=${input%@*}
      DOMAIN=${input##*@}
      [[ -n $LOCALPART && $LOCALPART != *@* && $LOCALPART != *[$'\r\n\t ']* ]] || return 1
      ((${#LOCALPART} <= 64 && ${#EMAIL} <= 254)) || return 1
   else
      DOMAIN=$input
      EMAIL="postmaster@$DOMAIN"
      LOCALPART=postmaster
   fi
   DOMAIN=${DOMAIN,,}
   valid_domain "$DOMAIN"
}

while (($# > 0)); do
   case $1 in
      --no-probe)
         DO_PROBE=0
         shift
         ;;
      --heuristic)
         USE_HEURISTICS=1
         shift
         ;;
      --ispdb)
         USE_ISPDB=1
         shift
         ;;
      -t | --timeout)
         (($# >= 2)) || die "$1 requires a value"
         TIMEOUT_SECONDS=$2
         shift 2
         ;;
      -h | --help)
         usage
         exit 0
         ;;
      --)
         shift
         break
         ;;
      -*) die "unknown option: $1" ;;
      *)
         [[ -z $TARGET ]] || die "provide only one email address or domain"
         TARGET=$1
         shift
         ;;
   esac
done

(($# == 0)) || die "unexpected argument: $1"
[[ -n $TARGET ]] || { read -r -p "Email address or domain: " TARGET; }
[[ $TIMEOUT_SECONDS =~ ^[1-9][0-9]*$ ]] && ((TIMEOUT_SECONDS <= 120)) \
   || die "timeout must be an integer from 1 to 120"
((BASH_VERSINFO[0] >= 4)) || die "Bash 4 or newer is required"
parse_target "$TARGET" || die "invalid or unsupported ASCII email address/domain"

for dependency in dig curl openssl; do
   command -v "$dependency" > /dev/null 2>&1 || die "'$dependency' is required"
done

TEMP_BASE=${TMPDIR:-/tmp}
[[ -d $TEMP_BASE && -w $TEMP_BASE ]] || TEMP_BASE=.
TEMP_DIR=$(mktemp -d "$TEMP_BASE/mail-discovery.XXXXXX") || die "cannot create temporary directory"
TEMP_CREATED=1
RESULTS_FILE="$TEMP_DIR/results.tsv"
: > "$RESULTS_FILE"

sanitize_field() {
   local value=$1
   value=${value//$'\t'/ }
   value=${value//$'\r'/ }
   value=${value//$'\n'/ }
   printf '%s' "$value"
}

add_result() {
   local protocol=$1 security=$2 host=$3 port=$4 source=$5 confidence=$6 details=${7:-}
   host=${host%.}
   valid_domain "$host" || return 1
   [[ $port =~ ^[1-9][0-9]*$ ]] && ((port <= 65535)) || return 1
   printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$(sanitize_field "$protocol")" "$(sanitize_field "$security")" \
      "$(sanitize_field "$host")" "$(sanitize_field "$port")" \
      "$(sanitize_field "$source")" "$(sanitize_field "$confidence")" \
      "$(sanitize_field "$details")" >> "$RESULTS_FILE"
}

discover_srv() {
   local label=$1 protocol=$2 security=$3 answer priority weight port host
   answer=$(dig +time=5 +tries=1 +short SRV "$label.$DOMAIN" 2> /dev/null || true)
   [[ -n $answer ]] || return 0

   while read -r priority weight port host extra; do
      [[ -n ${priority:-} && -n ${weight:-} && -n ${port:-} && -n ${host:-} && -z ${extra:-} ]] || continue
      [[ $priority =~ ^[0-9]+$ && $weight =~ ^[0-9]+$ && $port =~ ^[0-9]+$ ]] || continue
      if [[ $host == "." ]]; then
         printf '  %-28s explicitly unavailable (SRV target ".")\n' "$label.$DOMAIN"
         continue
      fi
      add_result "$protocol" "$security" "$host" "$port" "DNS SRV" "HIGH" \
         "priority=$priority weight=$weight"
   done <<< "$(printf '%s\n' "$answer" | sort -n -k1,1 -k2,2nr)"
}

printf 'Discovering published settings for %s\n\n' "$DOMAIN"
printf 'DNS service discovery:\n'
discover_srv "_imaps._tcp" "IMAP" "Implicit TLS"
discover_srv "_imap._tcp" "IMAP" "STARTTLS/plain"
discover_srv "_pop3s._tcp" "POP3" "Implicit TLS"
discover_srv "_pop3._tcp" "POP3" "STLS/plain"
discover_srv "_submissions._tcp" "SMTP" "Implicit TLS"
discover_srv "_submission._tcp" "SMTP" "STARTTLS"

MX_RECORDS=$(dig +time=5 +tries=1 +short MX "$DOMAIN" 2> /dev/null || true)

xml_value() {
   local file=$1 xpath=$2
   xmllint --xpath "string($xpath)" "$file" 2> /dev/null || true
}

parse_autoconfig_xml() {
   local file=$1 source=$2 kind tag count index xpath host port socket auth username protocol security
   command -v xmllint > /dev/null 2>&1 || return 0
   xmllint --noout "$file" > /dev/null 2>&1 || return 0

   for kind in imap pop3 smtp; do
      if [[ $kind == smtp ]]; then tag=outgoingServer; else tag=incomingServer; fi
      count=$(xmllint --xpath "count(//$tag[@type='$kind'])" "$file" 2> /dev/null || printf '0')
      count=${count%%.*}
      [[ $count =~ ^[0-9]+$ ]] || count=0

      for ((index = 1; index <= count; index++)); do
         xpath="(//$tag[@type='$kind'])[$index]"
         host=$(xml_value "$file" "$xpath/hostname")
         port=$(xml_value "$file" "$xpath/port")
         socket=$(xml_value "$file" "$xpath/socketType")
         auth=$(xml_value "$file" "$xpath/authentication")
         username=$(xml_value "$file" "$xpath/username")

         host=${host//%EMAILDOMAIN%/$DOMAIN}
         username=${username//%EMAILADDRESS%/$EMAIL}
         username=${username//%EMAILLOCALPART%/$LOCALPART}
         username=${username//%EMAILDOMAIN%/$DOMAIN}
         protocol=${kind^^}
         case ${socket^^} in
            SSL | TLS) security="Implicit TLS" ;;
            STARTTLS) security="STARTTLS" ;;
            *) security="Plain/unspecified" ;;
         esac
         add_result "$protocol" "$security" "$host" "$port" "$source" "HIGH" \
            "auth=${auth:-unspecified}; username=${username:-unspecified}" || true
      done
   done
}

fetch_autoconfig() {
   local url=$1 source=$2 output=$3
   if curl --silent --show-error --fail --location --max-redirs 3 \
      --proto '=https' --proto-redir '=https' \
      --connect-timeout "$TIMEOUT_SECONDS" --max-time "$TIMEOUT_SECONDS" \
      --get --data-urlencode "emailaddress=$EMAIL" --output "$output" "$url" 2> /dev/null; then
      parse_autoconfig_xml "$output" "$source"
      return 0
   fi
   return 1
}

printf '\nProvider autoconfiguration:\n'
if command -v xmllint > /dev/null 2>&1; then
   BEFORE_XML=$(wc -l < "$RESULTS_FILE")
   fetch_autoconfig "https://autoconfig.$DOMAIN/mail/config-v1.1.xml" \
      "Provider autoconfig" "$TEMP_DIR/autoconfig-subdomain.xml" || true
   fetch_autoconfig "https://$DOMAIN/.well-known/autoconfig/mail/config-v1.1.xml" \
      "Provider .well-known" "$TEMP_DIR/autoconfig-well-known.xml" || true
   if ((USE_ISPDB)); then
      fetch_autoconfig "https://autoconfig.thunderbird.net/v1.1/$DOMAIN" \
         "Thunderbird ISPDB" "$TEMP_DIR/autoconfig-ispdb.xml" || true
   fi
   AFTER_XML=$(wc -l < "$RESULTS_FILE")
   if ((AFTER_XML > BEFORE_XML)); then
      printf '  Valid configuration data found.\n'
   else
      printf '  No usable provider configuration found.\n'
   fi
else
   printf '  Skipped: install xmllint (libxml2-utils) to parse configuration XML.\n'
fi

run_bounded() {
   local output=$1
   shift
   local command_pid watchdog_pid status
   "$@" > "$output" 2>&1 &
   command_pid=$!
   (
      sleep "$TIMEOUT_SECONDS"
      kill -TERM "$command_pid" 2> /dev/null || true
   ) &
   watchdog_pid=$!
   wait "$command_pid"
   status=$?
   kill -TERM "$watchdog_pid" 2> /dev/null || true
   wait "$watchdog_pid" 2> /dev/null || true
   return "$status"
}

verify_endpoint() {
   local protocol=$1 security=$2 host=$3 port=$4 output="$TEMP_DIR/probe-${RANDOM}-${port}.log" starttls=""
   case "$security" in
      "Implicit TLS")
         if run_bounded "$output" openssl s_client -brief -verify_return_error \
            -verify_hostname "$host" -servername "$host" -connect "$host:$port" < /dev/null; then
            printf 'TLS verified'
         else
            printf 'TLS failed/unreachable'
         fi
         ;;
      "STARTTLS" | "STARTTLS/plain" | "STLS/plain")
         case $protocol in
            SMTP) starttls=smtp ;;
            IMAP) starttls=imap ;;
            POP3) starttls=pop3 ;;
         esac
         if run_bounded "$output" openssl s_client -brief -verify_return_error \
            -verify_hostname "$host" -servername "$host" -starttls "$starttls" \
            -connect "$host:$port" < /dev/null; then
            printf 'STARTTLS verified'
         else
            printf 'STARTTLS failed/unreachable'
         fi
         ;;
      *)
         if command -v nc > /dev/null 2>&1 && nc -z -w "$TIMEOUT_SECONDS" "$host" "$port" > /dev/null 2>&1; then
            printf 'TCP reachable; encryption unknown'
         else
            printf 'Not verified'
         fi
         ;;
   esac
}

result_exists() {
   local protocol=$1
   awk -F '\t' -v p="$protocol" '$1 == p { found=1 } END { exit !found }' "$RESULTS_FILE"
}

heuristic_add_if_verified() {
   local protocol=$1 security=$2 host=$3 port=$4 status
   status=$(verify_endpoint "$protocol" "$security" "$host" "$port")
   [[ $status == *verified ]] || return 0
   add_result "$protocol" "$security" "$host" "$port" "Heuristic probe" "MEDIUM" \
      "not provider-published"
}

if ((USE_HEURISTICS)); then
   printf '\nOptional heuristic discovery:\n'
   if ! result_exists IMAP; then
      heuristic_add_if_verified IMAP "Implicit TLS" "imap.$DOMAIN" 993
      heuristic_add_if_verified IMAP "Implicit TLS" "mail.$DOMAIN" 993
   fi
   if ! result_exists POP3; then
      heuristic_add_if_verified POP3 "Implicit TLS" "pop.$DOMAIN" 995
      heuristic_add_if_verified POP3 "Implicit TLS" "pop3.$DOMAIN" 995
      heuristic_add_if_verified POP3 "Implicit TLS" "mail.$DOMAIN" 995
   fi
   if ! result_exists SMTP; then
      heuristic_add_if_verified SMTP "Implicit TLS" "smtp.$DOMAIN" 465
      heuristic_add_if_verified SMTP "STARTTLS" "smtp.$DOMAIN" 587
      heuristic_add_if_verified SMTP "Implicit TLS" "mail.$DOMAIN" 465
      heuristic_add_if_verified SMTP "STARTTLS" "mail.$DOMAIN" 587
   fi
   printf '  Completed; heuristic results are labelled MEDIUM confidence.\n'
fi

printf '\nClient configuration candidates:\n'
if [[ ! -s $RESULTS_FILE ]]; then
   printf '  No published client configuration was discovered.\n'
else
   printf '%-6s %-28s %-6s %-18s %-23s %-10s %s\n' \
      "TYPE" "SERVER" "PORT" "SECURITY" "SOURCE" "CONFIDENCE" "CHECK"
   printf '%-6s %-28s %-6s %-18s %-23s %-10s %s\n' \
      "------" "----------------------------" "------" "------------------" \
      "-----------------------" "----------" "-----"

   sort -u "$RESULTS_FILE" | while IFS=$'\t' read -r protocol security host port source confidence details; do
      if ((DO_PROBE)); then
         check=$(verify_endpoint "$protocol" "$security" "$host" "$port")
      else
         check="not tested"
      fi
      printf '%-6s %-28s %-6s %-18s %-23s %-10s %s\n' \
         "$protocol" "$host" "$port" "$security" "$source" "$confidence" "$check"
      [[ -z $details ]] || printf '       Details: %s\n' "$details"
   done
fi

printf '\nSMTP relay information (not normally a client submission setting):\n'
if [[ -z $MX_RECORDS ]]; then
   printf '  No MX records found.\n'
else
   while read -r priority host extra; do
      [[ $priority =~ ^[0-9]+$ && -n ${host:-} && -z ${extra:-} ]] || continue
      if [[ $host == "." ]]; then
         printf '  Domain publishes Null MX: it accepts no inbound email.\n'
      else
         printf '  MX priority %-5s %-40s port 25 (server-to-server relay)\n' "$priority" "${host%.}"
      fi
   done <<< "$(printf '%s\n' "$MX_RECORDS" | sort -n -k1,1)"
fi

printf '\nNotes:\n'
printf '  - Prefer TLS-verified settings published by the provider or DNS SRV.\n'
printf '  - Port 465 is SMTP submission with implicit TLS; port 587 normally uses STARTTLS.\n'
printf '  - Port 25 is primarily SMTP relay and is not selected as a client default.\n'
printf '  - A reachable endpoint does not prove that a particular account is enabled.\n'
