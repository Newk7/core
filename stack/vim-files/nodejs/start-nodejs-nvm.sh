#!/bin/bash

function install_nvm_runtime() {
    # https://github.com/nvm-sh/nvm
    echo "installing nvm nodejs runtime"
    export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm list
    nvm install v25.2.1
    nvm use v25.2.1
    nvm list
    echo "done installing nvm nodejs runtime"
}


# Call the function
install_nvm_runtime
