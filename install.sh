#!/bin/bash
set -e

echo "Starting dotfiles setup..."

# Detect OS
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
            echo "Homebrew not found. Installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            # Add Homebrew to PATH for Apple Silicon Macs
            if [[ $(uname -m) == "arm64" ]]; then
                echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
                eval "$(/opt/homebrew/bin/brew shellenv)"
            fi
        fi
        brew install "$package"
    elif [ "$OS" = "linux" ]; then
        if command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --noconfirm "$package"
        elif command -v apt >/dev/null 2>&1; then
            sudo apt update && sudo apt install -y "$package"
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y "$package"
        elif command -v zypper >/dev/null 2>&1; then
            sudo zypper install -y "$package"
        else
            echo "Unsupported package manager. Please install $package manually."
            exit 1
        fi
    fi
}

# Install dependencies
echo "Installing dependencies..."
install_package stow
install_package tmux
install_package neovim

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

echo "Backing up existing config directories that would conflict..."
BACKUP_DIR="$HOME/dotfiles_backup_$(date +%Y%m%d_%H%M%S)"

cd ~/dots

# Identify top-level config directories that will be stowed
declare -a config_dirs

# Find immediate subdirectories under top-level directories
while IFS= read -r -d '' top_dir; do
    top_dir_name=$(basename "$top_dir")
    # Skip .git directory
    [[ "$top_dir_name" == ".git" ]] && continue
    # For .config, .local, etc., find their immediate subdirectories
    if [ -d "$top_dir" ]; then
        while IFS= read -r -d '' sub_dir; do
            relative_path="${sub_dir#./}"
            config_dirs+=("$relative_path")
        done < <(find "$top_dir" -mindepth 1 -maxdepth 1 -type d -print0)
    fi
done < <(find . -mindepth 1 -maxdepth 1 -type d -print0)

# Backup conflicting config directories
for config_dir in "${config_dirs[@]}"; do
    target_path="$HOME/$config_dir"
    # If directory exists and is not a symlink to our dots
    if [ -e "$target_path" ] && [ ! -L "$target_path" ]; then
        # Check if it would actually conflict with our stow
        has_conflict=false
        # Check if any files in our repo would conflict
        if [ -d "$config_dir" ]; then
            while IFS= read -r -d '' repo_file; do
                repo_relative="${repo_file#./}"
                target_file="$HOME/$repo_relative"
                if [ -e "$target_file" ] && [ ! -L "$target_file" ]; then
                    has_conflict=true
                    break
                elif [ -L "$target_file" ]; then
                    # Check if symlink points elsewhere
                    link_target=$(readlink "$target_file")
                    if [[ "$link_target" != *"/dots/$repo_relative" ]]; then
                        has_conflict=true
                        break
                    fi
                fi
            done < <(find "$config_dir" -type f -print0)
        fi
        if [ "$has_conflict" = true ]; then
            if [ ! -d "$BACKUP_DIR" ]; then
                mkdir -p "$BACKUP_DIR"
                echo "Created backup directory: $BACKUP_DIR"
            fi
            parent_dir="$BACKUP_DIR/$(dirname "$config_dir")"
            mkdir -p "$parent_dir"
            # Backup the entire config directory
            cp -r "$target_path" "$BACKUP_DIR/$config_dir"
            echo "  Backed up directory: $config_dir"
            # Remove the directory so stow can work
            rm -rf "$target_path"
        fi
    fi
done

# Also handle individual files that might conflict
while IFS= read -r -d '' repo_file; do
    relative_path="${repo_file#./}"
    target_path="$HOME/$relative_path"
    # Skip if parent directory was already backed up
    parent_backed_up=false
    for backed_dir in "${config_dirs[@]}"; do
        if [[ "$relative_path" == "$backed_dir"* ]]; then
            if [ -d "$BACKUP_DIR/$backed_dir" ]; then
                parent_backed_up=true
                break
            fi
        fi
    done
    if [ "$parent_backed_up" = true ]; then
        continue
    fi
    # If file exists and is NOT already a correct symlink
    if [ -e "$target_path" ] || [ -L "$target_path" ]; then
        if [ -L "$target_path" ]; then
            link_target=$(readlink "$target_path")
            # Skip if already pointing to our dots
            if [[ "$link_target" == *"/dots/$relative_path" ]]; then
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
        cp -P "$target_path" "$BACKUP_DIR/$relative_path"
        echo "  Backed up file: $relative_path"
        # Remove so stow can work
        rm -f "$target_path"
    fi
done < <(find . -type f -print0)

if [ -d "$BACKUP_DIR" ]; then
    echo "Backed up existing configs to: $BACKUP_DIR"
else
    echo "No conflicts found, no backup needed."
fi

echo "Setting up symlinks with stow..."
# Use --ignore to skip install.sh and other non-config files
if stow --restow --ignore="install.sh" --ignore="README.md" --ignore=".git" --ignore="LICENSE" --verbose=2 .; then
    echo "Symlinks created successfully."
else
    echo "Error: Stow failed."
    if [ -d "$BACKUP_DIR" ]; then
        echo "Your original files are backed up in: $BACKUP_DIR"
        echo "You can manually restore them if needed."
    fi
    exit 1
fi

# Apply tmux config if tmux is running
if tmux info &>/dev/null 2>&1; then
    echo "Applying tmux config to running session..."
    tmux source-file ~/.config/tmux/tmux.conf 2>/dev/null || true
fi

echo ""
echo "✓ Setup complete!"
[ -d "$BACKUP_DIR" ] && echo "✓ Your old configs backed up to: $BACKUP_DIR"
echo "✓ Neovim installed and configured"
echo "✓ Reload tmux and install plugins with prefix + I"

if [ "$OS" = "macos" ]; then
    echo ""
    echo "macOS specific notes:"
    echo "  - Homebrew installed/updated"
    echo "  - You may need to restart your terminal"
fi
