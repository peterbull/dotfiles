#!/bin/sh
if [ -x /opt/homebrew/bin/gh ]; then
    exec /opt/homebrew/bin/gh auth git-credential "$@"
elif [ -x /usr/bin/gh ]; then
    exec /usr/bin/gh auth git-credential "$@"
elif [ -x /usr/local/bin/gh ]; then
    exec /usr/local/bin/gh auth git-credential "$@"
elif [ -x /home/linuxbrew/.linuxbrew/bin/gh ]; then
    exec /home/linuxbrew/.linuxbrew/bin/gh auth git-credential "$@"
else
    exec gh auth git-credential "$@"
fi
