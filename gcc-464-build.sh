#!/bin/sh

# This is an almost automatic script for building the binary packages.
# It is designed to be run on linux, cygwin or mingw,
# but it should run fine on other GNU environments.

me="$0"

PACKAGENAME=gcc
VERSION=-4.6.4
VERSIONPATCH=-20230210
REVISION="MiNT ${VERSIONPATCH#-}"

#
# For which target we build-
# should be m68k-atari-mint
#
TARGET=m68k-atari-mint

#
# The hosts compiler.
# To build the 32bit version for linux,
# invoke this script with
# GCC="gcc -m32" GXX="g++ -m32"
# You will also need to have various 32bit flavours
# of system libraries installed.
# For other 32bit hosts (mingw32 and cygwin32)
# use the appropriate shell for that system.
#
GCC=${GCC-gcc}
GXX=${GXX-g++}

#
# The prefix where the executables should
# be installed later. If installed properly,
# this actually does not matter much, since
# all relevant directories are looked up
# relative to the executable
#
TAR=${TAR-tar}
TAR_OPTS=${TAR_OPTS---owner=0 --group=0}
SED_INPLACE=-i
case `uname -s` in
	MINGW64*) host=mingw64; MINGW_PREFIX=/mingw64; ;;
	MINGW32*) host=mingw32; MINGW_PREFIX=/mingw32; ;;
	MINGW*) if echo "" | ${GCC} -dM -E - 2>/dev/null | grep -q i386; then host=mingw32; else host=mingw64; fi; MINGW_PREFIX=/$host ;;
	MSYS*) if echo "" | ${GCC} -dM -E - 2>/dev/null | grep -q i386; then host=mingw32; else host=mingw64; fi; MINGW_PREFIX=/$host ;;
	CYGWIN*) if echo "" | ${GCC} -dM -E - 2>/dev/null | grep -q i386; then host=cygwin32; else host=cygwin64; fi ;;
	Darwin*) host=macos; STRIP=strip; TAR_OPTS=; SED_INPLACE="-i ''" ;;
	*) host=linux64
	   if echo "" | ${GCC} -dM -E - 2>/dev/null | grep -q i386; then host=linux32; fi
	   ;;
esac
case $host in
	mingw* | msys*) PREFIX=${MINGW_PREFIX} ;;
	macos*) PREFIX=/opt/cross-mint ;;
	*) PREFIX=/usr ;;
esac

#
# Where to look for the original source archives
#
case $host in
	mingw* | msys*) here=`pwd` ;;
	*) here=`pwd` ;;
esac
ARCHIVES_DIR="$here"

#
# where to look for mpfr/gmp/mpc/isl etc.
# currently only needed on Darwin, which lacks
# libmpc.
# Should be a static compiled version, so the
# compiler does not depend on non-standard shared libs
# We will compile now the required libraries before
# trying to compile gcc, in order to produce universal
# libraries
#
CROSSTOOL_DIR="$HOME/crosstools"

#
# Where to look for patches, write logs etc.
#
BUILD_DIR="$here"

#
# Where to configure and build gcc. This *must*
# be outside the gcc source directory, ie. it must
# not even be a subdirectory of it
#
MINT_BUILD_DIR="$BUILD_DIR/gcc-build4"

#
# Where to put the executables for later use.
# This should be the same as the one configured
# in the binutils script
#
PKG_DIR="$here/binary-package"

#
# Where to put the binary packages
#
DIST_DIR="$here/pkgs"

#
# Where to look up the source tree.
#
srcdir="$here/${PACKAGENAME}${VERSION}"

#
# whether to include the fortran backend
#
with_fortran=false

#
# whether to include the D backend
#
with_D=false

#
# whether to include the ada backend
#
with_ada=false


#
# this patch can be recreated by
# - cloning https://github.com/th-otto/m68k-atari-mint-gcc.git
# - checking out the mint/gcc-4.6 branch
# - running git diff releases/gcc-4.6 HEAD
PATCHES="patches/gcc/${PACKAGENAME}${VERSION}-mint${VERSIONPATCH}.patch"
OTHER_PATCHES="
patches/gcc/${PACKAGENAME}${VERSION}-fastcall.patch
patches/gmp/gmp-universal.patch
patches/gmp/gmp-6.2.1-CVE-2021-43618.patch
patches/gmp/gmp-6.2.1-arm64-invert_limb.patch
"

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

#
# install mintlib if needed, so libstdc++ can be configured
#
if ! test -f ${PREFIX}/${TARGET}/sys-root/usr/include/compiler.h; then
	if test "${GITHUB_REPOSITORY}" != ""; then
		sudo mkdir -p ${PREFIX}/${TARGET}/sys-root/usr
		echo "fetching mintlib"
		wget -q -O - "https://tho-otto.de/snapshots/mintlib/mintlib-latest.tar.bz2" | sudo $TAR -C "${PREFIX}/${TARGET}/sys-root/usr" -xjf -
		echo "fetching fdlibm"
		wget -q -O - "https://tho-otto.de/snapshots/fdlibm/fdlibm-latest.tar.bz2" | sudo $TAR -C "${PREFIX}/${TARGET}/sys-root/usr" -xjf -
	fi
fi

if test ! -f "${PREFIX}/${TARGET}/sys-root/usr/include/compiler.h"; then
	echo "mintlib headers must be installed in ${PREFIX}/${TARGET}/sys-root/usr/include" >&2
	exit 1
fi

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

BASE_VER=$(cat $srcdir/gcc/BASE-VER)
if test "$BASE_VER" != "${VERSION#-}"; then
	echo "version mismatch: this script is for gcc ${VERSION#-}, but gcc source is version $BASE_VER" >&2
	exit 1
fi
gcc_dir_version=${BASE_VER}
gccsubdir=${BUILD_LIBDIR}/gcc/${TARGET}/${gcc_dir_version}
gxxinclude=/usr/include/c++/${gcc_dir_version}

#
# try config.guess from automake first to get the
# canonical build system name.
# On some distros it is patched to have the
# vendor name included.
# FIXME: maybe use $GCC -dumpmachine intead?
#
for a in "" -1.16 -1.15 -1.14 -1.13 -1.12 -1.11 -1.10; do
	BUILD=`/usr/share/automake${a}/config.guess 2>/dev/null`
	test "$BUILD" != "" && break
	test "$host" = "macos" && BUILD=`/opt/local/share/automake${a}/config.guess 2>/dev/null`
	test "$BUILD" != "" && break
done
test "$BUILD" = "" && BUILD=`$srcdir/config.guess`
case $BUILD in
	x86_64-pc-mingw32) BUILD=x86_64-pc-mingw32 ;;
	i686-pc-mingw32) BUILD=i686-pc-msys ;;
esac

rm -rf "$MINT_BUILD_DIR"
mkdir -p "$MINT_BUILD_DIR"

cd "$MINT_BUILD_DIR"

CFLAGS_FOR_BUILD="-O2 -fomit-frame-pointer"
CFLAGS_FOR_TARGET="-O2 -fomit-frame-pointer"
LDFLAGS_FOR_BUILD=""
CXXFLAGS_FOR_BUILD="$CFLAGS_FOR_BUILD"
CXXFLAGS_FOR_TARGET="$CFLAGS_FOR_TARGET"
LDFLAGS_FOR_TARGET=

enable_lto=--disable-lto
enable_plugin=--disable-plugin
enable_libphobos=
languages=c,c++
$with_fortran && languages="$languages,fortran"
$with_ada && languages="$languages,ada"
$with_D && { languages="$languages,d"; enable_libphobos=; } # --enable-libphobos does not work because of missing swapcontext() in mintlib
ranlib=ranlib
STRIP=${STRIP-strip -p}

case "${TARGET}" in
    *-*-*elf* | *-*-linux*)
        enable_lto=--enable-lto
        case "${BUILD}" in
        *-*-linux*)
            enable_plugin=--enable-plugin
            ;;
        esac
        languages="$languages,lto"
        # not here; we are just building it
        # ranlib=gcc-ranlib
        ;;
esac
BUILD_EXEEXT=
LN_S="ln -s"
case $host in
	cygwin* | mingw* | msys*) BUILD_EXEEXT=.exe ;;
esac
case $host in
	mingw* | msys*) LN_S="cp -p" ;;
esac


#
# install binutils if needed
#
mkdir -p "${PKG_DIR}"
if test ! -f "${PKG_DIR}/${PREFIX}/bin/${TARGET}-${ranlib}"; then
	if test "${GITHUB_REPOSITORY}" != ""; then
		echo "fetching binutils"
		wget -q -O - "https://tho-otto.de/snapshots/crossmint/$host/binutils/binutils-2.39-${TARGET##*-}-20230206-bin-${host}.tar.xz" | $TAR -C "${PKG_DIR}" -xJf -
		export PATH="${PKG_DIR}${PREFIX}/bin:$PATH"
	fi
fi



try="${PKG_DIR}/${PREFIX}/bin/${TARGET}-${ranlib}"
if test -x "$try"; then
	ranlib="$try"
	strip="${PKG_DIR}/${PREFIX}/bin/${TARGET}-strip"
	as="${PKG_DIR}/${PREFIX}/bin/${TARGET}-as"
else
	ranlib=`which ${TARGET}-${ranlib} 2>/dev/null`
	strip=`which "${TARGET}-strip" 2>/dev/null`
	as=`which "${TARGET}-as" 2>/dev/null`
fi
if test "$ranlib" = "" -o ! -x "$ranlib" -o ! -x "$as" -o ! -x "$strip"; then
	echo "cross-binutil tools for ${TARGET} not found" >&2
	exit 1
fi

mpfr_config=

unset GLIBC_SO

case $host in
	macos*)
		GCC=/usr/bin/clang
		GXX=/usr/bin/clang++
		MACOSX_DEPLOYMENT_TARGET=10.9
		ARCHS="-arch x86_64"
		case `$GCC --print-target-triple 2>/dev/null` in
		arm64* | aarch64*)
			BUILD_ARM64=yes
			;;
		esac
		if test `uname -r | cut -d . -f 1` -ge 20; then
			BUILD_ARM64=yes
		fi
		if test "$BUILD_ARM64" = yes; then
			ARCHS="${ARCHS} -arch arm64"
			MACOSX_DEPLOYMENT_TARGET=11
		fi
		export MACOSX_DEPLOYMENT_TARGET
		CFLAGS_FOR_BUILD="-pipe -O2 ${ARCHS}"
		CXXFLAGS_FOR_BUILD="-pipe -O2 -stdlib=libc++ ${ARCHS}"
		LDFLAGS_FOR_BUILD="-Wl,-headerpad_max_install_names ${ARCHS}"
		mpfr_config="--with-mpc=${CROSSTOOL_DIR}"
		;;
esac

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
gmp='gmp-6.2.1.tar.bz2'
mpfr='mpfr-3.1.4.tar.bz2'
mpc='mpc-1.0.3.tar.gz'
isl='isl-0.18.tar.bz2'
base_url='https://gcc.gnu.org/pub/gcc/infrastructure/'

if test $host = macos; then
	mkdir -p "$CROSSTOOL_DIR"

	if test ! -f "$CROSSTOOL_DIR/lib/libgmp.a"; then
		cd "$CROSSTOOL_DIR" || exit 1
		mkdir -p lib include
		archive=$gmp
		package="${archive%.tar*}"
		echo "fetching ${archive}"
		wget -nv "${base_url}${archive}" || exit 1
		rm -rf "${package}"
		$TAR xf "$archive" || exit 1
		cd "${package}" || exit 1

		patch -p1 < "$BUILD_DIR/patches/gmp/gmp-universal.patch" || exit 1
		patch -p1 < "$BUILD_DIR/patches/gmp/gmp-6.2.1-CVE-2021-43618.patch" || exit 1
		# following patch was taken from SuSE, but failes to compile with clang
		# patch -p1 < "$BUILD_DIR/patches/gmp/gmp-6.2.1-arm64-invert_limb.patch" || exit 1
		
		rm -f "$CROSSTOOL_DIR/include/gmp.h"
		
		mkdir -p build-x86_64
		cd build-x86_64
		ABI=64 \
		CFLAGS="-O2 -arch x86_64" \
		CXXFLAGS="-O2 -arch x86_64" \
		LDFLAGS="-O2 -arch x86_64" \
		../configure --host=x86_64-apple-darwin \
		--with-pic --disable-shared --prefix="$CROSSTOOL_DIR/install-x86_64" || fail "gmp"
		${MAKE} $JOBS || exit 1
		${MAKE} install
		cd "$CROSSTOOL_DIR"
		sed -e 's/ -arch [a-z0-9_]*//' install-x86_64/include/gmp.h > install-x86_64/include/gmp.h.tmp
		mv install-x86_64/include/gmp.h.tmp install-x86_64/include/gmp.h

		if test "$BUILD_ARM64" = yes; then
			cd "${CROSSTOOL_DIR}/${package}"
			mkdir -p build-arm64
			cd build-arm64
			ABI=64 \
			CFLAGS="-O2 -arch arm64" \
			CXXFLAGS="-O2 -arch arm64" \
			LDFLAGS="-O2 -arch arm64" \
			../configure --host=aarch64-apple-darwin \
			--with-pic --disable-shared --prefix="$CROSSTOOL_DIR/install-arm64" || fail "gmp"
			${MAKE} $JOBS || exit 1
			${MAKE} install
			cd "$CROSSTOOL_DIR"
			# lipo -create install-arm64/lib/libgmp.10.dylib -create install-x86_64/lib/libgmp.10.dylib -output lib/libgmp.10.dylib
			lipo -create install-arm64/lib/libgmp.a -create install-x86_64/lib/libgmp.a -output lib/libgmp.a
		else
			cd "$CROSSTOOL_DIR"
			rm -f install-x86_64/lib/*.la
			mv install-x86_64/lib/* lib
		fi
		
		mv install-x86_64/include/* include
		rm -f lib/*.la
		rm -rf install-*
	fi

	
	if test ! -f "$CROSSTOOL_DIR/lib/libmpfr.a"; then
		cd "$CROSSTOOL_DIR" || exit 1
		mkdir -p lib include
		archive=$mpfr
		package="${archive%.tar*}"
		echo "fetching ${archive}"
		wget -nv "${base_url}${archive}" || exit 1
		rm -rf "${package}"
		$TAR xf "$archive" || exit 1
		cd "${package}" || exit 1

		rm -f include/mpfr.h include/mpf2mpfr.h
		
		mkdir -p build-x86_64
		cd build-x86_64
		CFLAGS="-O2 -arch x86_64" \
		CXXFLAGS="-O2 -arch x86_64" \
		LDFLAGS="-O2 -arch x86_64" \
		../configure --host=x86_64-apple-darwin \
		--with-gmp="$CROSSTOOL_DIR" --disable-shared --prefix="$CROSSTOOL_DIR/install-x86_64" || fail "mpfr"
		${MAKE} $JOBS || exit 1
		${MAKE} install

		if test "$BUILD_ARM64" = yes; then
			cd "${CROSSTOOL_DIR}/${package}"
			mkdir -p build-arm64
			cd build-arm64
			CFLAGS="-O2 -arch arm64" \
			CXXFLAGS="-O2 -arch arm64" \
			LDFLAGS="-O2 -arch arm64" \
			../configure --host=aarch64-apple-darwin \
			--with-gmp="$CROSSTOOL_DIR" --disable-shared --prefix="$CROSSTOOL_DIR/install-arm64" || fail "mpfr"
			${MAKE} $JOBS || exit 1
			${MAKE} install
			cd "$CROSSTOOL_DIR"
			# lipo -create install-arm64/lib/libmpfr.4.dylib -create install-x86_64/lib/libmpfr.4.dylib -output lib/libmpfr.4.dylib
			lipo -create install-arm64/lib/libmpfr.a -create install-x86_64/lib/libmpfr.a -output lib/libmpfr.a
		else
			cd "$CROSSTOOL_DIR"
			rm -f install-x86_64/lib/*.la
			mv install-x86_64/lib/* lib
		fi
		
		mv install-x86_64/include/* include
		rm -f lib/*.la
		rm -rf install-*
	fi

	
	if test ! -f "$CROSSTOOL_DIR/lib/libmpc.a"; then
		cd "$CROSSTOOL_DIR" || exit 1
		mkdir -p lib include
		archive=$mpc
		package="${archive%.tar*}"
		echo "fetching ${archive}"
		wget -nv "${base_url}${archive}" || exit 1
		rm -rf "${package}"
		$TAR xf "$archive" || exit 1
		cd "${package}" || exit 1

		rm -f include/mpc.h
		
		mkdir -p build-x86_64
		cd build-x86_64
		CFLAGS="-O2 -arch x86_64" \
		CXXFLAGS="-O2 -arch x86_64" \
		LDFLAGS="-O2 -arch x86_64" \
		../configure --host=x86_64-apple-darwin \
		--with-gmp="$CROSSTOOL_DIR" --disable-shared --prefix="$CROSSTOOL_DIR/install-x86_64" || fail "mpc"
		${MAKE} $JOBS || exit 1
		${MAKE} install
		
		if test "$BUILD_ARM64" = yes; then
			cd "${CROSSTOOL_DIR}/${package}"
			mkdir -p build-arm64
			cd build-arm64
			CFLAGS="-O2 -arch arm64" \
			CXXFLAGS="-O2 -arch arm64" \
			LDFLAGS="-O2 -arch arm64" \
			../configure --host=aarch64-apple-darwin \
			--with-gmp="$CROSSTOOL_DIR" --disable-shared --prefix="$CROSSTOOL_DIR/install-arm64" || fail "mpc"
			${MAKE} $JOBS || exit 1
			${MAKE} install
			cd "$CROSSTOOL_DIR"
			# lipo -create install-arm64/lib/libmpc.3.dylib -create install-x86_64/lib/libmpc.3.dylib -output lib/libmpc.3.dylib
			lipo -create install-arm64/lib/libmpc.a -create install-x86_64/lib/libmpc.a -output lib/libmpc.a
		else
			cd "$CROSSTOOL_DIR"
			rm -f install-x86_64/lib/*.la
			mv install-x86_64/lib/* lib
		fi
		
		mv install-x86_64/include/* include
		rm -f lib/*.la
		rm -rf install-*
	fi
fi



cd "$MINT_BUILD_DIR"

$srcdir/configure \
	--target="${TARGET}" --build="$BUILD" \
	--prefix="${PREFIX}" \
	--libdir="$BUILD_LIBDIR" \
	--bindir="${PREFIX}/bin" \
	--libexecdir='${libdir}' \
	CFLAGS_FOR_BUILD="$CFLAGS_FOR_BUILD" \
	CFLAGS="$CFLAGS_FOR_BUILD" \
	CXXFLAGS_FOR_BUILD="$CXXFLAGS_FOR_BUILD" \
	CXXFLAGS="$CXXFLAGS_FOR_BUILD" \
	BOOT_CFLAGS="$CFLAGS_FOR_BUILD" \
	CFLAGS_FOR_TARGET="$CFLAGS_FOR_TARGET" \
	CXXFLAGS_FOR_TARGET="$CXXFLAGS_FOR_TARGET" \
	LDFLAGS_FOR_BUILD="$LDFLAGS_FOR_BUILD" \
	LDFLAGS="$LDFLAGS_FOR_BUILD" \
	--with-pkgversion="$REVISION" \
	--disable-libvtv \
	--disable-libmpx \
	--disable-libcc1 \
	--disable-shared \
	--with-gxx-include-dir=${PREFIX}/${TARGET}/sys-root${gxxinclude} \
	--with-default-libstdcxx-abi=gcc4-compatible \
	--with-gcc --with-gnu-as --with-gnu-ld \
	--with-system-zlib \
	--disable-libgomp \
	--without-newlib \
	--disable-libstdcxx-pch \
	--disable-threads \
	$enable_lto \
	$enable_libphobos \
	--enable-ssp \
	--enable-libssp \
	$enable_plugin \
	--disable-decimal-float \
	--disable-nls \
	--with-libiconv-prefix="${PREFIX}" \
	--with-libintl-prefix="${PREFIX}" \
	$mpfr_config \
	--with-sysroot="${PREFIX}/${TARGET}/sys-root" \
	--enable-languages="$languages" || fail "gcc"


case $host in
	linux32)
		# make sure to pick up the just-compiled 32bit version of ld, not
		# some previous 64bit version
		# symptom of using a wrong linker is an error message "error loading plugin: wrong ELF class: ELFCLASS32" in the config.log
		sed $SED_INPLACE "s|S\[\"build_tooldir\"\]=.*|S[\"build_tooldir\"]=\"${PKG_DIR}${PREFIX}/${TARGET}\"|" config.status
		./config.status
		;;
esac

${MAKE} $JOBS all-gcc || exit 1
${MAKE} $JOBS all-target-libgcc || exit 1
${MAKE} $JOBS || exit 1

gcc_major_version=$(echo $BASE_VER | cut -d '.' -f 1)

THISPKG_DIR="${DIST_DIR}/${PACKAGENAME}${VERSION}"
rm -rf "${THISPKG_DIR}"
for INSTALL_DIR in "${PKG_DIR}" "${THISPKG_DIR}"; do
	
	cd "$MINT_BUILD_DIR"
	${MAKE} DESTDIR="${INSTALL_DIR}" install >/dev/null || exit 1
	
	mkdir -p "${INSTALL_DIR}/${PREFIX}/${TARGET}/bin"
	
	cd "${INSTALL_DIR}/${PREFIX}/${TARGET}/bin"
	
	for i in c++ cpp g++ gcc gcov gfortran gdc; do
		if test -x ../../bin/${TARGET}-$i; then
			rm -f ${i} ${i}${BUILD_EXEEXT}
			$LN_S ../../bin/${TARGET}-$i${BUILD_EXEEXT} $i
		fi
	done
	
	cd "${INSTALL_DIR}/${PREFIX}/bin"
	${STRIP} *
	
	if test -x ${TARGET}-g++ && test ! -h ${TARGET}-g++; then
		rm -f ${TARGET}-g++-${BASE_VER}${BUILD_EXEEXT} ${TARGET}-g++-${BASE_VER}
		rm -f ${TARGET}-g++-${gcc_major_version}${BUILD_EXEEXT} ${TARGET}-g++-${gcc_major_version}
		mv ${TARGET}-g++${BUILD_EXEEXT} ${TARGET}-g++-${BASE_VER}${BUILD_EXEEXT}
		$LN_S ${TARGET}-g++-${BASE_VER}${BUILD_EXEEXT} ${TARGET}-g++${BUILD_EXEEXT}
		$LN_S ${TARGET}-g++-${BASE_VER}${BUILD_EXEEXT} ${TARGET}-g++-${gcc_major_version}${BUILD_EXEEXT}
	fi
	if test -x ${TARGET}-c++ && test ! -h ${TARGET}-c++; then
		rm -f ${TARGET}-c++${BUILD_EXEEXT} ${TARGET}-c++
		$LN_S ${TARGET}-g++${BUILD_EXEEXT} ${TARGET}-c++${BUILD_EXEEXT}
	fi
	if test -x ${TARGET}-gcc && test ! -h ${TARGET}-gcc; then
		rm -f ${TARGET}-gcc-${BASE_VER}${BUILD_EXEEXT} ${TARGET}-gcc-${BASE_VER}
		rm -f ${TARGET}-gcc-${gcc_major_version}${BUILD_EXEEXT} ${TARGET}-gcc-${gcc_major_version}
		mv ${TARGET}-gcc${BUILD_EXEEXT} ${TARGET}-gcc-${BASE_VER}${BUILD_EXEEXT}
		$LN_S ${TARGET}-gcc-${BASE_VER}${BUILD_EXEEXT} ${TARGET}-gcc${BUILD_EXEEXT}
		$LN_S ${TARGET}-gcc-${BASE_VER}${BUILD_EXEEXT} ${TARGET}-gcc-${gcc_major_version}${BUILD_EXEEXT}
	fi
	if test -x ${TARGET}-cpp && test ! -h ${TARGET}-cpp; then
		rm -f ${TARGET}-cpp-${BASE_VER}${BUILD_EXEEXT} ${TARGET}-cpp-${BASE_VER}
		mv ${TARGET}-cpp${BUILD_EXEEXT} ${TARGET}-cpp-${BASE_VER}${BUILD_EXEEXT}
		$LN_S ${TARGET}-cpp-${BASE_VER}${BUILD_EXEEXT} ${TARGET}-cpp${BUILD_EXEEXT}
	fi

	cd "${INSTALL_DIR}"
	
# that directory only contains the gdb pretty printers;
# on the host we don't want them because they would conflict
# with the system ones; on the target we don't need them
# because gdb does not work
	rm -rf ${PREFIX#/}/share/gcc-${gcc_dir_version}
	if test -d ${PREFIX#/}/${TARGET}/lib; then find ${PREFIX#/}/${TARGET}/lib -name "libstdc++*.py" -delete; fi
	if test -d ${PREFIX#/}/lib; then find ${PREFIX#/}/lib -name "libstdc++*.py" -delete; fi

	rm -f ${PREFIX#/}/share/info/dir
	for f in ${PREFIX#/}/share/man/*/* ${PREFIX#/}/share/info/*; do
		case $f in
		*.gz) ;;
		*) rm -f ${f}.gz; gzip -9 $f ;;
		esac
	done
	
	rm -f */*/libiberty.a
	# macOS does not understand -printf
	# find . -type f -name "*.la" -delete -printf "rm %p\n"
	find . -type f -name "*.la" -delete

#
# move compiler dependant libraries to the gcc subdirectory
#
	pushd ${INSTALL_DIR}${PREFIX}/${TARGET}/lib || exit 1
	libs=`find . -name "lib*.a" ! -path "*/gcc/*"`
	$TAR -c $libs | $TAR -x -C ${INSTALL_DIR}${gccsubdir}
	rm -f $libs
	for i in libgfortran.spec libgomp.spec libitm.spec libsanitizer.spec libmpx.spec libgphobos.spec; do
		test -f $i && mv $i ${INSTALL_DIR}${gccsubdir}
		find . -name "$i" -delete
	done
	rmdir m*/*/*/* || :
	rmdir m*/*/* || :
	rmdir m*/* || :
	rmdir m* || :
	popd

	case $host in
		cygwin*) LTO_PLUGIN=cyglto_plugin-0.dll; MY_LTO_PLUGIN=cyglto_plugin_mintelf-${gcc_dir_version}.dll ;;
		mingw* | msys*) LTO_PLUGIN=liblto_plugin-0.dll; MY_LTO_PLUGIN=liblto_plugin_mintelf-${gcc_dir_version}.dll ;;
		macos*) LTO_PLUGIN=liblto_plugin.dylib; MY_LTO_PLUGIN=liblto_plugin_mintelf-${gcc_dir_version}.dylib ;;
		*) LTO_PLUGIN=liblto_plugin.so.0.0.0; MY_LTO_PLUGIN=liblto_plugin_mintelf.so.${gcc_dir_version} ;;
	esac
	
	for f in ${gccsubdir#/}/{cc1,cc1plus,cc1obj,cc1objplus,f951,d21,collect2,lto-wrapper,lto1,gnat1,gnat1why,gnat1sciln,go1,brig1}${BUILD_EXEEXT} \
		${gccsubdir#/}/${LTO_PLUGIN} \
		${gccsubdir#/}/plugin/gengtype${BUILD_EXEEXT} \
		${gccsubdir#/}/install-tools/fixincl${BUILD_EXEEXT}; do
		test -f "$f" && ${STRIP} "$f"
	done

	rmdir ${PREFIX#/}/include
	
	if test -f ${BUILD_LIBDIR#/}/gcc/${TARGET}/${gcc_dir_version}/${LTO_PLUGIN}; then
		mkdir -p ${PREFIX#/}/lib/bfd-plugins
		cd ${PREFIX#/}/lib/bfd-plugins
		rm -f ${MY_LTO_PLUGIN}
		$LN_S ../../${BUILD_LIBDIR##*/}/gcc/${TARGET}/${gcc_dir_version}/${LTO_PLUGIN} ${MY_LTO_PLUGIN}
		cd "${INSTALL_DIR}"
	fi
	
	find ${PREFIX#/}/${TARGET} -name "*.a" -exec "${strip}" -S -x '{}' \;
	find ${PREFIX#/}/${TARGET} -name "*.a" -exec "${ranlib}" '{}' \;
	find ${gccsubdir#/} -name "*.a" -exec "${strip}" -S -x '{}' \;
	find ${gccsubdir#/} -name "*.a" -exec "${ranlib}" '{}' \;
	
	cd ${BUILD_LIBDIR#/}/gcc/${TARGET}/${gcc_dir_version}/include-fixed && {
		for i in `find . -type f`; do
			case $i in
			./README | ./limits.h | ./syslimits.h) ;;
			*) echo "removing fixed include file $i"; rm -f $i ;;
			esac
		done
		for i in `find . -depth -type d`; do
			test "$i" = "." || rmdir "$i"
		done
	}
done

cd "${THISPKG_DIR}" || exit 1

TARNAME=${PACKAGENAME}${VERSION}-${TARGET##*-}${VERSIONPATCH}
BINTARNAME=${PACKAGENAME}${VERSION}-mint${VERSIONPATCH}

${TAR} ${TAR_OPTS} -Jcf ${DIST_DIR}/${TARNAME}-doc.tar.xz ${PREFIX#/}/share/info ${PREFIX#/}/share/man
rm -rf ${PREFIX#/}/share/info
rm -rf ${PREFIX#/}/share/man
rm -rf ${PREFIX#/}/share/gcc*/python

#
# create a separate archive for the fortran backend
#
if $with_fortran; then
	fortran=`find ${gccsubdir#/} -name finclude`
	fortran="$fortran "${gccsubdir#/}/f951
	fortran="$fortran "`find ${gccsubdir#/} -name libcaf_single.a`
	fortran="$fortran "`find ${gccsubdir#/} -name "*gfortran*"`
	${TAR} ${TAR_OPTS} -Jcf ${DIST_DIR}/${TARNAME}-fortran-${host}.tar.xz $fortran || exit 1
	rm -rf $fortran
fi

#
# create archive for all others
#
${TAR} ${TAR_OPTS} -Jcf ${DIST_DIR}/${TARNAME}-bin-${host}.tar.xz ${PREFIX#/}

cd "${BUILD_DIR}"
if test "$KEEP_PKGDIR" != yes; then
	rm -rf "${THISPKG_DIR}"
fi

${TAR} ${TAR_OPTS} -Jcf ${DIST_DIR}/${BINTARNAME}.tar.xz ${PATCHES} ${OTHER_PATCHES}
cp -p "$me" ${DIST_DIR}/${PACKAGENAME}${VERSION}${VERSIONPATCH}-build.sh
