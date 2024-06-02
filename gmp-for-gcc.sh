#
# Now, for darwin, build gmp etc.
#
base_url='https://gcc.gnu.org/pub/gcc/infrastructure/'

gmp="https://gmplib.org/download/gmp/gmp-6.3.0.tar.xz"
mpfr="https://www.mpfr.org/mpfr-current/mpfr-4.2.1.tar.xz"
mpc="https://ftp.gnu.org/gnu/mpc/mpc-1.3.1.tar.gz"
isl="${base_url}/isl-0.18.tar.bz2"

if test $host = macos; then
	mkdir -p "$CROSSTOOL_DIR"

	if test ! -f "$CROSSTOOL_DIR/lib/libgmp.a"; then
		cd "$CROSSTOOL_DIR" || exit 1
		mkdir -p lib include
		archive=$gmp
		basename=${archive##*/}
		package="${basename%.tar*}"
		rm -rf "${package}"
		if test -f "${scriptdir}/3rdparty/${basename}"; then
			echo "unpacking ${basename}"
			$TAR xf "${scriptdir}/3rdparty/${basename}" || exit 1
		else
			echo "fetching ${archive}"
			wget -nv "${archive}" || exit 1
			$TAR xf "${basename}" || exit 1
		fi
		cd "${package}" || exit 1

		patch -p1 < "$BUILD_DIR/patches/gmp/gmp-universal.patch" || exit 1
		# already applied in 6.3.0
		# patch -p1 < "$BUILD_DIR/patches/gmp/gmp-6.2.1-CVE-2021-43618.patch" || exit 1
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
		basename=${archive##*/}
		package="${basename%.tar*}"
		rm -rf "${package}"
		if test -f "${scriptdir}/3rdparty/${basename}"; then
			echo "unpacking ${basename}"
			$TAR xf "${scriptdir}/3rdparty/${basename}" || exit 1
		else
			echo "fetching ${archive}"
			wget -nv "${archive}" || exit 1
			$TAR xf "${basename}" || exit 1
		fi
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
		basename=${archive##*/}
		package="${basename%.tar*}"
		rm -rf "${package}"
		if test -f "${scriptdir}/3rdparty/${basename}"; then
			echo "unpacking ${basename}"
			$TAR xf "${scriptdir}/3rdparty/${basename}" || exit 1
		else
			echo "fetching ${archive}"
			wget -nv "${archive}" || exit 1
			$TAR xf "${basename}" || exit 1
		fi
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


