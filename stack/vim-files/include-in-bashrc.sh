# shellcheck disable=1090

function v() {
    var_num_files="$#"
    var_custom_vimrc_dir="/opt/merlion/vim-files/custom-vimrcs"
    export USER_VIMRC="${var_custom_vimrc_dir}/any-filetype-vimrc-coc.vimrc"
    if [[ "${var_num_files}" == 1 ]] && [[ -e "${var_custom_vimrc_dir}" ]]; then
        var_file_path="${1}"
        if [[ -e "${var_file_path}" ]]; then
            extension=$(basename "$var_file_path" | awk -F '.' '{print $NF}')
            date -u > /tmp/.vimrc_extension
            echo "extension: ${extension}" >> /tmp/.vimrc_extension
            if [[ "${extension}" == "sh" ]]; then
                export USER_VIMRC="${var_custom_vimrc_dir}/bash-vimrc-coc.vimrc"
            elif [[ "${extension}" == "tf" ]]; then
                export USER_VIMRC="${var_custom_vimrc_dir}/bash-vimrc-coc.vimrc"
            elif [[ "${extension}" == "rs" ]]; then
                export USER_VIMRC="${var_custom_vimrc_dir}/rust-vimrc-coc.vimrc"
            elif [[ "${extension}" == "py" ]]; then
                export USER_VIMRC="${var_custom_vimrc_dir}/python-vimrc-coc.vimrc"
            elif [[ "${extension}" == "tsx" ]] || [[ "${extension}" == "ts" ]] || [[ "${extension}" == "jsx" ]] || [[ "${extension}" == "js" ]] || [[ "${extension}" == "css" ]] || [[ "${extension}" == "html" ]] || [[ "${extension}" == "prisma" ]]; then
                export USER_VIMRC="${var_custom_vimrc_dir}/js-vimrc-coc.vimrc"
            fi
            echo "using vimrc: ${USER_VIMRC}" >> /tmp/.vimrc_extension
        fi
    fi
    init_fzf_for_vim
    py_path=$(which python)
    py_dirname=$(dirname "${py_path}")
    py_activate="${py_dirname}/activate"
    # echo "activated: ${py_activate}"
    deactivate > /dev/null 2>&1 || true
    vim -u "${USER_VIMRC}" "${@}"
    if [[ -e "${py_activate}" ]]; then
        source "${py_activate}"
    fi
    init_fzf_for_bash
} # vi - end

alias vi='v'
alias vim='v'
