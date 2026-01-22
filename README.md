# MY DOTFILES

## Install

Run the following command to install the dotfiles:

```bash
curl -fsSL https://raw.githubusercontent.com/s0rus/dots/main/install.sh | bash
```

## Manual Installation

### Requirements

Before cloning make sure you have installed the following:

### tmux

```bash
pacman -S tmux
```

### Tmux Plugin Manager

```bash
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

### Stow

```bash
pacman -S stow
```

### Clone the repository and create symlinks

If you have everything installed,
you can setup the dotfiles by running the following commands:

```bash
cd ~ && git clone https://github.com/s0rus/dots.git
cd dots && stow . --adopt
```

I am using these dotfiles in the following setup:

- [Omarchy](https://github.com/basecamp/omarchy)
- [Ghostty](https://github.com/ghostty-org/ghostty)
- [nvim](https://github.com/neovim/neovim)
