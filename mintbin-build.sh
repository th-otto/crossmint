#!/bin/sh

me="$0"
scriptdir=${0%/*}

PACKAGENAME=mintbin
VERSION=-0.3
VERSIONPATCH=-20230206

. ${scriptdir}/functions.sh

PATCHES=""

unpack_archive

#
# Do the tools for the cross-compiler
#

CFLAGS_FOR_BUILD="-O2 -fomit-frame-pointer"

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
		if test "$BUILD_ARM64" = yes; then
			ARCHS="${ARCHS} -arch arm64"
			MACOSX_DEPLOYMENT_TARGET=11
		fi
		export MACOSX_DEPLOYMENT_TARGET
		CFLAGS_FOR_BUILD="$CFLAGS_FOR_BUILD ${ARCHS}"
		;;
esac


cd "$MINT_BUILD_DIR"

CC="${GCC}" \
	CFLAGS="$CFLAGS_FOR_BUILD" \
	./configure --prefix=${prefix} --disable-nls --target=$TARGET
${MAKE} $JOBS || exit 1

${MAKE} DESTDIR="${THISPKG_DIR}" install || exit 1
${MAKE} distclean

cd "${THISPKG_DIR}/${prefix}/bin" || exit 1
${STRIP} *

cd "${THISPKG_DIR}/${prefix}/${TARGET}/bin" || exit 1
${STRIP} *

for i in arconv cnm csize cstrip flags mintbin stack symex; do
	if test -x ../../bin/${TARGET}-$i && test -x $i && test ! -h $i && cmp -s $i ../../bin/${TARGET}-$i; then
		rm -f ${i} ${i}${BUILD_EXEEXT}
		$LN_S ../../bin/${TARGET}-$i${BUILD_EXEEXT} $i
	fi
done
	
cd "${THISPKG_DIR}"
rm -f ${prefix#/}/share/info/dir
for f in ${prefix#/}/share/info/*; do
	case $f in
	*.gz) ;;
	*) rm -f ${f}.gz; gzip -9 $f ;;
	esac
done

TARNAME=${PACKAGENAME}${VERSION}-${TARGET##*-}${VERSIONPATCH}

${TAR} ${TAR_OPTS} -Jcf ${DIST_DIR}/${TARNAME}-bin-${host}.tar.xz *

cd "$BUILD_DIR"

test -z "${PATCHES}" || $TAR ${TAR_OPTS} -Jcf ${DIST_DIR}/${PACKAGENAME}${VERSION}-mint${VERSIONPATCH}.tar.xz ${PATCHES}
cp -p "$me" ${DIST_DIR}/${PACKAGENAME}${VERSION}${VERSIONPATCH}-build.sh


#
# Do the atari native tools
#
# do this only on linux. The macOS command-line tools are just too broken
#
if test "$host" != linux64; then
	cd "${BUILD_DIR}"
	if test "$KEEP_PKGDIR" != yes; then
	       rm -rf "${THISPKG_DIR}"
	fi
	if test "$KEEP_SRCDIR" != yes; then
	       rm -rf "${srcdir}"
	fi
	exit 0
fi


cd "$MINT_BUILD_DIR"

sysroot=
BINFILES="${TARGET_PREFIX#/}/*"
VERSIONPATCH=
TARNAME=${PACKAGENAME}${VERSION}-${TARGET##*-}${VERSIONPATCH}
BINTARNAME=${PACKAGENAME}${VERSION}-${TARGET##*-}${VERSIONPATCH}

CONFIGURE_FLAGS="--host=${TARGET} --prefix=${TARGET_PREFIX} ${CONFIGURE_FLAGS_AMIGAOS} --disable-nls"

for CPU in ${ALL_CPUS}; do
	eval CPU_CFLAGS=\${CPU_CFLAGS_$CPU}
	eval multilibdir=\${CPU_LIBDIR_$CPU}
	eval multilibexecdir=\${CPU_LIBEXECDIR_$CPU}
	CFLAGS="$CPU_CFLAGS $COMMON_CFLAGS ${CFLAGS_AMIGAOS}" \
	LDFLAGS="$CPU_CFLAGS $COMMON_CFLAGS ${STACKSIZE}" \
	"$srcdir/configure" ${CONFIGURE_FLAGS} \
	--libdir='${exec_prefix}/lib'$multilibdir || exit 1

	${MAKE} $JOBS || exit 1
	${MAKE} DESTDIR="${THISPKG_DIR}${sysroot}" target_alias=$TARGET install || exit 1
	rm -rf ${THISPKG_DIR}${TARGET_PREFIX}/${TARGET}

	${MAKE} distclean
	make_bin_archive $CPU
done

make_archives
