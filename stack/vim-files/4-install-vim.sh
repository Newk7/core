#!/bin/bash
# shellcheck disable=SC2174,SC1090,SC1091,SC2317

# Common requirements
#
# requires running as root or at least as a user with sudoer access
# requires python 3.8+ loaded with the cmake pip installed

function yellow() { printf "\x1b[38;5;227m%s\e[0m " "${@}"; printf "\n"; }
function warn() { printf "\x1b[38;5;208m%s\e[0m " "${@}"; printf "\n"; }
function green() { printf "\x1b[38;5;048m%s\e[0m " "${@}"; printf "\n"; }
function red() { printf "\x1b[38;5;196m%s\e[0m " "${@}"; printf "\n"; }

vc="/opt/merlion/vim-files/nodejs/create-nodejs-vim-env.sh"
echo "installing node and typescript"
eval "${vc}"
lt="$?"
if [[ "${lt}" -ne 0 ]]; then
    red "failed installing node and typescript with command: ${vc}"
    exit 1
fi

if [[ -e "${HOME}/.vim" ]]; then
    echo "removing previous ${HOME}/.vim"
    vc="rm -rf ${HOME}/.vim"
    eval "${vc}"
fi

# m24 - support for mounting vim plugins on persistent storage under /d
if [[ ! -e /d/vim/build ]]; then
    sudo mkdir /d
    sudo mkdir /d/vim
    sudo mkdir /d/vim/build
    sudo chmod 777 /d /d/vim /d/vim/build
fi
echo "created vim dir on mounted storage: ${HOME}/.vim"
vc="ln -s /d/vim/build ${HOME}/.vim"
eval "${vc}"
lt="$?"
if [[ "${lt}" -ne 0 ]]; then
    red "failed linking vim build dir with command: ${vc}"
    exit 1
fi
vc="ls -lrth ${HOME}/.vim"
eval "${vc}"
export USE_VIM_PYTHON_VERSION="3.12"

function vim_ubuntu_install() {
    yellow "vim_ubuntu_install - installing software-properties-common"
    sudo apt-get install -y software-properties-common
    yellow "vim_ubuntu_install - installing ctag requiremnets"
    # https://github.com/universal-ctags/ctags/blob/master/docs/autotools.rst#gnulinux-distributions
    sudo apt-get install -y \
        autoconf \
        automake \
        build-essential \
        cmake \
        libseccomp-dev \
        libjansson-dev \
        libncurses5-dev \
        libncursesw5-dev \
        libxml2-dev \
        libyaml-dev \
        mono-complete \
        make \
        pkg-config \
        "python${USE_VIM_PYTHON_VERSION}-venv" \
        ripgrep \
        silversearcher-ag \
        universal-ctags \
        vim-nox
    yellow "vim_ubuntu_install - adding toolchain repo"
    sudo add-apt-repository -y ppa:ubuntu-toolchain-r/test
    yellow "vim_ubuntu_install - updating repos"
    sudo apt-get update
    # yellow "vim_ubuntu_install - installing gcc-11 g++-11 gcc-10 g++-10"
    # sudo apt install -y gcc-12 g++12 gcc-11 g++-11 gcc-10 g++-10
    # yellow "vim_ubuntu_install - installing gcc-11 g++-11 gcc-12 g++-12"
    # sudo apt install -y gcc-11 g++-11 gcc-12 g++-12 gcc-13 g++-13 gcc-14 g++-14
    # yellow "vim_ubuntu_install - setting gcc-11 as 91 priority, preferred gcc command"
    # sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 91 --slave /usr/bin/g++ g++ /usr/bin/g++-11 --slave /usr/bin/gcov gcov /usr/bin/gcov-11
    # yellow "vim_ubuntu_install - setting gcc-12 as 92 priority, preferred gcc command"
    # sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 92 --slave /usr/bin/g++ g++ /usr/bin/g++-12 --slave /usr/bin/gcov gcov /usr/bin/gcov-12
    # yellow "vim_ubuntu_install - setting gcc-13 as 93 priority, preferred gcc command"
    # sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-13 93 --slave /usr/bin/g++ g++ /usr/bin/g++-13 --slave /usr/bin/gcov gcov /usr/bin/gcov-13
    yellow "vim_ubuntu_install - setting gcc-14 as 94 priority, preferred gcc command"
    sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-14 94 --slave /usr/bin/g++ g++ /usr/bin/g++-14 --slave /usr/bin/gcov gcov /usr/bin/gcov-14
    yellow "vim_ubuntu_install - confirming compiler version:"
    gcc --version
    g++ --version
    # yellow "vim_ubuntu_install - setting gcc-10 as 91 priority"
    # sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 91 --slave /usr/bin/g++ g++ /usr/bin/g++-10 --slave /usr/bin/gcov gcov /usr/bin/gcov-10
    #
    # example of legacy gcc 7 install and update-alternatives command
    # yellow "vim_ubuntu_install - setting gcc-7 as 70 priority gcc command"
    # sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-7 70 --slave /usr/bin/g++ g++ /usr/bin/g++-7 --slave /usr/bin/gcov gcov /usr/bin/gcov-7
    yellow "vim_ubuntu_install - checking gcc version"
    gcc --version
    mkdir -p -m 777 /opt/vim
    # yellow "vim_ubuntu_install - cloning fzf source"
    # git clone https://github.com/junegunn/fzf.git /opt/vim/fzf
    # yellow "vim_ubuntu_install - building fzf source"
    # /opt/vim/fzf/install --all
    # yellow "vim_ubuntu_install - installing fzf binaries"
    # sudo ln -s /opt/vim/fzf/bin/fzf /usr/local/bin/
    # sudo ln -s /opt/vim/fzf/bin/fzf-tmux /usr/local/bin/
    yellow "vim_ubuntu_install - installing vim-plug"
    # curl -fLo "${HOME}/.vim/autoload/plug.vim" --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
    yellow "vim_ubuntu_install - installing bats"
    vim_install_bats
    yellow "vim_ubuntu_install - installing doq, sphinx with pip and pip3"
    pip install doq sphinx --break-system-packages
    pip3 install doq sphinx --break-system-packages
    yellow "vim_ubuntu_install - done"
} # vim_ubuntu_install - end

function vim_install_bats() {
    if [[ ! -e /usr/bin/bat ]]; then
        # for older versions of ubuntu you have to install from the github release page
        # https://github.com/sharkdp/bat/releases/
        wget https://github.com/sharkdp/bat/releases/download/v0.26.1/bat_0.26.1_amd64.deb -O /tmp/bat_amd64.deb
        sudo dpkg -i /tmp/bat_amd64.deb
    fi
} # vim_install_bats - end

function vim_install_ctags_from_source() {
    # https://github.com/universal-ctags/ctags/blob/master/docs/autotools.rst
    yellow "installing ctags"
    var_cur_dir=$(pwd)
    cd /tmp || return
    if [[ ! -e /tmp/ctags ]]; then
        git clone https://github.com/universal-ctags/ctags.git
        local var_last_status="$?"
        if [[ "${var_last_status}" -ne 0 ]]; then
            red "failed to 'git clone https://github.com/universal-ctags/ctags.git' for ctags support - stopping"
            exit 1
        fi
    fi
    cd /tmp/ctags || return
    ./autogen.sh
    local var_last_status="$?"
    if [[ "${var_last_status}" -ne 0 ]]; then
        red "failed to './autogen.sh' in /tmp/ctags - stopping"
        exit 1
    fi
    ./configure
    local var_last_status="$?"
    if [[ "${var_last_status}" -ne 0 ]]; then
        red "failed to './configure' in /tmp/ctags - stopping"
        exit 1
    fi
    make -j8
    local var_last_status="$?"
    if [[ "${var_last_status}" -ne 0 ]]; then
        red "failed to 'make -j8' in /tmp/ctags - stopping"
        exit 1
    fi
    sudo make install
    local var_last_status="$?"
    if [[ "${var_last_status}" -ne 0 ]]; then
        red "failed to sudo 'sudo make install' in /tmp/ctags - stopping"
        exit 1
    fi
    cd "${var_cur_dir}" || return
    if [[ -e /tmp/ctags ]]; then
        rm -rf /tmp/ctags
    fi
} # vim_install_ctags_from_source - end

function vim_create_dirs() {
    if [[ "${USER}" == "" ]]; then
        var_cur_os_username=$(whoami)
        export USER="${var_cur_os_username}"
    fi
    if [[ "${USE_VIM_DIR}" == "" ]]; then
        export USE_USER_HOME_DIR="/home/${USER}"
        if [[ "${USER}" == "root" ]]; then
            export USE_USER_HOME_DIR="/root"
        fi
        if [[ "${USE_VIM_IN_USER_HOME_DIR}" == "1" ]]; then
            export USE_VIM_DIR="${USE_USER_HOME_DIR}/.vim"
        else
            export USE_VIM_DIR="/opt/vim"
        fi
        export USE_VIM_DIR="${USE_USER_HOME_DIR}/.vim"
        mkdir -p -m 775 "${USE_VIM_DIR}"
        var_last_status="$?"
        if [[ "${var_last_status}" -ne 0 ]]; then
            red "vim_create_dirs - failed to create vim source dir: mkdir -p -m 775 ${USE_VIM_DIR} - stopping"
            exit 1
        fi
    fi
    # 2023-10-16 m24
    if [[ ! -e /d/vim/build ]]; then
        sudo mkdir /d
        sudo mkdir /d/vim
        sudo mkdir /d/vim/build
        sudo chmod 777 /d /d/vim /d/build
    fi
    if [[ -e /d/vim/build ]]; then
        export USE_VIM_DIR="/d/vim/build"
    fi
    export VIM_DIR_BASE="${USE_VIM_DIR}"
    export VIM_DIR_SRC="${VIM_DIR_BASE}/repo"
    # https://github.com/junegunn/vim-plug/wiki/tips#migrating-from-other-plugin-managers
    export VIM_DIR_AUTOLOAD_PLUG="${VIM_DIR_BASE}/autoload/plug.vim"
    export VIM_DIR_PLUGGED="${VIM_DIR_BASE}/plugged"
    if [[ ! -e "${VIM_DIR_PLUGGED}" ]]; then
        mkdir -p -m 775 "${VIM_DIR_PLUGGED}"
        var_last_status="$?"
        if [[ "${var_last_status}" -ne 0 ]]; then
            red "vim_create_dirs - failed to create vim plugged dir: mkdir -p -m 775 ${VIM_DIR_PLUGGED} - stopping"
            exit 1
        fi
    fi
} # vim_create_dirs - end

function vim_mac_install_prep() {
    var_which_xcode_select=$(which xcode-select)
    if [[ "${var_which_xcode_select}" != "" ]]; then
        # you may need to install packages with: xcode-select --install
        yellow "vim_mac_install_prep - installing XQuartz"
        ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)" < /dev/null 2> /dev/null ; brew install caskroom/cask/brew-cask 2> /dev/null
        if [[ "${var_last_status}" -ne 0 ]]; then
            red "vim_mac_install_prep - failed to install xquartz using ruby homebrew - stopping"
            exit 1
        fi
        brew cask install xquartz
        if [[ "${var_last_status}" -ne 0 ]]; then
            red "vim_mac_install_prep - failed to brew cask install xquartz - stopping"
            exit 1
        fi
    fi
} # vim_mac_install_prep - end

function vim_install_from_source() {
    if [[ -e "${VIM_DIR_SRC}" ]]; then
        cd "${VIM_DIR_SRC}" || return
        yellow "updating local vim source build in dir=${VIM_DIR_SRC}"
        git pull
        var_last_status="$?"
        if [[ "${var_last_status}" -ne 0 ]]; then
            red "vim_install_from_source - failed to pull the latest from https://github.com/vim/vim.git - stopping"
            exit 1
        fi
    else
        yellow "cloning vim with command: git clone https://github.com/vim/vim.git ${VIM_DIR_SRC}"
        git clone https://github.com/vim/vim.git "${VIM_DIR_SRC}"
        var_last_status="$?"
        if [[ "${var_last_status}" -ne 0 ]]; then
            red "vim_install_from_source - failed to clone https://github.com/vim/vim.git - stopping"
            exit 1
        fi
        cd "${VIM_DIR_SRC}" || return
    fi
    yellow "cleaning previous build if found"
    make distclean
    var_last_status="$?"
    if [[ "${var_last_status}" -ne 0 ]]; then
        red "vim_install_from_source - failed to make dist clean"
        exit 1
    fi

    # 2023-10-11
    #
    # if you want to install a newer python
    # please ensure the command:
    # python3-config --configdir
    # /usr/lib/python3.11/config-3.11-x86_64-linux-gnu
    #
    # works as intended for the new version
    #
    # here's how to check:
    #
    # python3-config --configdir
    #
    # update-alternatives --list python3
    #
    # sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 120
    # sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 110
    # sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 100
    #
    # ls -l /usr/bin/python3-config
    # ls -l /usr/bin/python3*
    # sudo rm  /usr/bin/python3-config
    # sudo ln -s /usr/bin/python3.11-config /usr/bin/python3-config
    # deactivate > /dev/null 2>&1
    # python3-config --configdir
    #
    var_python3_config_dir=$(python3-config --configdir)
    # var_python3_config_dir="/usr/lib/python3.11/config-3.11-x86_64-linux-gnu"
    if [[ ! -e "${var_python3_config_dir}" ]]; then
        red "vim_install_from_source - failed to find python ${USE_VIM_PYTHON_VERSION} config dir: ${var_python3_config_dir} - stopping"
        warn "please install python${USE_VIM_PYTHON_VERSION} and retry"
        exit 1
    fi
    yellow "configuring vim with python3 config dir: ${var_python3_config_dir}"
    # this does not work on python 3.8 anymore
    # https://stackoverflow.com/questions/3373914/compiling-vim-with-python-support
    # apt-get install vim-gtk works on ubuntu 20.04
    ./configure \
        --enable-multibyte \
        --enable-python3interp=dynamic \
        --with-python3-config-dir="${var_python3_config_dir}" \
        --enable-gui=auto \
        --enable-cscope \
        --with-features=huge \
        --enable-fontset \
        --enable-largefile \
        --disable-netbeans \
        --with-features=huge \
        --with-compiledby="${USER}" \
        --enable-fail-if-missing \
        --with-tlib=ncurses
    var_last_status="$?"
    if [[ "${var_last_status}" -ne 0 ]]; then
        red "vim_install_from_source - failed to configure vim"
        exit 1
    fi
    yellow "making vim"
    make -j8
    var_last_status="$?"
    if [[ "${var_last_status}" -ne 0 ]]; then
        err "vim_install_from_source - failed to make vim"
        exit 1
    fi
    yellow "sudo installing vim"
    sudo make install
    var_last_status="$?"
    if [[ "${var_last_status}" -ne 0 ]]; then
        red "vim_install_from_source - failed to install vim"
        exit 1
    fi
    which vim > /dev/null 2>&1
    var_last_status="$?"
    if [[ "${var_last_status}" -ne 0 ]]; then
        red "vim_install_from_source - failed to install vim from source - stopping"
        exit 1
    fi
    yellow "vim install done"
} # vim_install_from_source - end

function vim_install_ycm() {
    var_cur_dir=$(pwd)
    if [[ -e "${VIM_DIR_PLUGGED}/YouCompleteMe" ]]; then
        cd "${VIM_DIR_PLUGGED}/YouCompleteMe" || return
        git pull
        var_last_status="$?"
        if [[ "${var_last_status}" -ne 0 ]]; then
            red "vim_install_ycm - failed to pull latest for https://github.com/ycm-core/YouCompleteMe - stopping"
            exit 1
        fi
    else
        git clone https://github.com/ycm-core/YouCompleteMe "${VIM_DIR_PLUGGED}/YouCompleteMe"
        var_last_status="$?"
        if [[ "${var_last_status}" -ne 0 ]]; then
            red "vim_install_ycm - failed to clone https://github.com/ycm-core/YouCompleteMe - stopping"
            exit 1
        fi
    fi
    cd "${VIM_DIR_PLUGGED}/YouCompleteMe" || return
    yellow "vim_install_ycm - cloning submodules"
    git submodule update --init --recursive
    var_last_status="$?"
    if [[ "${var_last_status}" -ne 0 ]]; then
        red "vim_install_ycm - failed to update recursive sub modules for YouCompleteMe - stopping"
        exit 1
    fi
    var_which_python=$(which python)
    # have not set up the go or java completers
    # var_install_args="--go-completer --rust-completer --clang-completer"
    # var_install_args="--rust-completer --clang-completer"
    #
    # NOTE
    #
    # validated on 2021-12-01 - the '--rust-completer' argument crushes cpu + memory + disk - uses the syntastic plugin instead of this
    # and save your disk
    #
    var_install_args_base="--clang-completer --rust-completer --go-completer --ts-completer"
    var_install_args_base="--clang-completer --rust-completer --ts-completer --go-completer"
    var_install_args="${var_install_args_base}"
    if [[ "${USER}" == "root" ]]; then
        var_install_args="${var_install_args_base} --force-sudo"
    fi

    echo ""
    yellow "vim_install_ycm - starting ycm install with ${var_which_python} and ${var_install_args}"
    # vc="CC=gcc-14 CXX=g++14 ./install.py ${var_install_args}"
    # vc="CC=gcc-14 CXX=g++14 ./install.py --all"
    # vc="./install.py --all"
    # vc="./install.py --clang-completer"
    vc="./install.py --clang-completer --rust-completer --ts-completer --go-completer"
    echo ""
    eval "${vc}"
    var_last_status="$?"
    if [[ "${var_last_status}" -ne 0 ]]; then
        red "vim_install_ycm - failed to install with ${var_which_python} and ${var_install_args} - stopping"
        echo -e "\n${vc}\n"
        exit 1
    fi
} # vim_install_ycm - end

function vim_install_tools_using_plug() {
    cd "${var_cur_dir}" || return
    if [[ ! -e "${VIM_DIR_AUTOLOAD_PLUG}" ]]; then
        yellow "vim_install_tools_using_plug - installing vim-plug:"
        echo "  curl -fLo ${HOME}/.vim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim"
        vc="curl -fLo ${VIM_DIR_AUTOLOAD_PLUG} --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim"
        # vc="curl -fLo ${VIM_DIR_AUTOLOAD_PLUG} \"https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim\""
        eval "${vc}"
        lt="$?"
        if [[ "${lt}" -ne 0 ]]; then
            red "vim_install_tools_using_plug - failed to install vim-plug - stopping"
            echo -e "\n${vc}\n"
            exit 1
        fi
        detected_dirname=$(dirname "${VIM_DIR_AUTOLOAD_PLUG}")
        if [[ ! -e "${detected_dirname}" ]]; then
            red "vim_install_tools_using_plug - failed to install detect autoload plug dir: ${VIM_DIR_AUTOLOAD_PLUG} - stopping"
            exit 1
        fi
        chmod 777 "${detected_dirname}"
    fi
    # yellow "vim_install_tools_using_plug - installing all vim plugins with: vim +PluginInstall +qall"
    # vim +PluginInstall +qall
    # vim -es -u vimrc -i NONE -c "PlugInstall" -c "qa"
    var_last_status="$?"
    if [[ "${var_last_status}" -ne 0 ]]; then
        red "vim_install_tools_using_plug - failed to install vim plugins - stopping"
        echo "vim -es -u vimrc -i NONE -c PlugInstall -c qa"
        exit 1
    fi
    yellow "ycm install done"
} # vim_install_tools_using_plug - end

function run_main() {
    var_is_ubuntu=$(which lsb_release 2> /dev/null)
    if [[ "${var_is_ubuntu}" != "" ]]; then
        vim_ubuntu_install
    fi
    vim_create_dirs
    vim_mac_install_prep
    vim_install_ctags_from_source
    vim_install_from_source
    # now handled by ~/.vimrc after reading: https://github.com/ycm-core/YouCompleteMe/issues/1751#issuecomment-273380629
    # vim_install_ycm
    vim_install_tools_using_plug
    if [[ -e /usr/bin/vi ]]; then
        echo "renaming /usr/bin/vi to prevent legacy vi to load"
        sudo mv /usr/bin/vi /usr/bin/backup-vi
    fi
    green "vim and ycm install done"
} # run_main - end

run_main

exit 0
