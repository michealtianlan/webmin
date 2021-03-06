#!/usr/bin/env bash
#############################################################################
# Update webmin/usermin to the latest develop version  from GitHub repo
# inspired by authentic-theme/theme-update.sh script, thanks qooob
#
# Version 1.4, 2018-01-31
#
# Kay Marquardt, kay@rrr.de, https://github.com/gandelwartz
#############################################################################

# Get webmin/usermin dir based on script's location
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROD=${DIR##*/} # => usermin or webmin
# where to get source
HOST="https://github.com"
REPO="webmin/$PROD"
ASK="YES"
GIT="git"

# temporary locations for git clone
WTEMP="${DIR}/.~files/webadmin" 
UTEMP="${DIR}/.~files/useradmin" 
TEMP=$WTEMP
[[ "$PROD" == "usermin" ]] && TEMP=$UTEMP
LTEMP="${DIR}/.~lang"

# don't ask -y given
if [[ "$1" == "-y" || "$1" == "-yes"  || "$1" == "-f" || "$1" == "-force" ]] ; then
        ASK="NO"
        shift
fi

# predefined colors for echo -e on terminal
if [[ -t 1 && ${ASK} == "YES" ]] ;  then
    RED='\e[49;0;31;82m'
    BLUE='\e[49;1;34;182m'
    GREEN='\e[49;32;5;82m'
    ORANGE='\e[49;0;33;82m'
    PURPLE='\e[49;1;35;82m'
    LGREY='\e[49;1;37;182m'
    GREY='\e[1;30m'
    CYAN='\e[36m'
    NC='\e[0m'
fi

# help requested output usage
if [[ "$1" == "-h" || "$1" == "--help" ]] ; then
    echo -e "${NC}${ORANGE}This is the unofficial webmin update script${NC}"
    echo "Usage:  ./`basename $0` [-force] [-repo:username/xxxmin] [-release[:number]]"
    [[ "$1" == "--help" ]] && cat <<EOF

Parameters:
    -force (-yes)
        unattended install, do not ask
    -repo
        pull from alternative github repo, format: -repo:username/reponame
        reponame can be "webmin" or "usermin"
        default github repo: webmin/webmin
    -release
        pull a released version, default release: -release:latest

Exit codes:
    0 - success
    1 - abort on error or user request, nothing changed
    2 - not run as root
    3 - git not found
    4 - stage 1: git clone failed
    5 - stage 2: makedist failed
    6 - stage 3: update with setup.sh failed, installation may in bad state!

EOF
    exit 0
fi

if [[ "${PROD}" != "webmin" && "${PROD}" != "usermin" ]] ; then
    echo -e "${NC}${RED}error: the current dir name hast to be webmin or usermin, no update possible!${NC}"
    echo -e "possible solution: ${ORANGE}ln -s ${PROD} ../webmini; cd ../webmin${NC} or ${ORANGE}ln -s ${PROD} ../usermin; cd ../webmin ${NC}"
    exit 1
fi

# need to be root 
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: This command has to be run under the root user.${NC}"
    exit 2
fi

# git has to be installed
echo -en "${CYAN}search minserv.conf ... ${NC}"
if [[ -f "/etc/webmin/miniserv.conf" ]] ; then
     # default location
    MINICONF="/etc/webmin/miniserv.conf"
    echo  -e "${ORANGE}found: ${MINICONF}${NC}"
else
    # possible other locations
    MINICONF=`find /* -maxdepth 6 -name miniserv.conf 2>/dev/null | grep ${PROD} | head -n 1`
    echo  -e "${ORANGE}found: ${MINICONF}${NC} (alternative location)"
fi
[[ "${MINICONF}" != "" ]] && export PATH="${PATH}:`grep path= ${MINICONF}| sed 's/^path=//'`"

if type ${GIT} >/dev/null 2>&1 ; then
    true
else
    echo -e "${RED}Error: Command \`git\` is not installed or not in the \`PATH\`.${NC}"
    exit 3
fi


################
# lets start
# Clear screen for better readability
[[ "${ASK}" == "YES" ]] && clear

# alternative repo given
if [[ "$1" == *"-repo"* ]]; then
        if [[ "$1" == *":"* ]] ; then
          REPO=${1##*:}
          [[ "${REPO##*/}" != "webmin" && "${REPO##*/}" != "usermin" ]] && echo -e "${RED}error: ${ORANGE} ${REPO} is not a valid repo name!${NC}" && exit 0
          shift
        else
          echo -e "${ORANGE}./`basename $0`:${NC} found -repo without parameter"
          exit 1
        fi
fi

# warn about possible side effects because webmins makedist.pl try cd to /usr/local/webmin (and more)
[[ -d "/usr/local/webadmin" ]] && echo -e "${RED}Warning:${NC} /usr/local/webadmin ${ORANGE}exist, update may fail!${NC}"

################
# really update?
REPLY="y"

if [ "${ASK}" == "YES" ] ; then
    if [[ "$1" != "-release"* ]] ; then
        echo -e "${RED}Warning:${NC} ${ORANGE}update from non release repository${NC} $HOST/$REPO ${ORANGE}may break your installation!${NC}"
    fi
    read -p "Would you like to update "${PROD^}" from ${HOST}/${REPO} [y/N] " -n 1 -r
    echo
fi

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
   # something different the y entered
   echo -e "${PURPLE}Operation aborted.${NC}"
   exit 1
fi

################
# here we go

  # remove temporary files from failed run
  rm -rf .~files
  # pull source from github
  if [[ "$1" == *"-release"* ]]; then
        if [[ "$1" == *":"* ]] && [[ "$1" != *"latest"* ]]; then
          RRELEASE=${1##*:}
        else
          RRELEASE=`curl -s -L https://github.com/${REPO}/blob/master/version  | sed -n '/id="LC1"/s/.*">\([^<]*\).*/\1/p'`
        fi
        echo -e "${CYAN}Pulling in latest release of${NC} ${ORANGE}${PROD^}${NC} $RRELEASE ($HOST/$REPO)..."
        RS="$(${GIT} clone --depth 1 --branch $RRELEASE -q $HOST/$REPO.git "${TEMP}" 2>&1)"
        if [[ "$RS" == *"ould not find remote branch"* ]]; then
          ERROR="Release ${RRELEASE} doesn't exist. "
        fi
  else
        echo -e "${CYAN}Pulling in latest changes for${NC} ${ORANGE}${PROD^}${NC} $RRELEASE ($HOST/$REPO) ..."
        ${GIT} clone --depth 1 --quiet  $HOST/$REPO.git "${TEMP}"
  fi
  # on usermin!! pull also webmin to resolve symlinks later!
  WEBMREPO=`echo ${REPO} | sed "s/\/usermin$/\/webmin/"`
  if [[ "${REPO}" != "${WEBMREPO}" ]]; then
        echo -e "${CYAN}Pulling in latest changes for${NC} ${ORANGE}Webmin${NC} ($HOST/$WEBMREPO) ..."
        ${GIT} clone --depth 1 --quiet  $HOST/$WEBMREPO.git "${WTEMP}"
  fi

  # Check for possible errors
  if [ $? -eq 0 ] && [ -f "${TEMP}/version" ]; then

        ####################
        # start processing pulled source
        version="`head -c -1 ${TEMP}/version`-`cd ${TEMP}; ${GIT} log -1 --format=%cd --date=format:'%m%d.%H%M'`" 
        DOTVER=`echo ${version} | sed 's/-/./'`
        TARBALL="${TEMP}/tarballs/${PROD}-${DOTVER}"
        ###############
        # FULL update
        echo -e "${CYAN}start FULL update for${NC} $PROD ..."
        # create missing dirs, simulate authentic present
        mkdir ${TEMP}/tarballs ${TEMP}/authentic-theme 
        cp authentic-theme/LICENSE ${TEMP}/authentic-theme
        # run makedist.pl
        ( cd ${TEMP}; perl makedist.pl ${DOTVER} ) 
        if [[ ! -f "${TEMP}/tarballs/webmin-${DOTVER}.tar.gz" ]] ; then
            echo -e "${RED}Error: makedist.pl failed! ${NC}aborting ..."
            rm -rf .~files
            exit 5
        fi

        # check for additional standard modules
        # fixed list better than guessing?
        for module in `ls */module.info`
        do 
            if [[ -f ${TEMP}/${module} && ! -f  "${TARBALL}/$module" ]]; then
              module=`dirname $module`
              echo "Adding nonstandard $module" && cp -r -L ${TEMP}/${module} ${TARBALL}/
            fi
        done

        # prepeare unattended upgrade
        echo "${version}" >"${TARBALL}/version"
        cp "${TEMP}/chinese-to-utf8.pl" .
        echo  -en "${CYAN}search for config dir ... ${NC}"
        config_dir=`grep env_WEBMIN_CONFIG= ${MINICONF}| sed 's/.*_WEBMIN_CONFIG=//'`
        echo  -e "${ORANGE}found: ${config_dir}${NC}"
        atboot="NO"
        makeboot="NO"
        nouninstall="YES"
        #nostart="YES"
        export config_dir atboot nouninstall makeboot nostart
        ( cd ${TARBALL}; ./setup.sh ${DIR} ) | grep -v -e "^$" -e "done$" -e "chmod" -e "chgrp" -e "chown"
        if [[ "${TARBALL}/version" -nt "${MINICONF}" ]] ; then
            echo -e "${RED}Error: update failed, ${PROD} may in a bad state! ${NC}aborting ..."
            rm -rf .~files
            exit 6
        fi

        #############
        # postprocessing

        # "compile" UTF-8 lang files
        echo -en "\n${CYAN}compile UTF-8 lang files${NC} ..."
        if [[ `which iconv 2> /dev/null` != '' ]] ; then
            perl "${TEMP}/chinese-to-utf8.pl" . 2>&1 | while read input; do echo -n "."; done
        else
            echo -e "${BLUE} iconv not found, skipping lang files!${NC}"
        fi

        # update authentic, put dummy clear in PATH
        echo -e "#!/bin/sh\necho" > ${TEMP}/clear; chmod +x ${TEMP}/clear
        export PATH="${TEMP}:${PATH}"
        # check if alternatve repo exist
        AUTHREPO=`echo ${REPO} | sed "s/\/.*min$/\/autehtic-theme/"`
        if [[ "${REPO}" != "${AUTHREPO}" ]]; then
             exist=`curl -s -L ${HOST}/${AUTHREPO}`
             [[ "${#exist}" -lt 20 ]] && RREPO="${AUTHREPO}"
        fi
        # run authenric-thme update, possible unattended
        if [[ -x authentic-theme/theme-update.sh ]] ; then
            if [[ "${ASK}" == "YES" ]] ; then
                authentic-theme/theme-update.sh ${RREPO}
            else
                yes | authentic-theme/theme-update.sh ${RREPO}
            fi
        fi
  else
        # something went wrong
        echo -e "${RED}${ERROR}Updating files, failed.${NC}"
        exit 4
  fi

  ###########
  # we are at the end, clean up

  # remove temporary files
  echo -e "\n${BLUE}clean up temporary files ...${NC}"
  rm -rf .~files .~lang
  # fix permissions, should be done by makedist.pl?
  echo -e "${CYAN}make scripts executable ...${NC}"
  chmod -R -x+X ${DIR}
  chmod +x *.pl *.cgi *.pm *.sh */*.pl */*.cgi */*.pm */*.sh
      
  # thats all folks
  echo -e "\n${CYAN}Updating ${PROD^} to Version `cat version`, done.${NC}"

# update success
exit 0
