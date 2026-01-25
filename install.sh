#!/bin/bash

set -e

echo "➡  Starting dotfiles setup..."

# 1. Detect OS
OS="unknown"
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
else
    echo "Unsupported OS: $OSTYPE"
    exit 1
fi

install_package() {
    local package="$1"
    if [ "$OS" = "macos" ]; then
        if ! command -v brew >/dev/null 2>&1; then
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            [[ $(uname -m) == "arm64" ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
        brew install "$package"
    elif [ "$OS" = "linux" ]; then
        if command -v pacman >/dev/null 2>&1; then sudo pacman -S --noconfirm "$package"
        elif command -v apt >/dev/null 2>&1; then sudo apt update && sudo apt install -y "$package"
        elif command -v dnf >/dev/null 2>&1; then sudo dnf install -y "$package"
        else echo "Install $package manually."; exit 1; fi
    fi
}

# 2. Install dependencies
echo "➡  Installing dependencies..."
install_package stow
install_package tmux
install_package neovim

# 3. Handle Tmux Plugin Manager
if [ ! -d ~/.tmux/plugins/tpm ]; then
    echo "➡  Installing TPM..."
    git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
fi

# 4. Handle Dotfiles Repo
DOTS_DIR="$HOME/dots"
if [ ! -d "$DOTS_DIR" ]; then
    echo "➡  Cloning repo..."
    git clone https://github.com/s0rus/dots.git "$DOTS_DIR"
fi
cd "$DOTS_DIR"

# 5. BACKUP
echo "➡  Detecting conflicts..."
BACKUP_DIR="$HOME/dotfiles_backup_$(date +%Y%m%d_%H%M%S)"

mapfile -t items < <(find . -maxdepth 1 -mindepth 1 ! -name ".git" ! -name "install.sh" ! -name "README.md" ! -name "LICENSE" -printf "%P\n")

for item in "${items[@]}"; do
    if [ "$item" == ".config" ] && [ -d "$item" ]; then
        mapfile -t subitems < <(find ".config" -maxdepth 1 -mindepth 1 -printf "%P\n")
        for subitem in "${subitems[@]}"; do
            target="$HOME/.config/$subitem"
            if [ -e "$target" ] || [ -L "$target" ]; then
                [ -L "$target" ] && [[ "$(readlink "$target")" == *"$DOTS_DIR"* ]] && continue
                mkdir -p "$(dirname "$BACKUP_DIR/.config/$subitem")"
                cp -rP "$target" "$BACKUP_DIR/.config/$subitem"
                rm -rf "$target"
                echo "  Backup: ~/.config/$subitem"
            fi
        done
    else
        # Handle top-level files like .bashrc
        target="$HOME/$item"
        if [ -e "$target" ] || [ -L "$target" ]; then
            [ -L "$target" ] && [[ "$(readlink "$target")" == *"$DOTS_DIR"* ]] && continue
            mkdir -p "$BACKUP_DIR"
            cp -rP "$target" "$BACKUP_DIR/$item"
            rm -rf "$target"
            echo "  Backup: ~/$item"
        fi
    fi
done

# 6. Symlink
echo "Stowing..."
stow -v .

# 7. Apply Tmux config
if tmux info &>/dev/null 2>&1; then
    echo "➡  Reloading tmux..."
    tmux source-file ~/.config/tmux/tmux.conf 2>/dev/null || true
fi

echo "========================"
echo "✓ Setup complete!"
[ -d "$BACKUP_DIR" ] && echo "✓ Backups: $BACKUP_DIR"
echo "========================"
