#!/bin/bash

#
# chkdeps.sh - Check Dependencies for Build
#
# This source-code is part of Windows XP stuff for XFCE:
# <<https://www.oddmatics.uk>>
#
# Author(s): Rory Fewell <roryf@oddmatics.uk>
#

#
# CONSTANTS
#
CURDIR=`realpath -s "./"`
SCRIPTDIR=`dirname "$0"`

REPO_ROOT=`realpath -s "${SCRIPTDIR}/.."`

SH_DISTID="${SCRIPTDIR}/distid.sh"
DEPMAP_PY="${REPO_ROOT}/tools/bldutils/depmap/depmap.py"



#
# ARGUMENTS
#
OPT_BUILDLIST="${SCRIPTDIR}/targets"
OPT_USE_LOCAL_LIBS=0

while getopts "c:hl" opt;
do
    case "${opt}" in
        c)
            OPT_BUILDLIST="${OPTARG}"
            ;;

        h)
            echo "Usage: chkdeps.sh [-chl]"
            echo ""
            echo " -c : provide a list of components (default 'targets')"
            echo " -h : display this help screen"
            echo " -l : use wintc libraries compiled here, not system"
            echo ""

            exit 0
            ;;

        l)
            OPT_USE_LOCAL_LIBS=1
            ;;
    esac
done



#
# FUNCTIONS
#
declare -a g_needed_pkgs

check_deps()
{
    local rel_dir="${1}"
    local full_target_dir="${REPO_ROOT}/${rel_dir}"
    local full_deps_path="${full_target_dir}/deps"

    # If there are dependencies to check, then call the depsmap tool
    #
    if [[ ! -f "${full_deps_path}" ]]
    then
        return 0
    fi

    local required_deps
    required_deps=`python3 ${DEPMAP_PY} ${full_deps_path} ${dist_id}`

    if [[ $? -gt 0 ]]
    then
        echo "Failed to map dependencies."
        exit 1
    fi

    # Check what we have
    #
    while IFS= read -r mapping;
    do
        local pkg_name=""

        if [[ "${mapping}" =~ ^(bt|bt,rt):(.+)$ ]]
        then
            pkg_name="${BASH_REMATCH[2]}"
        else
            continue
        fi

        # Is this one of ours?
        #
        if [[ "${pkg_name}" =~ wintc-(.+) ]]
        then
            # If this is a lib, we need to check deps
            #
            local chk_lib_rel_dir="shared/${BASH_REMATCH[1]}"

            if [[ -d "${REPO_ROOT}/${chk_lib_rel_dir}" ]]
            then
                check_deps "${chk_lib_rel_dir}"
            fi

            # If we're building our own libs locally instead of system installed
            # then do not add them to dependencies
            #
            if [[ $OPT_USE_LOCAL_LIBS -eq 1 ]]
            then
                continue
            fi
        fi

        # Check we haven't already got this dep in our list
        #
        for list_pkg in "${g_needed_pkgs[@]}"
        do
            if [[ "${list_pkg}" == "${pkg_name}" ]]
            then
                continue 2
            fi
        done

        # It's a new dep, check whether it is already installed
        #
        case "${dist_id}" in
            archpkg)
                pacman -Q -k "${pkg_name}" >/dev/null 2>&1
                ;;
            deb)
                dpkg -s "${pkg_name}" >/dev/null 2>&1
                ;;
        esac

        if [[ $? -gt 0 ]]
        then
            g_needed_pkgs+=("${pkg_name}")
        fi
    done <<< "${required_deps}"
}



#
# MAIN SCRIPT
#
if [[ ! -f "${SH_DISTID}" ]]
then
    echo "distid.sh not found - this should never happen!!"
    exit 1
fi

if [[ ! -f "${DEPMAP_PY}" ]]
then
    echo "depmap tool not found - this should never happen!!"
    exit 1
fi

if [[ ! -f "${OPT_BUILDLIST}" ]]
then
    echo "Build list not found or readable: ${OPT_BUILDLIST}"
    exit 1
fi

# Identify our distro
#
dist_id=`"${SH_DISTID}"`

if [[ $? -gt 0 ]]
then
    echo "Failed to identify distribution."
    exit 1
fi

# Iterate through components to build now, identify their deps
#
while IFS= read -u "${buildlist_fd}" -r rel_target_dir
do
    check_deps "${rel_target_dir}"
done {buildlist_fd}<"${OPT_BUILDLIST}"

# Output what needs to be installed
#
if [[ "${#g_needed_pkgs[@]}" -eq 0 ]]
then
    echo "All dependencies verified."
    exit 0
fi

for pkg_not_installed in "${g_needed_pkgs[@]}"
do
    echo "needed:${pkg_not_installed}"
done

exit 2
