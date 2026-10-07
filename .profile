# The following lines were added by Docker Desktop to add commands to your PATH.
export PATH="$PATH:$HOME/.docker/bin"
# End of Docker Desktop section.

if [ -r "$HOME/.deno/env" ]; then
    . "$HOME/.deno/env"
fi

# Keep RVM administration available without activating its Ruby environment.
export PATH="$PATH:$HOME/.rvm/bin"

if [ -r "$HOME/.cargo/env" ]; then
    . "$HOME/.cargo/env"
fi
