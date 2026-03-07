#!/bin/bash
# shellcheck disable=SC2174,SC1091,SC2317

function yellow() { printf "\x1b[38;5;227m%s\e[0m " "${@}"; printf "\n"; }
function warn() { printf "\x1b[38;5;208m%s\e[0m " "${@}"; printf "\n"; }
function green() { printf "\x1b[38;5;048m%s\e[0m " "${@}"; printf "\n"; }
function red() { printf "\x1b[38;5;196m%s\e[0m " "${@}"; printf "\n"; }

# setting this to 1 will enable the baremetal/ui installers
install_server_with_ui=0

function install_upgrades_for_baremetal() {
    os_name=$(uname -r)
    echo "installing upgrades for baremetal - ${os_name} - not a guest vm"
    sudo apt-get install -y \
        linux-tools-common \
        linux-headers-generic \
        "linux-headers-${os_name}" \
        "linux-image-${os_name}"
}

function setup_bootup_fixes() {
    setup_no_restart
    setup_short_grub
}

function setup_no_restart() {
    sudo systemctl disable systemd-networkd-wait-online.service
    sudo systemctl mask systemd-networkd-wait-online.service
}

function setup_short_grub() {
    test_exist=$(grep -c "nrconf{restart} = 'a'" /etc/needrestart/needrestart.conf)
    if [[ "${test_exist}" -eq 0 ]]; then
        echo "\$nrconf{restart} = 'a';" >> /etc/needrestart/needrestart.conf
    fi
    # 3 second boot menu
    sudo sed -i 's/GRUB_TIMEOUT=0/GRUB_TIMEOUT=3/g' /etc/default/grub
}

function install_core_tools() {
    sudo chmod 777 /opt
    vc="apt-get update -y"
    eval "${vc}"
    lt="$?"
    if [[ "${lt}" -ne 0 ]]; then
        red "failed to update repos with command: ${vc}"
        exit 1
    fi
    echo ""
    echo "installing build tools"
    apt-get install -y \
        apt-utils \
        aptitude \
        apt-transport-https \
        build-essential \
        cmake \
        dkms \
        gcc \
        git ca-certificates \
        make \
        software-properties-common
    lt="$?"
    if [[ "${lt}" -ne 0 ]]; then
        red "failed to install build tools - stopping"
        exit 1
    fi
    echo ""
    add-apt-repository ppa:deadsnakes/ppa -y
    lt="$?"
    if [[ "${lt}" -ne 0 ]]; then
        red "failed to get python 3.12 repo - stopping"
        exit 1
    fi
    apt update
    echo "installing packages"
    packages="acpid \
        apache2-utils \
        autoconf \
        automake \
        autotools-dev \
        binutils \
        bzip2 \
        btop \
        ca-certificates \
        caribou \
        cracklib-runtime \
        curl \
        debianutils \
        dnsutils \
        docutils-common \
        dosfstools \
        e2fsprogs \
        espeak \
        ffmpeg \
        fuse-overlayfs \
        fwupd \
        fwupdate \
        gdb \
        gdbserver \
        gettext \
        gettext-base \
        git \
        git-lfs \
        graphviz \
        graphviz-dev \
        gstreamer1.0-alsa \
        gstreamer1.0-clutter-3.0 \
        gstreamer1.0-packagekit \
        gstreamer1.0-plugins-base \
        gstreamer1.0-plugins-base-apps \
        gstreamer1.0-plugins-good \
        gstreamer1.0-pulseaudio \
        gstreamer1.0-tools \
        gstreamer1.0-x \
        gparted \
        gzip \
        htop \
        imagemagick \
        iw \
        iotop \
        jq \
        libaio-dev \
        libarchive-dev \
        libarchive13 \
        libappindicator3-1 \
        libappstream-glib8 \
        libbluetooth3 \
        libcurl4-openssl-dev \
        libcrack2 \
        libffi-dev \
        libgssapi3-heimdal \
        libgstreamer-plugins-base1.0-0 \
        libgstreamer-plugins-good1.0-0 \
        libgstreamer1.0-0 \
        libgtk-3-dev \
        libguestfs-tools \
        libicu-dev \
        libjansson-dev \
        libpq-dev \
        libmp3lame-dev \
        libncurses6 \
        libncurses-dev \
        libopencv-dev \
        libpoppler-cpp-dev
        libseccomp-dev \
        libssl-dev \
        libxml2 \
        libxml2-dev \
        libxslt1-dev \
        libxcursor-dev \
        libyaml-dev \
        logrotate \
        lshw \
        lsof \
        ltrace \
        m4 \
        man \
        mbrola \
        mplayer \
        mtools \
        nano \
        net-tools \
        ncdu \
        ntpdate \
        openssh-client \
        openssh-server \
        openssl \
        parted \
        poppler-utils \
        perl \
        postgresql \
        postgresql-client-common \
        postgresql-contrib \
        procps \
        qpdf \
        readline-common \
        redis-tools \
        rfkill \
        rsync \
        rsyslog \
        rtkit \
        shellcheck \
        strace \
        tar \
        tcl \
        tcpdump \
        telnet \
        terminator \
        tk \
        tree \
        tzdata \
        unzip \
        usb-creator-common \
        usb-modeswitch \
        usb-modeswitch-data \
        usbutils \
        virtualenv \
        wget \
        wireless-regdb \
        wireless-tools \
        wpasupplicant \
        xxd \
        zip \
        zlib1g"

    for i in $packages; do
        is_installed=$(apt-get install -s git | grep -c "already the")
        lt="0"
        if [[ "${is_installed}" == "0" ]]; then
            echo "Installing: ${i}"
            apt-get install -y "${i}"
            lt="$?"
            last_step="install"
        else
            echo "Upgrading: ${i}"
            apt-get install -y "${i}"
            lt="$?"
            last_step="upgrade"
        fi

        if [[ "${lt}" != "0" ]]; then
            echo ""
            echo "Failed to ${last_step} package ${i}"
            echo "apt-get install -y ${i}"
            echo ""
            exit 1
        fi
    done

    vc="sudo apt-get install -y git subversion cmake libx11-dev libxxf86vm-dev libxcursor-dev libxi-dev libxrandr-dev libxinerama-dev libegl-dev mbrola-us1 mbrola-us2 mbrola-us3"
    eval "${vc}"
    lt="$?"
    if [[ "${lt}" != "0" ]]; then
        red "failed to install packages for blender with command: ${vc}"
        exit 1
    fi

    vc="sudo apt install -y libwayland-dev wayland-protocols libxkbcommon-dev libdbus-1-dev linux-libc-dev"
    eval "${vc}"
    lt="$?"
    if [[ "${lt}" != "0" ]]; then
        red "failed to install additional blender packages with command: ${vc}"
        exit 1
    fi

    apt-get install -y build-essential
    apt-get install -y libglib2.0-dev zlib1g cmake libssl-dev libsasl2-dev libzstd-dev zlib1g-dev libxml2-dev libgl1-mesa-glx
    apt-get install -y libgl1-mesa-glx mesa-utils libgl1-mesa-dri libglib2.0-0 libglib2.0-dev glib-networking glibmm-2.4
    apt-get install -y pkg-config python3-dev
    apt-get install -y libpq-dev postgresql-client
    apt-get install -y ffmpeg libavutil-dev libavformat-dev libavcodec-dev python3-pydub python3-pyaudio python3-tk libncurses5-dev libgdbm-dev libreadline-dev libffi-dev
    ln -s /usr/bin/ffmpeg /usr/local/bin/ffmpeg
    apt-get install -y python3-pip python3-tk libncurses5-dev libgdbm-dev libreadline-dev libffi-dev
    apt-get install -y antiword catdoc libpoppler-cpp-dev poppler-utils
    apt-get install -y git openssl tar unzip jq
    apt-get install -y texlive-latex-base
    apt-get install -y texlive-fonts-recommended
    apt-get install -y texlive-fonts-extra
    apt-get install -y texlive-latex-extra
    apt-get install -y pandoc curl wget fonts-dejavu
    apt-get install -y libpangocairo-1.0-0 libpango-1.0-0 libcairo2
    apt-get install -y libevent-2.1-7 libgstreamer-plugins-base1.0-0
    apt-get install -y ripgrep tesseract-ocr libreoffice

    systemctl start acpid
    systemctl enable acpid

    if [[ ! -e /data ]]; then
        mkdir -p -m 777 /data
    fi

    echo "uninstalling update-notifier"
    sudo apt-get remove -y update-notifier

    lt="$?"
    if [[ "${lt}" -ne 0 ]]; then
        red "failed to install build tools - stopping"
        exit 1
    fi
} # install_core_tools - end

function install_go() {
    # https://go.dev/dl/
    GO_VERSION="1.26.0"
    GO_OS="linux"
    GO_ARCH="amd64"
    go_artifact_name="go${GO_VERSION}.${GO_OS}-${GO_ARCH}"
    go_artifact="${go_artifact_name}.tar.gz"
    go_file="/tmp/${go_artifact}"
    if [[ ! -e ${go_file} ]]; then
        curl "https://dl.google.com/go/${go_artifact}" --output "${go_file}"
        sudo tar -C /usr/local -xzf ${go_file}

        export GOROOT=/usr/local/go
        export GOPATH=$HOME/go
        export PATH=$PATH:$GOROOT/bin:$GOPATH/bin
    fi

    if [[ ! -e /opt/go ]]; then
        mkdir /opt/go
        chmod 777 /opt/go
    fi
    if [[ ! -e /opt/go/lazygit ]]; then
        echo "cloning lazygit to /opt/go/lazygit"
        git clone https://github.com/jesseduffield/lazygit.git /opt/go/lazygit
        var_cur_dir=$(pwd)
        cd /opt/go/lazygit || return
        go install
        go build
        sudo cp ./lazygit /usr/bin/lazygit
        cd "${var_cur_dir}" || return
    fi
    which cfssl > /dev/null 2>&1
    is_cfssl_installed=$?
    if [[ "${is_cfssl_installed}" -ne 0 ]]; then
        echo "installing cfssl with go"
        ./files/cfssl/install.sh
    fi
} # install_go - end

function disable_screensaver_and_screenlock() {
    gsettings set org.gnome.desktop.session idle-delay 0
    gsettings set org.gnome.desktop.screensaver lock-enabled false
} # disable_screensaver_and_screenlock - end

function enable_only_lightdb() {
    sudo systemctl stop lightdm
    sudo systemctl disable lightdm
    sudo systemctl mask lightdm
    sudo systemctl stop gdm
    sudo systemctl disable gdm
    sudo systemctl mask gdm
}

function install_python312() {
    echo "installing python 3.12"
    sudo apt-get install -y \
        python3 \
        python3-apport \
        python3-certifi \
        python3-dev \
        python3-docutils \
        python3-pip \
        python3-pygments \
        python3-roman \
        python3-setuptools \
        python3-tk \
        python3-venv

    # echo "checking defaults for system python:"
    # sudo update-alternatives --display python
    # python --version
    # python3 --version

    # echo "installing python 3 config"
    # sudo rm -f /usr/bin/python3-config
    # sudo ln -s /usr/bin/python3.11-config /usr/bin/python3-config

    # higher priority wins

    # 2023-10-17 - python3.10 is required on ubuntu 22.04.3
    #
    # python3.10 is the highest priority
    # echo "installing python 3 alternative priorities"
    # sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.10 5
    # sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1
    # sudo update-alternatives --install /usr/bin/python python3 /usr/bin/python3.10 5
    # sudo update-alternatives --install /usr/bin/python python3 /usr/bin/python3.11 1


    # echo "installing pip alternative priorities"
    # sudo mv /usr/bin/pip /usr/bin/org-pip
    # sudo update-alternatives --install /usr/bin/pip pip /usr/local/bin/pip3.11 1
    # sudo update-alternatives --install /usr/bin/pip pip /usr/local/bin/pip3.10 5

    # echo "after - default pip:"
    # sudo update-alternatives --display pip
    # pip --version

    # echo "after - default python 3:"
    # sudo update-alternatives --display python
    # python --version
    # python3 --version
}

function set_system_time_to_utc() {
    use_tz=/usr/share/zoneinfo/UTC
    if [[ -e /etc/localtime ]]; then
        rm -f /etc/localtime
    fi
    if [[ -e "${use_tz}" ]]; then
        echo "installing timezone: ${use_tz}"
        ln -s "${use_tz}" /etc/localtime
    fi
    date
}

function setup_data_dirs() {
    mkdir -p -m 777 /opt/merlion
    mkdir -p -m 777 /data/ebs1/customers/merliondev.com/data
}

function install_xfce_and_lightdm() {
    # if you need x windows
    apt-get install -y "lightdm xfce4 xfce4-goodies"
}

set_system_time_to_utc
setup_bootup_fixes
if [[ "${install_server_with_ui}" -eq 1 ]]; then
    install_upgrades_for_baremetal
fi
install_core_tools
install_go
disable_screensaver_and_screenlock
if [[ "${install_server_with_ui}" -eq 1 ]]; then
    enable_only_lightdb
fi
install_python312
if [[ "${install_server_with_ui}" -eq 1 ]]; then
    install_xfce_and_lightdm
fi
setup_data_dirs

exit 0
