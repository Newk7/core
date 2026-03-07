#!/bin/bash

function install_nodejs_runtime_for_vim() {
    # install nodejs
    echo "install nodejs with typescript"
    ./nodejs/typescript-nodejs-installer.sh
    # install nvm
    echo "install nvm"
    ./nodejs/nvm-installer.sh
    echo "install node runtime with nvm"
    ./nodejs/start-nodejs-nvm.sh
}


# Call the function
install_nodejs_runtime_for_vim
