## SMTP Reachability Check Script

Run it with:

```bash
chmod +x smtp-reachability-check.sh
./smtp-reachability-check.sh user@example.com
```

For better acceptance rates, use a sender and HELO domain you control:

```bash
./smtp-reachability-check.sh \
  --from probe@yourdomain.com \
  --helo mail.yourdomain.com \
  user@example.com
```

The script:

* Validates the address and prevents SMTP command injection.
* Resolves and sorts MX records by priority.
* Supports RFC 5321 implicit-MX fallback.
* Detects RFC 7505 Null MX domains.
* Performs sequential `EHLO`, `MAIL FROM`, and `RCPT TO` commands.
* Falls back from `EHLO` to `HELO`.
* Tries another MX server after connection or temporary failures.
* Sends `RSET` and `QUIT`, but never `DATA`.
* Returns automation-friendly exit codes.

Dependencies are Bash 4.1+, `dig`, and `nc` (OpenBSD netcat). On Debian/Ubuntu:

```bash
sudo apt install dnsutils netcat-openbsd
```

On Arch/CachyOS:

```bash
sudo pacman -S bind openbsd-netcat
```

Interpretation is deliberately conservative:

* `250`: accepted during the SMTP transaction, but not proof the mailbox exists.
* `5xx`: permanently rejected at that moment; it may indicate an unknown mailbox or a policy rejection.
* `4xx`, timeout, blocked port 25, required TLS, or rejected sender: inconclusive.

### Sources

* [RFC 5321 — SMTP and MX resolution](https://www.rfc-editor.org/info/rfc5321/)
* [RFC 7505 — Null MX](https://www.rfc-editor.org/info/rfc7505/)
* [RFC 7504 — SMTP 521 and 556 response codes](https://www.rfc-editor.org/info/rfc7504/)

Confidence: High (94%).

## Mail Settings Discovery Script

```bash
chmod +x discover-mail-settings.sh
./discover-mail-settings.sh utente@example.com
```

Modalità più completa:

```bash
./discover-mail-settings.sh \
  --heuristic \
  --ispdb \
  utente@example.com
```

Lo script:

* interroga i record SRV per IMAP, POP3 e SMTP submission;
* legge l’autoconfigurazione pubblicata dal provider;
* può consultare opzionalmente Thunderbird ISPDB;
* verifica connessione, TLS, STARTTLS/STLS e certificato;
* non richiede né trasmette credenziali;
* assegna un livello di confidenza a ogni risultato;
* separa l’MX sulla porta 25 dalle impostazioni SMTP del client;
* usa euristiche solo con `--heuristic`.

Per analizzare senza effettuare probe di rete:

```bash
./discover-mail-settings.sh --no-probe example.com
```

Dipendenze Ubuntu/Debian:

```bash
sudo apt install dnsutils curl openssl libxml2-utils netcat-openbsd
```

Dipendenze Arch/CachyOS (`curl` e `openssl` sono già nel sistema base):

```bash
sudo pacman -S bind libxml2 openbsd-netcat
```

Ho validato sintassi, opzioni CLI e uno scenario end-to-end simulato con SRV IMAP 993, SMTP submission 587 e MX relay 25. Il comportamento con uno specifico provider dipenderà naturalmente dai record e dai file che pubblica.

### Fonti

* [RFC 6186 — Service discovery tramite SRV](https://www.rfc-editor.org/rfc/rfc6186)
* [RFC 8314 — TLS per accesso e submission](https://www.rfc-editor.org/rfc/rfc8314)
* [RFC 6409 — SMTP submission](https://www.rfc-editor.org/rfc/rfc6409)
* [Thunderbird Autoconfiguration](https://wiki.mozilla.org/Thunderbird:Autoconfiguration:ConfigFileFormat)

Confidenza: 96%.
