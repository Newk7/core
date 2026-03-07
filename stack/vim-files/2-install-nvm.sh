#!/bin/bash

function install_nvm() {
    # https://github.com/nvm-sh/nvm
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash

    nvm install v25.6.1
    nvm alias default 25.2.1
}


# Call the function
install_nvm
