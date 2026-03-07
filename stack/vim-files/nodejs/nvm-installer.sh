#!/bin/bash

function install_nvm() {
    # https://github.com/nvm-sh/nvm
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
}


# Call the function
install_nvm
