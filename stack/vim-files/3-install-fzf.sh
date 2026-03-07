#!/bin/bash

# https://github.com/junegunn/fzf#using-git
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install

if [[ -e "${HOME}/.fzf/bin/fzf" ]]; then
    echo "instaling fzf using sudo to /usr/bin/fzf"
    sudo cp "${HOME}/.fzf/bin/fzf" /usr/bin/fzf
    lt="$?"
    if [[ "${lt}" -ne 0 ]]; then
        echo " - failed to install fzf into /usr/bin/fzf - pathing may fail"
    fi
fi
