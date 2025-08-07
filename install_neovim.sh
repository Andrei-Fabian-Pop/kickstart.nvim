#!/bin/bash

# Install latest neovim ppa
sudo add-apt-repository ppa:neovim-ppa/unstable
sudo apt update
sudo apt install neovim clangd npm

# Install the kickstart distro
git clone https://github.com/Andrei-Fabian-Pop/kickstart.nvim.git "${XDG_CONFIG_HOME:-$HOME/.config}"/nvim --branch work
