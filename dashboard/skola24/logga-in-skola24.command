#!/bin/zsh
# Logga in i Skola24 igen (när inloggningen har gått ut), och läs schemat direkt.
cd "$(dirname "$0")"
DIR="$HOME/Library/Application Support/Panel/skola24"
"$DIR/venv/bin/python" skola24.py login && "$DIR/venv/bin/python" skola24.py fetch
