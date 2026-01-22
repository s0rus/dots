#!/bin/bash

set -e
echo "Starting dotfiles setup..."

install_package() {
    if command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --noconfirm "$1"
    elif command -v apt >/dev/null 2>&1; then
        sudo apt update && sudo apt install -y "$1"
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y "$1"
    elif command -v zypper >/dev/null 2>&1; then
        sudo zypper install -y "$1"
    else
        echo "Unsupported package manager. Please install $1 manually (see https://github.com/s0rus/dots)."
        exit 1
    fi
}

# Install dependencies
echo "Installing dependencies..."
install_package stow
install_package tmux

# Install Tmux Plugin Manager if missing
if [ ! -d ~/.tmux/plugins/tpm ]; then
    echo "Installing Tmux Plugin Manager..."
    git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
else
    echo "Tmux Plugin Manager already installed."
fi

# Clone repo if not present
if [ ! -d ~/dots ]; then
    echo "Cloning dotfiles repo..."
    git clone https://github.com/s0rus/dots.git ~/dots
else
    echo "Dotfiles repo already cloned."
fi

# Backup existing conflicting directories/files
echo "Backing up any existing dotfiles to avoid conflicts..."
cd ~/dots
for item in .*; do
    if [ -e ~/"$item" ] && [ "$item" != "." ] && [ "$item" != ".." ]; then
        echo "Backing up ~/$item to ~/$item.bak"
        mv ~/"$item" ~/"$item".bak || { echo "Backup failed for $item. Please resolve manually."; exit 1; }
    fi
done

# Run stow
echo "Setting up symlinks with stow..."
if stow .; then
    echo "Symlinks created successfully."
else
    echo "Error: Stow failed. Check for conflicts or run 'cd ~/dots && stow .' manually."
    exit 1
fi

# Apply tmux config if possible
echo "Applying tmux config..."
tmux source-file ~/.config/tmux/tmux.conf || true
echo "Setup complete! Backups are in ~/*.bak if needed. If in a tmux session, press prefix + I to install plugins."
