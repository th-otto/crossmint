#
# Now, for darwin, build zstd library
#
zstd='zstd-1.5.5.tar.gz'
zstd_url='https://github.com/facebook/zstd/releases/download/v1.5.5/zstd-1.5.5.tar.gz'

if test $host = macos; then
	mkdir -p "$CROSSTOOL_DIR"

	if test ! -f "$CROSSTOOL_DIR/lib/libzstd.a"; then
		cd "$CROSSTOOL_DIR" || exit 1
		mkdir -p lib/pkgconfig include
		archive=$zstd
		package="${archive%.tar*}"
		echo "fetching ${archive}"
		wget -nv "${zstd_url}" || exit 1
		rm -rf "${package}"
		$TAR xf "$archive" || exit 1
		cd "${package}" || exit 1

		CFLAGS="-O2 -arch x86_64" \
		CXXFLAGS="-O2 -arch x86_64" \
		LDFLAGS="-O2 -arch x86_64" \
		prefix="$CROSSTOOL_DIR" \
		DESTDIR="$CROSSTOOL_DIR/install-x86_64" \
		${MAKE} $JOBS -C lib libzstd.a libzstd.pc install-static install-pc install-includes || fail "zstd"
		
		if test "$BUILD_ARM64" = yes; then
			cd "${CROSSTOOL_DIR}/${package}"
			${MAKE} clean
			CFLAGS="-O2 -arch arm64" \
			CXXFLAGS="-O2 -arch arm64" \
			LDFLAGS="-O2 -arch arm64" \
			prefix="$CROSSTOOL_DIR" \
			DESTDIR="$CROSSTOOL_DIR/install-arm64" \
			${MAKE} $JOBS -C lib libzstd.a libzstd.pc install-static install-pc install-includes || fail "zstd"
			cd "$CROSSTOOL_DIR"
			lipo -create "install-arm64/$CROSSTOOL_DIR/lib/libzstd.a" -create "install-x86_64/$CROSSTOOL_DIR/lib/libzstd.a" -output lib/libzstd.a
		elif test "$BUILD_I386" = yes; then
			cd "${CROSSTOOL_DIR}/${package}"
			${MAKE} clean
			CFLAGS="-O2 -arch i386" \
			CXXFLAGS="-O2 -arch 386" \
			LDFLAGS="-O2 -arch 386" \
			prefix="$CROSSTOOL_DIR" \
			DESTDIR="$CROSSTOOL_DIR/install-386" \
			${MAKE} $JOBS -C lib libzstd.a libzstd.pc install-static install-pc install-includes || fail "zstd"
			cd "$CROSSTOOL_DIR"
			lipo -create "install-386/$CROSSTOOL_DIR/lib/libzstd.a" -create "install-x86_64/$CROSSTOOL_DIR/lib/libzstd.a" -output lib/libzstd.a
		else
			cd "$CROSSTOOL_DIR"
			mv "install-x86_64/$CROSSTOOL_DIR/lib/"*.a lib
		fi
		mv "install-x86_64/$CROSSTOOL_DIR/lib/pkgconfig/"*.pc lib/pkgconfig
		sed $SED_INPLACE 's/-pthread//' lib/pkgconfig/libzstd.pc
		
		mv "install-x86_64/$CROSSTOOL_DIR/include/"* include
		rm -rf install-*
	fi
fi


