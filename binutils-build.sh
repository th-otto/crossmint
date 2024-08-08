#!/bin/sh

#
# This script is for building the binutils
# for the cross-compiler
#

me="$0"

unset CDPATH
unset LANG LANGUAGE LC_ALL LC_CTYPE LC_TIME LC_NUMERIC LC_COLLATE LC_MONETARY LC_MESSAGES

scriptdir=${0%/*}
scriptdir=`cd "${scriptdir}"; pwd`

PACKAGENAME=binutils
VERSION=-2.43
VERSIONPATCH=-20240808
REVISION="GNU Binutils for MiNT ${VERSIONPATCH#-}"

TARGET=${1:-m68k-atari-mint}
if test "$TARGET" = m68k-atari-mintelf; then
REVISION="GNU Binutils for MiNT ELF ${VERSIONPATCH#-}"
fi
PREFIX=/usr

case `uname -s` in
	MINGW* | MSYS*) here=/`pwd -W | tr '\\\\' '/' | tr -d ':'` ;;
	*) here=`pwd` ;;
esac

#
# where to look for 3rd party libraries like zstd etc.
# Should be a static compiled version, so the
# compiler does not depend on non-standard shared libs
# We will compile now the required libraries before
# trying to compile binutils/gcc, in order to produce universal
# libraries for darwin
#
CROSSTOOL_DIR="$HOME/crosstools"

ARCHIVES_DIR=$HOME/packages
BUILD_DIR="$here"
MINT_BUILD_DIR="$BUILD_DIR/binutils-build"
PKG_DIR="$here/binary7-package"
DIST_DIR="$here/pkgs"

srcdir="${PACKAGENAME}${VERSION}"

#
# The branch patch was created by
# BINUTILS_SUPPORT_DIRS="libsframe bfd gas include libiberty libctf opcodes ld elfcpp gold gprof gprofng intl setup.com makefile.vms cpu zlib"
# git diff binutils-2_29_1.1 binutils-2_29-branch -- $BINUTILS_SUPPORT_DIRS
# BINUTILS_SUPPORT_DIRS is from src-release.sh
#
# The mint patch can be recreated by running
# git diff binutils-2_42-branch binutils-2_42-mint
# in my fork (https://github.com/th-otto/binutils/)
#
PATCHES="\
        patches/binutils/${PACKAGENAME}${VERSION}-mint${VERSIONPATCH}.patch \
"
ALLPATCHES="$PATCHES \
        patches/binutils/binutils-m68k-segmentalign.patch \
        zstd-for-gcc.sh \
"

TAR=${TAR-tar}
TAR_OPTS=${TAR_OPTS---owner=0 --group=0}

BUILD_EXEEXT=
LN_S="ln -s"
GCC=${GCC-gcc}
GXX=${GXX-g++}
case `uname -s` in
	MINGW64*) host=mingw64; MINGW_PREFIX=/mingw64; ;;
	MINGW32*) host=mingw32; MINGW_PREFIX=/mingw32; ;;
	MINGW*) if echo "" | ${GCC} -dM -E - 2>/dev/null | grep -q i386; then host=mingw32; else host=mingw64; fi; MINGW_PREFIX=/$host ;;
	MSYS*) host=msys ;;
	CYGWIN*) if echo "" | ${GCC} -dM -E - 2>/dev/null | grep -q i386; then host=cygwin32; else host=cygwin64; fi ;;
	Darwin*) host=macos; STRIP=strip; TAR_OPTS= ;;
	*) host=linux64
	   if echo "" | ${GCC} -dM -E - 2>/dev/null | grep -q i386; then
	      host=linux32
	      PKG_DIR="$PKG_DIR-32bit"
	      export PATH=$PKG_DIR/usr/bin:$PATH
	   fi
	   ;;
esac
case $host in
	cygwin* | mingw* | msys*) BUILD_EXEEXT=.exe ;;
esac
case $host in
	mingw* | msys*) LN_S="cp -p" ;;
esac

if test ! -f ".patched-${PACKAGENAME}${VERSION}"; then
	for f in "$ARCHIVES_DIR/${PACKAGENAME}${VERSION}.tar.xz" \
	         "$ARCHIVES_DIR/${PACKAGENAME}${VERSION}.tar.bz2" \
	         "${PACKAGENAME}${VERSION}.tar.xz" \
	         "${PACKAGENAME}${VERSION}.tar.bz2"; do
		if test -f "$f"; then $TAR xf "$f" || exit 1; fi
	done
	if test ! -d "$srcdir"; then
		echo "$srcdir: no such directory" >&2
		exit 1
	fi
	for f in $PATCHES; do
	  if test -f "$f"; then
	    cd "$srcdir" && patch -p1 < "$BUILD_DIR/$f" || exit 1
	  else
	    echo "missing patch $f" >&2
	    exit 1
	  fi
	  cd "$BUILD_DIR"
	done
	touch ".patched-${PACKAGENAME}${VERSION}"
fi

if test ! -d "$srcdir"; then
	echo "$srcdir: no such directory" >&2
	exit 1
fi
srcdir=`cd "$srcdir"; pwd`

# we may need to regenerate some file in the source tree,
# if it is a git repo
cd "$srcdir/ld"
if test ldlex.l -nt ldlex.c; then rm -f ldlex.c; fi
if test ldgram.y -nt ldgram.c; then rm -f ldgram.c ldgram.h; fi
if test deffilep.y -nt deffilep.c; then rm -f deffilep.c deffilep.h; fi
cd "$BUILD_DIR"

if test -d /usr/lib64 -a $host = linux64; then
	BUILD_LIBDIR=${PREFIX}/lib64
else
	BUILD_LIBDIR=${PREFIX}/lib
fi

JOBS=`rpm --eval '%{?jobs:%jobs}' 2>/dev/null`
P=$(getconf _NPROCESSORS_CONF 2>/dev/null || nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null)
if test -z "$P"; then P=$NUMBER_OF_PROCESSORS; fi
if test -z "$P"; then P=1; fi
if test -z "$JOBS"; then
  JOBS=$P
else
  test 1 -gt "$JOBS" && JOBS=1
fi
JOBS=-j$JOBS
MAKE=${MAKE:-make}

#
# try config.guess from automake first to get the
# canonical build system name.
# On some distros it is patched to have the
# vendor name included.
#
for a in "" -1.16 -1.15 -1.14 -1.13 -1.12 -1.11 -1.10; do
	BUILD=`/usr/share/automake${a}/config.guess 2>/dev/null`
	test "$BUILD" != "" && break
	test "$host" = "macos" && BUILD=`/opt/local/share/automake${a}/config.guess 2>/dev/null`
	test "$BUILD" != "" && break
done
test "$BUILD" = "" && BUILD=`$srcdir/config.guess`

bfd_targets="--enable-targets=$BUILD"
enable_plugins=--disable-plugins
enable_lto=--disable-lto
ranlib=ranlib
STRIP=${STRIP-strip -p}

# binutils ld does not have support for darwin target anymore
test "$host" = "macos" && bfd_targets=""

# add opposite of default mingw32 target for binutils,
# and also host target
case "${TARGET}" in
    x86_64-*-mingw*)
    	if test -n "${bfd_targets}"; then bfd_targets="${bfd_targets},"; else bfd_targets="--enable-targets="; fi
	    bfd_targets="${bfd_targets}i686-pc-mingw32"
    	;;
    i686-*-mingw*)
    	if test -n "${bfd_targets}"; then bfd_targets="${bfd_targets},"; else bfd_targets="--enable-targets="; fi
    	bfd_targets="${bfd_targets}x86_64-w64-mingw64"
		;;
    *-*-*elf* | *-*-linux* | *-*-darwin*)
    	enable_lto=--enable-lto
		enable_plugins=--enable-plugins
    	ranlib=gcc-ranlib
		;;
esac
case "${TARGET}" in
    m68k-atari-mintelf*)
    	if test -n "${bfd_targets}"; then bfd_targets="${bfd_targets},"; else bfd_targets="--enable-targets="; fi
    	bfd_targets="${bfd_targets}m68k-atari-mint"
		;;
    m68k-atari-mint*)
    	if test -n "${bfd_targets}"; then bfd_targets="${bfd_targets},"; else bfd_targets="--enable-targets="; fi
    	bfd_targets="${bfd_targets}m68k-atari-mintelf"
		;;
    *-*-darwin*)
    	if test -n "${bfd_targets}"; then bfd_targets="${bfd_targets},"; else bfd_targets="--enable-targets="; fi
        bfd_targets="${bfd_targets}aarch64-apple-darwin"
		;;
esac

rm -rf "$MINT_BUILD_DIR"
mkdir -p "$MINT_BUILD_DIR"

cd "$MINT_BUILD_DIR"

glibc_hack=false
if test "`lsb_release -s -i 2>/dev/null`" = openSUSE; then
	glibc_hack=true
fi

CFLAGS_FOR_BUILD="-O2 -fomit-frame-pointer"
if ! $glibc_hack; then
	CFLAGS_FOR_BUILD="$CFLAGS_FOR_BUILD -D__LIBC_CUSTOM_BINDINGS_H__"
fi
LDFLAGS_FOR_BUILD="-s"
CXXFLAGS_FOR_BUILD="$CFLAGS_FOR_BUILD"

unset GLIBC_SO

with_gmp=
build_gdb=true
SED_INPLACE=-i

case $host in
	macos*)
		GCC=/usr/bin/clang
		GXX=/usr/bin/clang++
		MACOSX_DEPLOYMENT_TARGET=10.6
		ARCHS="-arch x86_64"
		case `$GCC --print-target-triple 2>/dev/null` in
		arm64* | aarch64*)
			BUILD_ARM64=yes
			;;
		esac
		if test "$BUILD_ARM64" = yes; then
			ARCHS="${ARCHS} -arch arm64"
			MACOSX_DEPLOYMENT_TARGET=11
		fi
		export MACOSX_DEPLOYMENT_TARGET
		CFLAGS_FOR_BUILD="-pipe -O2 ${ARCHS}"
		CXXFLAGS_FOR_BUILD="-pipe -O2 -stdlib=libc++ ${ARCHS}"
		LDFLAGS_FOR_BUILD="-Wl,-headerpad_max_install_names ${ARCHS}"
		export PKG_CONFIG_LIBDIR="$PKG_CONFIG_LIBDIR:${CROSSTOOL_DIR}/lib/pkgconfig"
		SED_INPLACE="-i .orig"
		with_gmp=--with-gmp=${CROSSTOOL_DIR}
		# disable gdb for now, since it is not part of the binutils archive
		build_gdb=false
		;;
	linux64)
		CFLAGS_FOR_BUILD="$CFLAGS_FOR_BUILD"
		CXXFLAGS_FOR_BUILD="$CFLAGS_FOR_BUILD"
		if $glibc_hack; then
			export GLIBC_SO="$srcdir/bfd/glibc.so"
		fi
		;;
	mingw*)
		build_gdb=false
		;;
esac
if test "$TARGET" != m68k-atari-mintelf; then
	build_gdb=false
fi
if ! $build_gdb; then
	gdb="--disable-gdb --disable-gdbserver --disable-sim --disable-readline"
fi

export CC="${GCC}"
export CXX="${GXX}"

fail()
{
	component="$1"
	echo "configuring $component failed"
	exit 1
}


#
# Now, for darwin, build gmp etc.
#
if test "$gdb" = ""; then
	. ${scriptdir}/gmp-for-gcc.sh
fi
. ${scriptdir}/zstd-for-gcc.sh

cd "$MINT_BUILD_DIR"

$srcdir/configure \
	MAKEINFO="echo texinfo 7.0" \
	--target="${TARGET}" --build="$BUILD" \
	--prefix="${PREFIX}" \
	--libdir="$BUILD_LIBDIR" \
	--bindir="${PREFIX}/bin" \
	--libexecdir='${libdir}' \
	CFLAGS="$CFLAGS_FOR_BUILD" \
	CXXFLAGS="$CXXFLAGS_FOR_BUILD" \
	LDFLAGS="$LDFLAGS_FOR_BUILD" \
	$bfd_targets \
	--with-pkgversion="$REVISION" \
	--with-bugurl='https://github.com/freemint/m68k-atari-mint-binutils-gdb/issues' \
	--with-stage1-ldflags= \
	--with-boot-ldflags="$LDFLAGS_FOR_BUILD" \
	--with-gcc --with-gnu-as --with-gnu-ld \
	--disable-werror \
	--disable-threads \
	--disable-threading \
	--enable-new-dtags \
	--enable-relro \
	--enable-default-hash-style=both \
	$enable_lto \
	$enable_plugins \
	--disable-nls \
	--with-system-zlib \
	$with_gmp $gdb \
	--disable-bracketed-paste-default \
	--with-sysroot="${PREFIX}/${TARGET}/sys-root"

${MAKE} $JOBS || exit 1


case $host in
	mingw*) if test "${PREFIX}" = /usr; then PREFIX=${MINGW_PREFIX}; BUILD_LIBDIR=${PREFIX}/lib; fi ;;
	macos*) if test "${PREFIX}" = /usr; then PREFIX=/opt/cross-mint; BUILD_LIBDIR=${PREFIX}/lib; fi ;;
esac

#
# install this package twice:
# - once for building the binary archive for this package only.
# - once for building a complete package.
#   This directory is also kept for later stages,
#   eg. compiling the C-library and gcc
#
THISPKG_DIR="${DIST_DIR}/${PACKAGENAME}${VERSION}"
rm -rf "${THISPKG_DIR}"
INSTALL_DIRS="${THISPKG_DIR}"
if $glibc_hack; then
	INSTALL_DIRS="${PKG_DIR} ${INSTALL_DIRS}"
fi
for INSTALL_DIR in ${INSTALL_DIRS}; do
	
	cd "$MINT_BUILD_DIR"
	${MAKE} DESTDIR="$INSTALL_DIR" prefix="${PREFIX}" bindir="${PREFIX}/bin" install-strip >/dev/null || exit 1
	
	mkdir -p "${INSTALL_DIR}/${PREFIX}/${TARGET}/bin"
	
	cd "${INSTALL_DIR}/${PREFIX}/${TARGET}/bin"
	
	for i in addr2line ar as nm ld ld.bfd objcopy objdump ranlib strip readelf dlltool dllwrap size strings; do
		if test -x ../../bin/${TARGET}-$i; then
			rm -f ${i} ${i}${BUILD_EXEEXT}
			$LN_S ../../bin/${TARGET}-$i${BUILD_EXEEXT} $i
		fi
	done
	
	cd "${INSTALL_DIR}/${PREFIX}/bin"
	
	rm -f ${TARGET}-ld ${TARGET}-ld${BUILD_EXEEXT}
	$LN_S ${TARGET}-ld.bfd${BUILD_EXEEXT} ${TARGET}-ld${BUILD_EXEEXT}
	cd "${INSTALL_DIR}" || exit 1
	
	${STRIP} ${PREFIX#/}/bin/*
	rm -f ${BUILD_LIBDIR#/}/libiberty.a

	rm -f ${PREFIX#/}/share/info/dir
    rm -f ${BUILD_LIBDIR#/}/bfd-plugins/libdep.so
    rm -f ${BUILD_LIBDIR#/}/bfd-plugins/*dep.dll
    rmdir ${BUILD_LIBDIR#/}/bfd-plugins 2>/dev/null || :
	for f in ${PREFIX#/}/share/man/*/* ${PREFIX#/}/share/info/*; do
		case $f in
		*.gz) ;;
		*) rm -f ${f}.gz; gzip -9 $f ;;
		esac
	done
done

cd "${THISPKG_DIR}" || exit 1

TARNAME=${PACKAGENAME}${VERSION}-${TARGET##*-}${VERSIONPATCH}

# create separate archive for gdb
if test -f ${PREFIX#/}/bin/${TARGET}-gdb; then
	gdb=${PREFIX#/}/bin/${TARGET}-gdb*
	# do not overwrite the system files
	if test "${PREFIX}" = /usr -o "${PREFIX}" = "$MINGW_PREFIX"; then
		rm -rf "${PREFIX#/}/share/gdb"
		rm -f "${PREFIX#/}/share/info/"*gdb*
		rm -f "${PREFIX#/}/share/man/"*/*gdb*
		rm -rf "${PREFIX#/}/include/gdb"
	else
		gdb="$gdb "${PREFIX#/}/share/gdb"
		gdb="$gdb "${PREFIX#/}/share/info/"*gdb*
		gdb="$gdb "${PREFIX#/}/share/man/"*/*gdb*
		gdb="$gdb "${PREFIX#/}/include/gdb"
	fi
	# this is empty currently
	rmdir "${PREFIX#/}/include/sim" 2>/dev/null || true
	gdb_version=`cat $srcdir/gdb/version.in`
	gdb_version=${gdb_version//.DATE-git/}
	gdb_version=$(echo ${gdb_version} | cut -d '.' -f 1-2)
	${TAR} ${TAR_OPTS} -Jcf ${DIST_DIR}/gdb-${gdb_version}-${TARGET##*-}${VERSIONPATCH}-bin-${host}.tar.xz $gdb || exit 1
	rm -rf $gdb
fi

${TAR} ${TAR_OPTS} -Jcf ${DIST_DIR}/${TARNAME}-doc.tar.xz ${PREFIX#/}/share/info ${PREFIX#/}/share/man
rm -rf ${PREFIX#/}/share/info
rm -rf ${PREFIX#/}/share/man
rmdir "${PREFIX#/}/share" 2>/dev/null || :

if test $glibc_hack = false -a \( $host = linux32 -o $host = linux64 \); then
	id=`lsb_release -i -s | tr '[[:upper:]]' '[[:lower:]]'`
	release=`lsb_release -r -s`
	# binutils-x.y-ubuntu-20.04-mint.tar.xz
	TARNAME=${PACKAGENAME}${VERSION}-${id}-${release}-${TARGET##*-}
	${TAR} ${TAR_OPTS} -Jcf ${DIST_DIR}/${TARNAME}.tar.xz ${PREFIX#/}
else
	${TAR} ${TAR_OPTS} -Jcf ${DIST_DIR}/${TARNAME}-bin-${host}.tar.xz ${PREFIX#/}
fi

cd "${BUILD_DIR}"
if test "$KEEP_PKGDIR" != yes; then
	rm -rf "${THISPKG_DIR}"
fi

${TAR} ${TAR_OPTS} -Jcf ${DIST_DIR}/${PACKAGENAME}${VERSION}-mint${VERSIONPATCH}.tar.xz ${ALLPATCHES}
cp -p "$me" ${DIST_DIR}/${PACKAGENAME}${VERSION}${VERSIONPATCH}-build.sh
