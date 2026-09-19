#!/usr/bin/env bash
# Installs create-llmstxt: uv venv + deps, Firecrawl key, zsh alias.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

# 1. uv
if ! command -v uv >/dev/null 2>&1; then
    echo "uv not found, installing via astral.sh..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
fi

# 2. venv + deps
uv venv --quiet --allow-existing .venv
uv pip install --quiet --python .venv/bin/python -r requirements.txt
echo "Dependencies installed in $DIR/.venv"

# 3. Firecrawl key (only prompt; keep an existing real key)
if grep -qE '^FIRECRAWL_API_KEY=fc-[A-Za-z0-9-]{8,}' .env 2>/dev/null; then
    echo "Firecrawl key already set in .env, keeping it"
else
    read -r -p "Firecrawl API key (fc-...): " key
    [[ -n "$key" ]] || { echo "No key given, aborting"; exit 1; }
    printf 'FIRECRAWL_API_KEY=%s\n' "$key" > .env
    chmod 600 .env
    echo "Saved to $DIR/.env"
fi

# 4. zsh alias, idempotent, inside the repos/bin shorthand block if present
ZSHRC="$HOME/.zshrc"
ALIAS="alias create-llmstxt=\"${DIR/#$HOME/\$HOME}/create-llmstxt\""  # $HOME-relative like the other shorthands
if ! grep -qF 'alias create-llmstxt=' "$ZSHRC" 2>/dev/null; then
    if grep -qF '# <<< repos/bin shorthands end <<<' "$ZSHRC" 2>/dev/null; then
        sed -i "/# <<< repos\/bin shorthands end <<</i $ALIAS" "$ZSHRC"
    else
        printf '\n%s\n' "$ALIAS" >> "$ZSHRC"
    fi
    echo "Alias added to $ZSHRC (run: source ~/.zshrc)"
else
    echo "Alias already in $ZSHRC"
fi

echo "Done. Usage: create-llmstxt https://example.com --no-full-text --output-dir ./out"
