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

cd ~/dots

# Find all files in the dots repo (these are what stow will try to link)
find . -type f -o -type l | while read -r repo_file; do
    # Remove leading './'
    relative_path="${repo_file#./}"
    target_path="$HOME/$relative_path"

    # If something exists at target and it's NOT already a symlink to our repo
    if [ -e "$target_path" ] || [ -L "$target_path" ]; then
        # Check if it's already the correct symlink
        if [ -L "$target_path" ]; then
            link_target=$(readlink "$target_path")
            # If it points to our dots repo, skip it
            if [[ "$link_target" == "$HOME/dots/$relative_path" ]] || [[ "$link_target" == ~/dots/"$relative_path" ]]; then
                continue
            fi
        fi

        # This is a conflict - back it up
        if [ ! -d "$BACKUP_DIR" ]; then
            mkdir -p "$BACKUP_DIR"
            echo "Created backup directory: $BACKUP_DIR"
        fi

        parent_dir="$BACKUP_DIR/$(dirname "$relative_path")"
        mkdir -p "$parent_dir"

        # Move (not copy) to preserve permissions and avoid issues
        mv "$target_path" "$BACKUP_DIR/$relative_path"
        echo "  Backed up: $relative_path"
    fi
done

# Also handle directories that might conflict (less common but possible)
find . -type d -mindepth 1 | while read -r repo_dir; do
    relative_path="${repo_dir#./}"
    target_path="$HOME/$relative_path"

    # If it exists and is a regular file (not a directory), that's a conflict
    if [ -f "$target_path" ]; then
        if [ ! -d "$BACKUP_DIR" ]; then
            mkdir -p "$BACKUP_DIR"
        fi

        parent_dir="$BACKUP_DIR/$(dirname "$relative_path")"
        mkdir -p "$parent_dir"

        mv "$target_path" "$BACKUP_DIR/$relative_path"
        echo "  Backed up conflicting file: $relative_path"
    fi
done

if [ -d "$BACKUP_DIR" ]; then
    echo "Backed up existing files to: $BACKUP_DIR"
else
    echo "No conflicts found, no backup needed."
fi

echo "Setting up symlinks with stow..."
if stow --restow --verbose=2 .; then
    echo "Symlinks created successfully."
else
    echo "Error: Stow failed."
    if [ -d "$BACKUP_DIR" ]; then
        echo "Your original files are safe in: $BACKUP_DIR"
        echo "Restoring backup..."
        cp -r "$BACKUP_DIR"/. "$HOME/"
        echo "Backup restored."
    fi
    exit 1
fi

# Apply tmux config if tmux is running
if tmux info &>/dev/null; then
    echo "Applying tmux config to running session..."
    tmux source-file ~/.config/tmux/tmux.conf
fi

echo ""
echo "✓ Setup complete!"
[ -d "$BACKUP_DIR" ] && echo "✓ Your old configs backed up to: $BACKUP_DIR"
echo "✓ Reload tmux and install plugins with prefix + I"
