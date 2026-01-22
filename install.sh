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

cd ~/dots

# Verify the dots repo has content
echo "Verifying dots repo contents..."
if [ ! -d .config ] && [ ! -f .bashrc ] && [ ! -f .zshrc ]; then
    echo "Warning: dots repo seems empty or misconfigured"
    echo "Contents of ~/dots:"
    ls -la
    exit 1
fi

echo "Detecting conflicts..."
BACKUP_DIR="$HOME/dotfiles_backup_$(date +%Y%m%d_%H%M%S)"
declare -a conflicts_to_remove=()

# Find all files/dirs that would conflict
while IFS= read -r -d '' item; do
    relative_path="${item#./}"
    target_path="$HOME/$relative_path"
    
    # Skip if already a correct symlink
    if [ -L "$target_path" ]; then
        link_target=$(readlink "$target_path")
        if [[ "$link_target" == "$HOME/dots/$relative_path" ]] || [[ "$link_target" == ~/dots/"$relative_path" ]]; then
            continue
        fi
    fi
    
    # If it exists and isn't the correct symlink, it's a conflict
    if [ -e "$target_path" ]; then
        conflicts_to_remove+=("$target_path")
        
        # Backup
        if [ ! -d "$BACKUP_DIR" ]; then
            mkdir -p "$BACKUP_DIR"
            echo "Created backup directory: $BACKUP_DIR"
        fi
        
        parent_dir="$BACKUP_DIR/$(dirname "$relative_path")"
        mkdir -p "$parent_dir"
        
        # Use cp to preserve originals during backup phase
        if [ -d "$target_path" ]; then
            cp -r "$target_path" "$BACKUP_DIR/$relative_path"
            echo "  Backed up directory: $relative_path"
        else
            cp -P "$target_path" "$BACKUP_DIR/$relative_path"
            echo "  Backed up file: $relative_path"
        fi
    fi
done < <(find . -mindepth 1 \( -type f -o -type d \) ! -path "./.git/*" ! -name ".git" ! -name "install.sh" ! -name "README.md" ! -name "LICENSE" -print0)

# Now that everything is safely backed up, remove conflicts
if [ ${#conflicts_to_remove[@]} -gt 0 ]; then
    echo ""
    echo "Removing conflicts to make way for symlinks..."
    for conflict in "${conflicts_to_remove[@]}"; do
        echo "  Removing: ${conflict#$HOME/}"
        rm -rf "$conflict"
    done
fi

if [ -d "$BACKUP_DIR" ]; then
    echo ""
    echo "✓ All conflicts backed up to: $BACKUP_DIR"
fi

echo ""
echo "Setting up symlinks with stow..."
if stow --restow --ignore="install.sh" --ignore="README.md" --ignore=".git" --ignore="LICENSE" --verbose=2 . 2>&1 | tee /tmp/stow_output.log; then
    echo "✓ Symlinks created successfully"
else
    echo "✗ Error: Stow failed!"
    echo ""
    echo "Stow output:"
    cat /tmp/stow_output.log
    echo ""
    
    if [ -d "$BACKUP_DIR" ]; then
        echo "RESTORING from backup: $BACKUP_DIR"
        cp -r "$BACKUP_DIR"/. "$HOME/"
        echo "✓ Backup restored"
    fi
    exit 1
fi

# Verify critical files were linked
echo ""
echo "Verifying symlinks..."
critical_files=(".config/tmux/tmux.conf" ".config/nvim")
all_good=true

for file in "${critical_files[@]}"; do
    if [ -e "$HOME/$file" ]; then
        if [ -L "$HOME/$file" ]; then
            echo "  ✓ ~/$file -> $(readlink "$HOME/$file")"
        else
            echo "  ⚠ ~/$file exists but is not a symlink"
        fi
    else
        echo "  ✗ ~/$file missing!"
        all_good=false
    fi
done

if [ "$all_good" = false ]; then
    echo ""
    echo "⚠ Warning: Some expected files are missing"
    echo "Check your dots repo structure:"
    echo "  cd ~/dots && find . -type f | head -20"
fi

# Apply tmux config if tmux is running
if tmux info &>/dev/null 2>&1; then
    echo ""
    echo "Applying tmux config to running session..."
    tmux source-file ~/.config/tmux/tmux.conf 2>/dev/null || true
fi

echo ""
echo "========================"
echo "✓ Setup complete!"
[ -d "$BACKUP_DIR" ] && echo "✓ Backups: $BACKUP_DIR"
echo "✓ Neovim installed"
echo "✓ Reload tmux: prefix + I to install plugins"
echo "========================"
