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
        echo "Unsupported package manager. Please install $1 manually."
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

echo "Backing up existing dotfiles that would conflict..."
BACKUP_DIR="$HOME/dotfiles_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

cd ~/dots

# Use stow --simulate to detect conflicts without making changes
conflicts=$(stow --simulate --no-folding . 2>&1 | grep "existing target is" | awk '{print $NF}' || true)

if [ -n "$conflicts" ]; then
    echo "Found conflicts, backing up to: $BACKUP_DIR"
    echo "$conflicts" | while read -r conflict; do
        # Remove leading "~/" or convert to absolute path
        conflict_path="${conflict/#\~/$HOME}"
        
        if [ -e "$conflict_path" ] && [ ! -L "$conflict_path" ]; then
            # Create parent directory structure in backup
            parent_dir="$BACKUP_DIR/$(dirname "${conflict_path#$HOME/}")"
            mkdir -p "$parent_dir"
            
            # Copy the actual file (not symlink)
            cp -P "$conflict_path" "$BACKUP_DIR/${conflict_path#$HOME/}"
            echo "  Backed up: ${conflict_path#$HOME/}"
            
            # Remove the conflicting file
            rm -f "$conflict_path"
        fi
    done
else
    echo "No conflicts found."
    rmdir "$BACKUP_DIR" 2>/dev/null || true
fi

echo "Setting up symlinks with stow..."
if stow --no-folding .; then
    echo "Symlinks created successfully."
else
    echo "Error: Stow failed. Restoring from backup..."
    if [ -d "$BACKUP_DIR" ]; then
        cp -r "$BACKUP_DIR"/* "$HOME/"
        echo "Backup restored. Please check conflicts manually."
    fi
    exit 1
fi

# Apply tmux config if tmux is running
if tmux info &>/dev/null; then
    echo "Applying tmux config to running session..."
    tmux source-file ~/.config/tmux/tmux.conf
fi

echo "Setup complete!"
echo "Backup location (if created): $BACKUP_DIR"
echo "Reload your tmux and install plugins with prefix + I."
