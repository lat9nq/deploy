#!/bin/bash
# deploy-msys.sh [executable]
#   (Simplified) bash re-implementation of [linuxdeploy](https://github.com/linuxdeploy).
#   Reads [executable] and copies required libraries to [AppDir]/usr/lib
#   Copies the desktop and svg icon to [AppDir]
#   Respects the AppImage excludelist
#
# Unlike linuxdeploy, this does not:
# - Copy any icon other than svg (too lazy to add that without a test case)
# - Do any verification on the desktop file
# - Run any linuxdeploy plugins
# - *Probably other things I didn't know linuxdeploy can do*
#
# It notably also does not copy unneeded libraries, unlike linuxdeploy. On a desktop system, this
# can help reduce the end AppImage's size, although in a production system this script proved
# unhelpful.
#~ set -x
export _OBJDUMP_FLUFF="DLL Name: "
export _MINGW_PREFIX="/mingw64"
export _SEARCH_PATHS="$(echo -n ${_MINGW_PREFIX}/bin | tr ':' ' ')"
export _DEPLOY_QT=0
export _QT_PLUGIN_PATH="${_MINGW_PREFIX}/share/qt5/plugins"
export _EXCLUDES='ADVAPI32.dll AVRT.dll bcrypt.dll CRYPT32.dll d3d11.dll dwmapi.dll dxgi.dll \
GDI32.dll IMM32.dll IPHLPAPI.DLL KERNEL32.dll MPR.dll msvcrt.dll NETAPI32.dll ole32.dll \
OLEAUT32.dll OPENGL32.dll SETUPAPI.dll SHELL32.dll USER32.dll USERENV.dll UxTheme.dll VERSION.dll \
WINMM.dll WS2_32.dll WTSAPI32.dll DWrite.dll RPCRT4.dll USP10.dll'

# find_library [library]
#   Finds the full path of partial name [library] in _SEARCH_PATHS
#   This is a time-consuming function.
_NOT_FOUND=""
function find_library {
    local _PATH=""
    for i in ${_SEARCH_PATHS}; do
        _PATH=$(find $i -regex ".*$(echo -n $1 | tr '+' '.')" -print -quit)
        if [ "$_PATH" != "" ]; then
            break
        fi
    done
    if [ "$_PATH" != "" ]; then
        echo -n $(readlink -e $_PATH)
    fi
}

# get_dep_names [object]
#   Returns a space-separated list of all required libraries needed by [object].
function get_dep_names {
    echo -n $(objdump -p $1 | grep "${_OBJDUMP_FLUFF}" |  sed "s/${_OBJDUMP_FLUFF}//")
}

# get_deps [object] [library_path]
#   Finds and installs all libraries required by [object] to [library_path].
#   This is a recursive function that also depends on find_library.
function get_deps {
    local _DEST=$2
    local _EXCL=
    for i in $(get_dep_names $1); do
        _EXCL=`echo "$_EXCLUDES" | tr ' ' '\n' | grep $i`
        if [ "$_EXCL" != "" ]; then
            #>&2 echo "$i is on the exclude list... skipping"
            continue
        fi
        if [ -f $_DEST/$i ]; then
            continue
        fi
        local _LIB=$(find_library $i)
        if [ -z $_LIB ]; then
            echo -n "$i:"
            continue
        fi
        >&2 cp -v $_LIB $_DEST/$i
        get_deps $_LIB $_DEST
    done
}

export -f get_deps
export -f get_dep_names
export -f find_library

_ERROR=0
if [ -z $1 ]; then
    _ERROR=1
fi

if [ $_ERROR -eq 1 ]; then
    >&2 echo "usage: $0 <executable> [-qt]"
    exit 1
fi

if [[ "$2" == "-qt" ]]; then
    _DEPLOY_QT=1
fi

LIB_DIR=$(dirname $(readlink -e $1))
mkdir -p $LIB_DIR
_NOT_FOUND=$(get_deps $1 $LIB_DIR)

if [ $_DEPLOY_QT -eq 1 ]; then
    mkdir -p platforms imageformats styles
    cp -nv "${_QT_PLUGIN_PATH}/platforms/qwindows.dll" platforms/
    #~ cp -rnv "${_QT_PLUGIN_PATH}/mediaservice/" ./
    cp -rnv ${_QT_PLUGIN_PATH}/imageformats/*.dll ./imageformats
    cp -rnv ${_QT_PLUGIN_PATH}/styles/*.dll ./styles
    touch qt.conf

	# Find any remaining libraries needed for Qt libraries
    _NOT_FOUND+=$(get_deps platforms/qwindows.dll $LIB_DIR)
    _NOT_FOUND+=$(find $(pwd)/imageformats -type f -exec bash -c "get_deps {} $LIB_DIR" ';')
    _NOT_FOUND+=$(find $(pwd)/styles -type f -exec bash -c "get_deps {} $LIB_DIR" ';')
fi

if [ "${_NOT_FOUND}" != "" ]; then
    >&2 echo "WARNING: failed to find the following libraries:"
    >&2 echo "$(echo -n $_NOT_FOUND | tr ':' '\n' | sort -u)"
fi

