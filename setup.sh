#!/usr/bin/env bash

set -Eeuo pipefail                      #Exit script on cmd fail
trap 'error_handler $? $LINENO' SIGINT SIGTERM

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)     #Change location to script dir
libraries=("curl" "jq" "unzip" "wget" "ufw")
today=$(date +"%D %T")

usage() {
    cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v] [-f] -p param_value arg1 [arg2...]

Script description here.

Available options:

-h, --help              Print this help and exit
-v, --verbose           Print script debug info

-d, --dir               The directory to use for the install of both the game and the manager ("/opt" by default)
-f, --force-download    Force to re-download the necessary file even if they are already present in /tmp
-g, --game-version      Install a specific factorio version ("latest" by default)
-i, --install-pkg       Automatically install the missing packages needed for this script (using apt) instead of exiting the script with an error.
-m, --manager-version   Install a specific factorio-server-manager version ("latest" by default, "dev" for the dev branch)
-s, --skip              Skip an install part (either "game" of "manager")
-p, --platform          Target platform ("linux" by default)
-u, --user              Create a new "factorio" user instead of the current one, as suggested in https://wiki.factorio.com/Multiplayer.

EOF
    exit
}

error_handler() {
    trap - SIGINT SIGTERM ERR
    if [ -z ${game_archive_name+x} ]
    then
        sudo rm -rf $tmp/${game_archive_name}
    fi
    if [ -z ${manager_archive_name+x} ]
    then
        sudo rm -rf $tmp/${manager_archive_name}
    fi
    msg "${RED}Exiting after error ${1-'n/a'} occurs on line ${2-'n/a'} \nCheck '${log_file}' for details."
}


setup_colors() {
    if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
    NOFORMAT='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[1;33m'
    else
    NOFORMAT='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
    fi
    running="[${BLUE}.${NOFORMAT}]"
    succed="[${GREEN}V${NOFORMAT}]"
    failed="[${RED}X${NOFORMAT}]"
    skipped="[${YELLOW}-${NOFORMAT}]"
    warning="[${ORANGE}O${NOFORMAT}]"
}

msg() {
    if [ "${2-}" == "-c" ]
    then 
        for ((i = 0; i < ${3-}; i++))
        do
            echo >&2 -e -n "\e[1A\r\e[K" >&5
        done
        echo >&2 -e "${1-}" >&5
    elif [ "${2-}" == "-e" ]
    then 
        echo >&2 -e -n "\e[${3-}A\r\e[K${1-}" >&5
        echo >&2 -e -n "\e[${3-}B\r" >&5
    else
        echo >&2 -e "${1-}" >&5
    fi
    echo >&2 "${1-}" >> ${log_file} 
}


die() {
    local msg=$1
    local code=${2-1} # default exit status 1
    msg "$msg"
    exit "$code"
}

parse_params() {
    # default values of variables set from params
    force_dl=0
    install_missing_pkg=0
    clean=0
    create_user=0
    install_dir="/opt"
    game_version="latest"
    manager_version="latest"
    skip=0
    platform="linux"
    log_file="/home/${USER}/.factorio_setup.log"
    web_port=0
    
    while :; do
        case "${1-}" in
            -h | --help) usage ;;
            -v | --verbose) set -x ;;
            --no-color) NO_COLOR=1 ;;

            -c | --clean) clean=1 ;;
            -d | --dir) install_dir=1 ;;
            -f | --force-download) force_dl=1 ;;
            -u | --user) create_user=1 ;;

            -i | --install-pkg)
                install_missing_pkg=1 ;;
            -l | --log)
                log_file="${2-}"
                shift
                ;;
            -g | --game-version)
                game_version="${2-}"
                shift
                ;;
            -m | --manager-version)
                manager_version="${2-}"
                shift
                ;;
            -r | --remove) remove ;;
            -s | --skip)
                skip="${2-}"
                shift
                ;;
            -p | --platform)
                platform="${2-}"
                shift
                ;;
            -fw | --firewall) web_port=1 ;;
            -?*) die "Unknown option: $1" ;;
            *) break ;;
        esac
        shift
    done

    args=("$@")

    # check required params and arguments
    #[[ -z "${param-}" ]] && die "Missing required parameter: param"
    #[[ ${#args[@]} -eq 0 ]] && die "Missing script arguments"

    return 0
}

remove() {
    sudo rm -rf ${install_dir}/factorio
    sudo rm -rf ${install_dir}/factorio-server-manager
    exit
}

install_pkg() {
    missing=1
    msg "\t${warning} Missing some libraries."
    if [ "${install_missing_pkg-}" == 0 ]
    then
        ## Prompt the user 
        msg "\t${ORANGE}Do you want to install missing libraries? [Y/n]:${NOFORMAT}"
        read -r answer
        msg "" -c 2
    else
        answer=Y
    fi
    if [[ $answer =~ [Yy] ]]
    then
        msg "\t${running} Installing missing libraries" -e 1
        sudo apt-get -y install ${libraries[@]} >> ${log_file}
    else
        die "Missing library"
    fi
    msg "\t${succed} Missing libraries installed" -e 1  
}

init() {
    msg "${running} Initialisation"
    nb_line=1

    if ! sudo -vn 2> /dev/null
    then
        msg "\t${running} sudo permission needed"
        ((nb_line++))
        sudo -v
        msg "\t${succed} sudo permission granted" -c 2
    fi

    ## Run the install_pkg function if sany of the libraries are missing
    missing=0
    dpkg -s "${libraries[@]}" >/dev/null 2>&1 || install_pkg
    if [ $missing == 0 ]
    then
        msg "\t${succed} No library to install"
        ((nb_line++))
    fi

    if [ $create_user == 1 ]
    then
        msg "\t${running} User 'factorio' setup"
        ((nb_line++))
        if grep -q "^factorio:" /etc/passwd ;then
            msg "\t${skipped} User 'factorio' already exist" -e 1
        else
            msg "\t${running} New user 'factorio' creation" -e 1
            sudo useradd -p wube factorio >> ${log_file}
            msg "\t${succed} new user 'factorio' created with default password ${BLUE}'wube'${NOFORMAT}" -e 1
        fi
    fi

    msg "${succed} Initialisation" -e $nb_line
}

install_game() {
    if [ "${skip}" == "game" ]
    then
        msg "${skipped} Skipped game installation"
        return
    fi

    msg "${running} Game installation (factorio '${game_version}' for '${platform}')"
    game_archive_name="factorio_${game_version}_${platform}64.tar.xz"
    nb_line=1
    
    msg "\t${running} Checking for existing installation" 
    ((nb_line++))
    if [ -d "${install_dir}/factorio" ]; then
        msg "\t${running} Removing existing installation" -e 1
        sudo rm -rf -v "${install_dir}/factorio" >> ${log_file}
        msg "\t${succed} Existing installation removed" -e 1
    else
        msg "\t${succed} No existing install found" -e 1
    fi

    msg "\t${running} Checking for archive"
    ((nb_line++))
    if [ "${force_dl}" == 1 ] || [ ! -f "/tmp/${game_archive_name}" ]
    then
        msg "\t${running} Downloading archive from https://www.factorio.com/get-download/" -e 1
        sudo wget https://www.factorio.com/get-download/${game_version}/headless/${platform}64 -O /tmp/${game_archive_name} -nv --show-progress --progress=bar:force 2>&5
        msg "\t${succed} Archive download succesfull" -c 4
    else
        msg "\t${succed} Found existing archive in dir '/tmp'. Use '-f' to ignore existing file and download anyway" -e 1
    fi

    msg "\t${running} Archive extraction to '${install_dir}'"
    ((nb_line++))
    sudo tar -xvf /tmp/${game_archive_name} -C ${install_dir} >> ${log_file}
    msg "\t${succed} Archived extracted" -e 1

    if [ $create_user == 1 ]
    then
        msg "\t${running} Ownership attribution of '${install_dir}/factorio' to 'factorio' user"
        ((nb_line++))
        sudo chown -R factorio:factorio ${install_dir}/factorio >> ${log_file}
        msg "\t${succed} Ownership of '${install_dir}/factorio' attributed to 'factorio' user" -e 1
    else
        sudo chown -R $USER:$USER ${install_dir}/factorio >> ${log_file}
    fi

    if [ $clean == 1 ]
    then
        msg "\t${running} Cleaning temporary files"
        ((nb_line++))
        sudo rm -v /tmp/${game_archive_name} >> ${log_file}
        msg "\t${succed} Temporary file cleaned" -e 1
    fi

    msg "${succed} Game installation (factorio '${game_version}' for '${platform}')" -e $nb_line

}

install_manager() {
     if [ "${skip}" == "manager" ]
    then
        msg "${skipped} Skipped manager installation"
        return
    fi


    msg "${running} Manager installation (fsm '${manager_version}' for '${platform}')"
    nb_line=1
    
    if [ "${manager_version}" == "latest" ]
    then 
        manager_version=$(curl -sL https://api.github.com/repos/OpenFactorioServerManager/factorio-server-manager/releases/latest | jq -r ".tag_name")
    fi
    manager_archive_name="factorio-server-manager-${platform}-${manager_version}.zip"

    msg "\t${running} Checking for existing installation" 
    ((nb_line++))
    if [ -d "${install_dir}/factorio-server-manager" ]; then
        msg "\t${running} Removing existing installation" -e 1
        sudo rm -rf -v "${install_dir}/factorio-server-manager" >> ${log_file}
        msg "\t${succed} Existing installation removed" -e 1
    else
        msg "\t${succed} No existing install found" -e 1
    fi

    msg "\t${running} Checking for archive"
    ((nb_line++))
    if [ "${force_dl}" == 1 ] || [ ! -f "/tmp/${manager_archive_name}" ]
    then
        msg "\t${running} Downloading archive from https://github.com/OpenFactorioServerManager/factorio-server-manager/releases/download/" -e 1
        sudo wget https://github.com/OpenFactorioServerManager/factorio-server-manager/releases/download/${manager_version}/${manager_archive_name} -O /tmp/${manager_archive_name} -nv --show-progress --progress=bar:force 2>&5
        msg "\t${succed} Archive download succesfull" -c 7
    else
        msg "\t${succed} Found existing archive in dir '/tmp'. Use '-f' to ignore existing file and download anyway" -e 1
    fi

    msg "\t${running} Extracting archive to '${install_dir}'"
    ((nb_line++))
    sudo unzip -o /tmp/${manager_archive_name} -d ${install_dir} >> ${log_file}
    msg "\t${succed} Archive extraction succesfull" -e 1

    if [ $create_user == 1 ]
    then
        msg "\t${running} Ownership attribution of '${install_dir}/factorio-server-manager' to 'factorio' user"
        ((nb_line++))
        sudo chown -R factorio:factorio ${install_dir}/factorio-server-manager >> ${log_file}
        msg "\t${succed} Ownership of '${install_dir}/factorio-server-manager' attributed to 'factorio' user" -e 1
    else
        sudo chown -R $USER:$USER ${install_dir}/factorio-server-manager >> ${log_file}
    fi

    if [ $clean == 1 ]
    then
        msg "\t${running} Cleaning temporary files"
        ((nb_line++))
        sudo rm -v /tmp/${manager_archive_name} >> ${log_file}
        msg "\t${succed} Temporary file cleaned" -e 1
    fi

    if [ $web_port == 1 ]
    then
        msg "\t${running} Allowing port 80 for web server"
        ((nb_line++))
        sudo ufw allow 80
        msg "\t${succed} Port 80 open for web server" -e 1
    fi
    
    sudo setcap 'cap_net_bind_service=+ep' ${install_dir}/factorio-server-manager/factorio-server-manager
    msg "${succed} Manager installed (fsm '${manager_version}' for '${platform}')" -e $nb_line

    msg "${BLUE}\tInstruction to start the server manager:"
    if [ $create_user == 1 ]
    then
        msg "\t  Switch to user 'factorio' (i.e. 'su - factorio')"
    fi

    msg "\t  Go to directory '/opt/factorio-server-manager'"
    msg "\t  Run './factorio-server-manager --dir /opt/factorio'"
    msg "\t  The manager web page will be available at 'localhosh:80${NOFORMAT}"
}



parse_params "$@"
setup_colors
echo "${today}" > ${log_file}
exec 5<&1
exec 1>> ${log_file} 2>&1

# script logic here
init
install_game
install_manager