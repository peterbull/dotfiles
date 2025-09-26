#!/bin/bash

set -e

echo "Setting up development environment..."

echo "Installing ImageMagick..."
if command -v brew >/dev/null 2>&1; then
    brew install imagemagick
else
    echo "Error: Homebrew not found. Please install Homebrew first."
    exit 1
fi

echo "Creating virtualenvs directory..."
mkdir -p ~/.virtualenvs

echo "Creating Neovim virtual environment..."
if command -v python3 >/dev/null 2>&1; then
    python3 -m venv ~/.virtualenvs/nvim
elif command -v python >/dev/null 2>&1; then
    python -m venv ~/.virtualenvs/nvim
else
    echo "Error: Python not found. Please install Python first."
    exit 1
fi

echo "Installing Python packages..."
source ~/.virtualenvs/nvim/bin/activate

# Upgrade pip first
pip install --upgrade pip

# Install packages
pip install \
    pynvim \
    jupyter_client \
    cairosvg \
    plotly \
    kaleido \
    pnglatex \
    pyperclip

echo "Setup complete!"
echo "To use the Neovim virtual environment, run:"
echo "source ~/.virtualenvs/nvim/bin/activate"
