#!/bin/bash
# deploy-mingw.sh [executable]
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
export _PREFIX="/usr"
export _SEARCH_PATHS="$(echo -n ${_PREFIX}/lib64 | tr ':' ' ')"
export _DEPLOY_QT=0
export _QT_PLUGIN_PATH="${_PREFIX}/lib64/qt5/plugins"
export _EXCLUDES="ld-linux.so.2 ld-linux-x86-64.so.2 libanl.so.1 libBrokenLocale.so.1 libcidn.so.1 \
libc.so.6 libdl.so.2 libm.so.6 libmvec.so.1 libnss_compat.so.2 libnss_dns.so.2 libnss_files.so.2 \
libnss_hesiod.so.2 libnss_nisplus.so.2 libnss_nis.so.2 libpthread.so.0 libresolv.so.2 librt.so.1 \
libthread_db.so.1 libutil.so.1 libstdc++.so.6 libGL.so.1 libEGL.so.1 libGLdispatch.so.0 \
libGLX.so.0 libOpenGL.so.0 libdrm.so.2 libglapi.so.0 libgbm.so.1 libxcb.so.1 libX11.so.6 \
libasound.so.2 libfontconfig.so.1 libthai.so.0 libfreetype.so.6 libharfbuzz.so.0 libcom_err.so.2 \
libexpat.so.1 libgcc_s.so.1 libgpg-error.so.0 libICE.so.6 libp11-kit.so.0 libSM.so.6 \
libusb-1.0.so.0 libuuid.so.1 libz.so.1 libpangoft2-1.0.so.0 libpangocairo-1.0.so.0 \
libpango-1.0.so.0 libgpg-error.so.0 libjack.so.0 libxcb-dri3.so.0 libxcb-dri2.so.0 \
libfribidi.so.0 libgmp.so.10"

# find_library [library]
#  Finds the full path of partial name [library] in _SEARCH_PATHS
#  This is a time-consuming function.
_NOT_FOUND=""
function find_library {
  local _PATH=""
  for i in ${_SEARCH_PATHS}; do
    _PATH=$(find $i -maxdepth 1 -regex ".*$(echo -n $1 | tr '+' '.')" -print -quit)
    if [ "$_PATH" != "" ]; then
      break
    fi
  done
  if [ "$_PATH" != "" ]; then
    echo -n $(readlink -e $_PATH)
  fi
}

# get_dep_names [object]
#  Returns a space-separated list of all required libraries needed by [object].
function get_dep_names {
  echo -n $(patchelf --print-needed $1)
}

# get_deps [object] [library_path]
#  Finds and installs all libraries required by [object] to [library_path].
#  This is a recursive function that also depends on find_library.
function get_deps {
  local _DEST=$2
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
  cp -nv "${_QT_PLUGIN_PATH}/platforms/libqxcb.so" platforms/
  #~ cp -rnv "${_QT_PLUGIN_PATH}/mediaservice/" ./
  cp -rnv ${_QT_PLUGIN_PATH}/imageformats/*.so ./imageformats
  cp -rnv ${_QT_PLUGIN_PATH}/styles/*.so ./styles
  touch qt.conf

	# Find any remaining libraries needed for Qt libraries
  _NOT_FOUND+=$(get_deps platforms/libqxcb.so $LIB_DIR)
  _NOT_FOUND+=$(find $(pwd)/imageformats -type f -exec bash -c "get_deps {} $LIB_DIR" ';')
  _NOT_FOUND+=$(find $(pwd)/styles -type f -exec bash -c "get_deps {} $LIB_DIR" ';')
fi

if [ "${_NOT_FOUND}" != "" ]; then
  >&2 echo "WARNING: failed to find the following libraries:"
  >&2 echo "$(echo -n $_NOT_FOUND | tr ':' '\n' | sort -u)"
fi

