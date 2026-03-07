#!/bin/bash

function install_nodejs_version() {
  local node_version="25.2.1"
  local install_dir="/opt/public/node"
  local node_tar="https://nodejs.org/dist/v${node_version}/node-v${node_version}-linux-x64.tar.xz"

  echo "installing node version: ${node_version}"

  # Follow-up question: Should we check if the installation directory already exists and has a different content?
  if [ -d "$install_dir" ]; then
    echo "Warning: The directory '$install_dir' already exists."
    read -r -p "Do you want to proceed and overwrite its contents? (y/n): " confirm
    if [[ $confirm != "y" ]]; then
      echo "Installation aborted."
      exit 1
    fi
  else
    mkdir -p "$install_dir"
  fi

  cd "$install_dir" || return

  pwd
  local commands=(
    "wget $node_tar"
    "tar xvf node-v${node_version}-linux-x64.tar.xz"
    "cd node-v${node_version}-linux-x64"
    "sudo cp -r bin/* /usr/local/bin/"
    "sudo cp -r include/* /usr/local/include/"
    "sudo cp -r lib/* /usr/local/lib/"
  )

  for cmd in "${commands[@]}"; do
    echo "running command: ${cmd}"
    eval "${cmd}"
    local exit_status=$?
    if [[ "${exit_status}" -ne 0 ]]; then
      echo "Failed running command: ${cmd}"
      exit 1
    fi
  done

  # Business use case consideration: Verify node and npm versions to ensure successful installation
  if command -v node &>/dev/null; then
    node_version=$("node --version")
    echo "Node.js version: $node_version"
  else
    echo "Node.js not found in system PATH."
    exit 1
  fi

  if command -v npm &>/dev/null; then
    npm_version=$("npm version")
    echo "npm version: $npm_version"
  else
    echo "npm not found in system PATH."
    exit 1
  fi

  echo "Node.js and npm installed successfully."
  npm install typescript
  npm install -g typescript
  npm install yarn
  npm install -g yarn
  exit 0
}


# Call the function
install_nodejs_version
