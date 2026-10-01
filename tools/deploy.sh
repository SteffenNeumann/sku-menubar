#!/bin/bash
# Alter Einstieg – baut jetzt über tools/update.sh (Release, sauber signiert).
exec bash "$(dirname "${BASH_SOURCE[0]}")/update.sh" --force
