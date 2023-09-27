#
# our vendor name, for a few packages that display it
#
VENDOR=RPMint

#
# For which target we build-
# should be either m68k-atari-mint or m68k-atari-mintelf
#
TARGET=${1:-m68k-atari-mint}

#
# The prefix where the executables should
# be installed later. If installed properly,
# this actually does not matter much, since
# all relevant directories are looked up
# relative to the executable
#
TAR=${TAR-tar}
TAR_OPTS=${TAR_OPTS---owner=0 --group=0}
GCC=${GCC-gcc}
GXX=${GXX-g++}
case `uname -s` in
	MINGW64*) host=mingw64; MINGW_PREFIX=/mingw64; ;;
	MINGW32*) host=mingw32; MINGW_PREFIX=/mingw32; ;;
	MINGW*) if echo "" | ${GCC} -dM -E - 2>/dev/null | grep -q i386; then host=mingw32; else host=mingw64; fi; MINGW_PREFIX=/$host ;;
	MSYS*) host=msys ;;
	CYGWIN*) if echo "" | ${GCC} -dM -E - 2>/dev/null | grep -q i386; then host=cygwin32; else host=cygwin64; fi ;;
	Darwin*) host=macos; STRIP=strip; TAR_OPTS= ;;
	Linux) host=linux64
	   if echo "" | ${GCC} -dM -E - 2>/dev/null | grep -q i386; then host=linux32; fi
	   ;;
	*)
	   echo "unsupported host os: ${host}" >&2
	   uname -a >&2
	   exit 1
	   ;;
esac
case $host in
	mingw*) prefix=${MINGW_PREFIX} ;;
	macos*) prefix=/opt/cross-mint ;;
	*) prefix=/usr ;;
esac
sysroot=${prefix}/${TARGET}/sys-root

#
# prefix of the target system. Should not need to be changed.
#
case $TARGET in
	m68k-amigaos*)
		prefix=/opt/amiga
		sysroot=
		PATH="/opt/amiga/bin:$PATH"
		TARGET_PREFIX=${prefix}
		CONFIGURE_FLAGS_AMIGAOS=" --includedir=${prefix}/sys-include"
		CFLAGS_AMIGAOS=" -mcrt=nix20"
		;;
	*)
		TARGET_PREFIX=/usr
		;;
esac

TARGET_LIBDIR="${TARGET_PREFIX}/lib"
TARGET_BINDIR="${TARGET_PREFIX}/bin"
TARGET_MANDIR="${TARGET_PREFIX}/share/man"
TARGET_INFODIR="${TARGET_PREFIX}/share/info"
TARGET_SYSCONFDIR=/etc

#
# Where to look for the original source archives
#
case $host in
	mingw* | msys*) here=`pwd` ;;
	*) here=`pwd` ;;
esac
ARCHIVES_DIR=$HOME/packages

#
# Where to look up the source tree, after unpacking
#
test -z "${PACKAGENAME}" && { echo "PACKAGENAME not set" >&2; exit 1; }
test -z "${VERSION}" && { echo "VERSION not set" >&2; exit 1; }
srcdir="${here}/${PACKAGENAME}${VERSION}"

#
# Where to look for patches, write logs etc.
#
BUILD_DIR="${here}"

#
# Where to configure and build the package
#
MINT_BUILD_DIR="$srcdir"

#
# Where to put the executables for later use.
# This should be the same as the one configured
# in the binutils script
#
PKG_DIR="${here}/binary7-package"

#
# Where to put the binary packages
#
DIST_DIR="${here}/pkgs"


BUILD_EXEEXT=
TARGET_EXEEXT=
LN_S="ln -s"
case $host in
	cygwin* | mingw* | msys*) BUILD_EXEEXT=.exe ;;
esac
case $host in
	mingw* | msys*) LN_S="cp -p" ;;
esac
case $TARGET in
 	*-*-cygwin* | *-*-mingw* | *-*-msys*) TARGET_EXEEXT=.exe ;;
esac

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

TARNAME=${PACKAGENAME}${VERSION}-${TARGET##*-}${VERSIONPATCH}
BINTARNAME=${PACKAGENAME}${VERSION}-mint${VERSIONPATCH}
THISPKG_DIR="${DIST_DIR}/${PACKAGENAME}${VERSION}"

#
# this could eventually be extracted from gcc -print-multi-lib
#
# It should list the default target cpu last,
# so that any files left behind are compiled for this
#
case $TARGET in
m68k-atari-mint*)
	CPU_CFLAGS_000=-m68000    ; CPU_LIBDIR_000=           ; CPU_LIBEXECDIR_000=/m68000
	CPU_CFLAGS_020=-m68020-60 ; CPU_LIBDIR_020=/m68020-60 ; CPU_LIBEXECDIR_020=/m68020-60
	CPU_CFLAGS_v4e=-mcpu=5475 ; CPU_LIBDIR_v4e=/m5475     ; CPU_LIBEXECDIR_v4e=/m5475
	if test "$ALL_CPUS" = ""; then
		ALL_CPUS="020 v4e 000"
	fi
	;;
m68k-amigaos*)
	if test "$ALL_CPUS" = ""; then
		ALL_CPUS="000 020"
	fi
	CPU_CFLAGS_000=-m68000    ; CPU_LIBDIR_000=nix/lib           ; CPU_LIBEXECDIR_000=/m68000
	CPU_CFLAGS_020="-m68020 -msoft-float"; CPU_LIBDIR_020=nix/lib/libm020   ; CPU_LIBEXECDIR_020=/m68020
	;;
esac

export PKG_CONFIG_LIBDIR="$prefix/$TARGET/lib/pkgconfig"
export PKG_CONFIG_PATH="$PKG_CONFIG_LIBDIR"

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
if test "$BUILD" = ""; then
	if test -f "$srcdir/config.guess"; then
		BUILD=`$srcdir/config.guess`
	fi
fi

LTO_CFLAGS=
ELF_CFLAGS=
ranlib=ranlib
STRIP=${STRIP-strip -p}

case "${TARGET}" in
    *-*-*elf* | *-*-linux*)
    	ranlib=gcc-ranlib
		# we cannot add this to CFLAGS, because then autoconf tests
		# for missing c library functions will always succeed
		LTO_CFLAGS="-flto -ffat-lto-objects"
		ELF_CFLAGS="-ffunction-sections -fdata-sections"
		;;
esac


#
# install binutils & gcc if needed
#
if test ! -f "${prefix}/bin/${TARGET}-${ranlib}"; then
	if test "${GITHUB_REPOSITORY}" != ""; then
		if test "${PACKAGENAME}" != binutils; then
			echo "fetching binutils"
			wget -q -O - "https://tho-otto.de/snapshots/crossmint/$host/binutils/binutils-2.41-${TARGET##*-}-20230926-bin-${host}.tar.xz" | sudo $TAR -C "/" -xJf -
		fi
		if test "${PACKAGENAME}" != gcc -a "${PACKAGENAME}" != binutils; then
			echo "fetching gcc"
			wget -q -O - "https://tho-otto.de/snapshots/crossmint/$host/gcc-7/gcc-7.5.0-${TARGET##*-}-20230210-bin-${host}.tar.xz" | sudo $TAR -C "/" -xJf -
		fi
		if test "${PACKAGENAME}" != mintbin -a "${PACKAGENAME}" != gcc -a "${PACKAGENAME}" != binutils; then
			echo "fetching mintbin"
			wget -q -O - "https://tho-otto.de/snapshots/crossmint/$host/mintbin/mintbin-0.3-${TARGET##*-}-20230206-bin-${host}.tar.xz" | sudo $TAR -C "/" -xJf -
		fi
		if test "${prefix}" != /usr; then
			export PATH="${prefix}/bin:$PATH"
		fi
	fi
fi

#
# install mintlib & fdlibm if needed
#
if ! test -f ${sysroot}/usr/include/compiler.h; then
	if test "${GITHUB_REPOSITORY}" != ""; then
		sudo mkdir -p "${sysroot}/usr"
		echo "fetching mintlib"
		wget -q -O - "https://tho-otto.de/snapshots/mintlib/mintlib-${TARGET##*-}-latest.tar.bz2" | sudo $TAR -C "${sysroot}/usr" -xjf -
		echo "fetching fdlibm"
		wget -q -O - "https://tho-otto.de/snapshots/fdlibm/fdlibm-${TARGET##*-}-latest.tar.bz2" | sudo $TAR -C "${sysroot}/usr" -xjf -
	fi
fi



gcc=`which "${TARGET}-gcc"`
cxx=`which "${TARGET}-g++"`
ar="${TARGET}-ar"
ranlib=`which ${TARGET}-${ranlib} 2>/dev/null`
strip=`which "${TARGET}-strip"`
MAKE=${MAKE:-make}

if test "$ranlib" = "" -o ! -x "$ranlib" -o ! -x "$gcc" -o ! -x "$strip"; then
	echo "cross tools for ${TARGET} not found" >&2
	exit 1
fi

unset CDPATH
unset LANG LANGUAGE LC_ALL LC_CTYPE LC_TIME LC_NUMERIC LC_COLLATE LC_MONETARY LC_MESSAGES

unpack_archive()
{
	rm -rf "$srcdir"
	if :; then
		missing=true
		test -z "$srcarchive" && srcarchive=${PACKAGENAME}${VERSION}
		for f in "$ARCHIVES_DIR/${srcarchive}.tar.xz" \
		         "$ARCHIVES_DIR/${srcarchive}.tar.zst" \
		         "$ARCHIVES_DIR/${srcarchive}.tar.lz" \
		         "$ARCHIVES_DIR/${srcarchive}.tar.bz2" \
		         "$ARCHIVES_DIR/${srcarchive}.tar.gz" \
		         "$ARCHIVES_DIR/${srcarchive}.tgz" \
		         "$ARCHIVES_DIR/${srcarchive}.tlz" \
		         "${here}/${srcarchive}.tar.xz" \
		         "${here}/${srcarchive}.tar.zst" \
		         "${here}/${srcarchive}.tar.lz" \
		         "${here}/${srcarchive}.tar.bz2" \
		         "${here}/${srcarchive}.tar.gz" \
		         "${here}/${srcarchive}.tgz" \
		         "${here}/${srcarchive}.tlz"; do
			if test -f "$f"; then missing=false; tar xf "$f" || exit 1; break; fi
		done
		if $missing; then
			echo "${srcarchive}.*: no such file" >&2
			exit 1
		fi
		if test ! -d "$srcdir"; then
			echo "$srcdir: no such directory" >&2
			exit 1
		fi
		if test -n "${PATCHARCHIVE}"; then
			mkdir -p "$BUILD_DIR/${PACKAGENAME}-patches"
			${TAR} -C "$BUILD_DIR/${PACKAGENAME}-patches" --strip-components=1 -xjf "${PATCHARCHIVE}"
			cd "$srcdir"
			for patch in $BUILD_DIR/${PACKAGENAME}-patches/${PACKAGENAME}*.patch
			do
			    patch -f -T -p1 -s --read-only=ignore < $patch
			done
			cd "$BUILD_DIR"
			rm -rf "$BUILD_DIR/${PACKAGENAME}-patches"
		fi
		for f in $PATCHES; do
		  if test -f "$f"; then
		    cd "$srcdir" || exit 1
		    flags=
		    if patch -N -s --dry-run -p1 -i "$BUILD_DIR/$f" > /dev/null 2>&1; then
		    	flags="-N -p1 --read-only=ignore"
		    	echo "applying patch $f"
			    patch $flags -i "$BUILD_DIR/$f" || exit 1
		    elif patch -R -N -s --dry-run -p1 -i "$BUILD_DIR/$f" > /dev/null 2>&1; then
		    	echo "patch $f already applied; skipping" >&2
		    else
		    	echo "patch $f does not apply" >&2
		    	exit 1
			fi
		  else
		    echo "missing patch $f" >&2
		    exit 1
		  fi
		  cd "$BUILD_DIR"
		done
	fi

	if test ! -d "$srcdir"; then
		echo "$srcdir: no such directory" >&2
		exit 1
	fi

	rm -rf "${THISPKG_DIR}"
}


#
# FIXME: does not work if arguments are too long
# and are split to several lines in config.status
#
hack_lto_cflags()
{
	configdirs="$@"
	if test "$configdirs" = ""; then configdirs=.; fi
	if test "$LTO_CFLAGS" != ""; then
		for dir in $configdirs; do
		(
		cd "$dir" || exit 1
        sed -i 's/^S\["CFLAGS"\]="\([^"]*\)"$/S\["CFLAGS"\]="'"$LTO_CFLAGS"' \1"/
s/^S\["CXXFLAGS"\]="\([^"]*\)"$/S\["CXXFLAGS"\]="'"$LTO_CFLAGS"' \1"/
s/^S\["BUILD_CFLAGS"\]="\([^"]*\)"$/S\["BUILD_CFLAGS"\]="'"$LTO_CFLAGS"' \1"/
s/^s,@CFLAGS@,\(.*\)$/s,@CFLAGS@,'"$LTO_CFLAGS"' \1/
s/^s,@CXXFLAGS@,\(.*\)$/s,@CXXFLAGS@,'"$LTO_CFLAGS"' \1/' config.status
		./config.status
		)
		done
	fi
}


move_prefix()
{
	cd "${THISPKG_DIR}"
	if test "${prefix}" != "${TARGET_PREFIX}"; then
		cd "${THISPKG_DIR}${sysroot}" || exit 1
		test ! -d "${TARGET_PREFIX}" || exit 1
		mv "${prefix}" "${TARGET_PREFIX}" || exit 1
	fi
}


gzip_docs()
{
	cd "${THISPKG_DIR}${sysroot}${TARGET_PREFIX}" || exit 1
	rm -f share/info/dir
	if test -d share/man; then
		find share/man \( -type f -o -type l \) | while read f; do
			case $f in
			*.gz) ;;
			*)
				if test -h $f; then
					t=$(readlink $f)
					case $t in
					*.gz) ;;
					*)
						rm -f $f $f.gz
						$LN_S $t.gz $f.gz
						;;
					esac
				else
					rm -f ${f}.gz; gzip -9 $f
				fi
				;;
			esac
		done
	fi
	if test -d share/info; then
		find share/info -type f | while read f; do
			case $f in
			*.gz) ;;
			*) rm -f ${f}.gz; gzip -9 $f ;;
			esac
		done
	fi
}


make_bin_archive()
{
	archsuffix=${1-000}

	gzip_docs

	cd "${THISPKG_DIR}${sysroot}" || exit 1
	files=""
	for i in ${BINFILES}; do
		i=${i#/}
		if test -d "$i" -o -f "$i" -o -h "$i"; then
			files="$files $i"
			if test -z "$NO_STRIP"; then
				case $i in 
				*/bin/* | */sbin/* | bin/* | sbin/*)
					if test ! -d "$i" -a ! -h "$i"; then
						"${strip}" "$i"
					fi
					;;
				esac
			fi
		else
			pwd
			echo "make_bin_archive: $i does not exist for packaging" >&2
			exit 1
		fi
	done

	if test -z "$files"; then
		echo "no files for bin archive; skipping" >&2
	else
		${TAR} ${TAR_OPTS} -Jcf ${DIST_DIR}/${BINTARNAME}-${archsuffix}.tar.xz $files
	fi
	
	cd "$MINT_BUILD_DIR" || exit 1
}


move_pkgconfig_libs_private()
{
	# If a *.pc has a Libs.private entry,
	# move the flags to the Libs entry, since we only
	# link against static libraries.
	# Most autoconf tests only use the entry from
	# pkg-config --libs, and would fail otherwise
	local file="$1"
	local lib
	local privlib
	local modified
	# If a *.pc has a Libs.private entry,
	libs=" "`sed -n 's,Libs: *\(.*\)$,\1,p' "$file"`" "
	libs_priv=" "`sed -n 's,Libs\.private: *\(.*\)$,\1,p' "$file"`" "
	modified=false;
	for lib in $libs_priv; do
		case $libs in
		*" "$lib" "*) ;;
		*) libs="$libs$lib "; modified=true ;;
		esac
	done
	if $modified; then
		sed -e 's,Libs: .*$,'"Libs: $libs"',' "$file" > "$file.tmp"
		mv "$file.tmp" "$file"
	fi
}

copy_pkg_configs()
{
	local pattern="${1:-*.pc}"
	local build_prefix="$prefix/$TARGET"
	local i base dst
	
	cd "${THISPKG_DIR}"

	case $TARGET in
	m68k-amigaos*)
		# with mcrt=nix*, the config files end up in a subdirectory; move them up
		if test -d ${THISPKG_DIR}${sysroot}${TARGET_PREFIX}/libnix/lib/pkgconfig; then
			rm -rf ${THISPKG_DIR}${sysroot}${TARGET_PREFIX}/libnix/lib/*/pkgconfig
			mkdir -p ${THISPKG_DIR}${sysroot}${TARGET_PREFIX}/lib
			mv ${THISPKG_DIR}${sysroot}${TARGET_PREFIX}/libnix/lib/pkgconfig ${THISPKG_DIR}${sysroot}${TARGET_PREFIX}/lib/pkgconfig
		fi
		;;
	esac

	if test -d .${sysroot}$TARGET_LIBDIR/pkgconfig; then
	mkdir -p ./$build_prefix/lib/pkgconfig
	
	#
	# replace absolute pathnames by their symbolic equivalents
	# and remove unneeded -I and -L switches,
	# since those directories are always on the
	# default search path.
	# remove -L${sharedlibdir}, because
	# sharedlibdir is the bin directory, but the import libraries
	# are in the lib directory
	#
	for i in .${sysroot}$TARGET_LIBDIR/pkgconfig/$pattern; do
		test -e "$i" || continue
		true && {
			# from the *.pc files generated for the target,
			# generate *.pc files that are suitable for the cross-compiler
			base=${i##*/}
			dst=./$build_prefix/lib/pkgconfig/$base
			if test ! -f $dst -o $i -nt $dst; then
				cp -a $i $dst
				test -h "$i" && continue
				move_pkgconfig_libs_private "$dst"
				sed -i 's,",,g
						 s,prefix[ ]*=[ ]*'${configured_prefix}',prefix='${sysroot}${TARGET_PREFIX}',
			             /^prefix[ ]*=/{p;d}
			             s,=[ ]*'$prefix',=${prefix},
			             s,-L'$TARGET_LIBDIR',-L${libdir},g
			             s,-L${sharedlibdir} ,,g
			             s,-L${exec_prefix}/lib,-L${libdir},g
			             s,-L${libdir} ,,g
			             s,-L${libdir}$,,
			             s,-L'${TARGET_BINDIR}'[ ]*,,g
			             s,-I/usr/include,-I${includedir},g
			             s,-I'${sysroot}${TARGET_PREFIX}/include',-I${includedir},g' $dst
				includedir=`sed -n 's/^[ ]*includedir[ ]*=[ ]*\([^ ]*\)/\1/p' $dst`
				if test "$includedir" = '/usr/include' -o "$includedir" = '${prefix}/include' -o "$includedir" = '${prefix}/sys-include'; then
					sed -i 's,-I${prefix}/include,-I${includedir},g
					     s,-I${includedir} ,,g
					     s,-I${includedir}$,,' $dst
				fi
			fi
		}
		true && {
			sed -e 's,",,g
					 s,prefix[ ]*=[ ]*'${configured_prefix}',prefix='${TARGET_PREFIX}',
			         /^prefix[ ]*=/{p;d}
			         s,[ ]*=[ ]*'$prefix',=${prefix},
			         s,-L'$TARGET_LIBDIR',-L${libdir},g
		             s,-L${sharedlibdir} ,,g
		             s,-L${exec_prefix}/lib,-L${libdir},g
			         s,-L${libdir} ,,g
			         s,-L${libdir}$,,
		             s,-L'${TARGET_BINDIR}'[ ]*,,g
 		             s,-I/usr/include,-I${includedir},g
		             s,-I'${sysroot}${TARGET_PREFIX}/include',-I${includedir},g' $i > $i.tmp
			includedir=`sed -n 's/^[ ]*includedir[ ]*=[ ]*\([^ ]*\)/\1/p' $i.tmp`
			if test "$includedir" = '/usr/include' -o "$includedir" = '${prefix}/include' -o "$includedir" = '${prefix}/sys-include'; then
				sed -i 's,-I${prefix}/include,-I${includedir},g
				     s,-I${includedir} ,,g
				     s,-I${includedir}$,,' $i.tmp
			fi
			move_pkgconfig_libs_private "$i.tmp"
			diff -q $i $i.tmp >/dev/null && rm -f $i.tmp || {
				echo "fixed $i"
				mv $i.tmp $i
			}
		}
	done
	fi
}


make_archives()
{
	gzip_docs

	cd "${THISPKG_DIR}${sysroot}${TARGET_PREFIX}" || exit 1
	find . \( -type f -o -xtype l \) -name "*.la" -delete -printf "rm %p\n"
	if test -z "$NO_STRIP"; then
		test "$LTO_CFLAGS" != "" || find . -name "*.a" ! -type l -exec "${strip}" -S -x '{}' \;
	fi
	if test -z "$NO_RANLIB"; then
		find . -name "*.a" ! -type l -exec "${ranlib}" '{}' \;
	fi
	
	if test -d "${THISPKG_DIR}${sysroot}${TARGET_PREFIX}/bin"; then
		cd "${THISPKG_DIR}${sysroot}${TARGET_PREFIX}/bin"
		for i in *; do
			test -h "$i" && continue
			test -d "$i" && continue
			if test -z "$NO_STRIP"; then
				"${strip}" "$i"
			fi
		done
	fi
	
	if test -d "${THISPKG_DIR}${sysroot}${TARGET_PREFIX}/libexec"; then
		cd "${THISPKG_DIR}${sysroot}${TARGET_PREFIX}/libexec"
		for i in `find . -type f`; do
			test -h "$i" && continue
			test -d "$i" && continue
			if test -z "$NO_STRIP"; then
				"${strip}" "$i"
			fi
		done
	fi
	
	#
	# remove pkgconfig dirs in architecture dependent subdirs
	# we only need the one in the toplevel directory
	#
	case $TARGET in
	m68k-amigaos*)
		# with mcrt=nix*, the config files end up in a subdirectory; move them up
		if test -d ${THISPKG_DIR}${sysroot}${TARGET_PREFIX}/libnix/lib/pkgconfig; then
			rm -rf ${THISPKG_DIR}${sysroot}${TARGET_PREFIX}/libnix/lib/*/pkgconfig
			mkdir -p ${THISPKG_DIR}${sysroot}${TARGET_PREFIX}/lib/
			mv ${THISPKG_DIR}${sysroot}${TARGET_PREFIX}/libnix/lib/pkgconfig ${THISPKG_DIR}${sysroot}${TARGET_PREFIX}/lib/pkgconfig
		fi
		;;
	*)
		rm -rf ${THISPKG_DIR}${sysroot}${TARGET_PREFIX}/lib/*/pkgconfig
		;;
	esac

	cd "${THISPKG_DIR}" || exit 1

	${TAR} ${TAR_OPTS} -Jcf ${DIST_DIR}/${TARNAME}-dev.tar.xz *

	if test -n "${BINFILES}"; then
		cd "${THISPKG_DIR}${sysroot}" || exit 1
		files=""
		for i in ${BINFILES}; do
			i=${i#/}
			if test -d "$i" -o -f "$i" -o -h "$i"; then
				files="$files $i"
			else
				echo "make_archives: $i does not exist for packaging" >&2
				exit 1
			fi
		done
		
		rm -rf $files
		cd "${THISPKG_DIR}" || exit 1
		files=`find . -type f`
		if test "$files" = ""; then
			echo "no dev files, removing ${TARNAME}-dev.tar.xz"
			rm -f ${DIST_DIR}/${TARNAME}-dev.tar.xz
		fi
	fi
	
	cd "${BUILD_DIR}" || exit 1
	if test "$KEEP_PKGDIR" != yes; then
		rm -rf "${THISPKG_DIR}"
	fi
	if test "$KEEP_SRCDIR" != yes; then
		rm -rf "${srcdir}"
	fi

	test -z "${PATCHES}${DISABLED_PATCHES}" || ${TAR} ${TAR_OPTS} -Jcf ${DIST_DIR}/${BINTARNAME}.tar.xz ${PATCHES} ${DISABLED_PATCHES} ${POST_INSTALL_SCRIPTS} ${PATCHARCHIVE}
	cp -p "$me" ${DIST_DIR}/${PACKAGENAME}${VERSION}${VERSIONPATCH}-build.sh
	cp -p "${scriptdir}/functions.sh" "${DIST_DIR}"
}


append_gnulib_cache()
{
cat <<EOF >>config.cache
ac_cv_func_malloc_0_nonnull=yes
ac_cv_func_realloc_0_nonnull=yes
ac_cv_func_chown_works=yes
ac_cv_func_getgroups=yes
ac_cv_func_getgroups_works=yes
am_cv_func_working_getline=yes
ac_cv_func_working_mktime=yes
ac_cv_func_gettimeofday=yes
gl_cv_func_chown_slash_works=yes
gl_cv_func_chown_ctime_works=yes
gl_cv_func_fflush_stdin=yes
gl_cv_func_fcntl_f_dupfd_works=yes
gl_cv_func_getcwd_abort_bug=no
gl_cv_func_getcwd_path_max=yes
gl_cv_func_getcwd_null=yes
gl_cv_func_getdtablesize_works=yes
gl_cv_func_getgroups=yes
gl_cv_func_getgroups_works=yes
gl_cv_func_getopt_gnu=yes
gl_cv_func_getopt_posix=yes
gl_cv_func_working_getdelim=yes
gl_cv_func_malloc_0_nonnull=1
gl_cv_func_mbrlen_empty_input=yes
gl_cv_func_memchr_works=yes
gl_cv_func_working_mktime=yes
gl_cv_func_perror_works=yes
gl_cv_func_printf_sizes_c99=yes
gl_cv_func_printf_infinite=yes
gl_cv_func_printf_infinite_long_double=no
gl_cv_func_printf_directive_a=no
gl_cv_func_printf_directive_f=no
gl_cv_func_printf_directive_n=yes
gl_cv_func_printf_directive_ls=no
gl_cv_func_printf_positions=yes
gl_cv_func_printf_flag_grouping=yes
gl_cv_func_printf_flag_zero=yes
gl_cv_func_printf_enomem=yes
gl_cv_func_realpath_works=yes
gl_cv_func_rmdir_works=yes
gl_cv_func_snprintf_truncation_c99=yes
gl_cv_func_snprintf_retval_c99=yes
gl_cv_func_snprintf_directive_n=yes
gl_cv_func_symlink_works=yes
gl_cv_func_vsnprintf_zerosize_c99=yes
gl_cv_func_signbit=yes
gl_cv_func_signbit_gcc=yes
gl_cv_func_stpncpy=yes
gl_cv_func_working_strerror=yes
gl_cv_func_strerror_0_works=yes
gl_cv_func_strerror_r_works=yes
gl_cv_func_strerror_r_posix_signature=yes
gl_cv_func_memchr_works=yes
gl_cv_func_strstr_works_always=yes
gl_cv_func_strstr_linear=yes
gl_cv_func_strtod_works=yes
gl_cv_func_fcntl_f_dupfd_works=no
gl_cv_func_fdopendir_works=yes
gl_cv_func_gettimeofday_clobber=no
gl_cv_func_ungetc_works=yes
gl_cv_func_link_follows_symlink=no
gl_cv_func_lstat_dereferences_slashed_symlink=yes
gl_cv_func_mkdir_trailing_dot_works=yes
gl_cv_func_mkdir_trailing_slash_works=yes
gl_cv_func_readlink_works=yes
gl_cv_func_setenv_works=yes
gl_cv_func_sleep_works=yes
gl_cv_func_snprintf_usable=yes
gl_cv_func_stat_file_slash=yes
gl_cv_func_unsetenv_works=yes
gl_cv_func_vsnprintf_usable=yes
gl_cv_func_working_utimes=yes
gl_cv_struct_dirent_d_ino=yes
gl_cv_func_wcwidth_works=yes
gl_cv_func_printf_directive_n=yes
EOF
}

# fu_cv_sys_stat_statfs2_fsize
