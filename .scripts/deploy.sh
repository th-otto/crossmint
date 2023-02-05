#!/bin/sh -x

GCC=${GCC-gcc}
case `uname -s` in
	MINGW64*) HOST_TYPE=mingw64 ;;
	MINGW32*) HOST_TYPE=mingw32 ;;
	MINGW*) if echo "" | ${GCC} -dM -E - 2>/dev/null | grep -q i386; then HOST_TYPE=mingw32; else HOST_TYPE=mingw64; fi ;;
	MSYS*) HOST_TYPE=msys ;;
	CYGWIN*) if echo "" | ${GCC} -dM -E - 2>/dev/null | grep -q i386; then HOST_TYPE=cygwin32; else HOST_TYPE=cygwin64; fi ;;
	Darwin*) HOST_TYPE=macos ;;
	*) HOST_TYPE=linux64
	   if echo "" | ${GCC} -dM -E - 2>/dev/null | grep -q i386; then HOST_TYPE=linux32; fi
	   ;;
esac

UPLOAD_DIR=web196@server43.webgo24.de:/home/www/snapshots/crossmint/${HOST_TYPE}

PROJECT_REPO=$(echo "${GITHUB_REPOSITORY}" | cut -d '/' -f 1)
# PROJECT_VERSION is defined in the action script
# DEPLOY_DIR must match the settings in the build script(s)
DEPLOY_DIR=pkgs

SHORT_ID=$(echo ${GITHUB_SHA} | cut -c 1-3)
LONG_ID=$(echo ${GITHUB_SHA} | cut -c 1-8)
BRANCH=$(echo "${GITHUB_REF}" | cut -d '/' -f 3)

# GITHUB_HEAD_REF is only set for pull requests
if [ "${GITHUB_HEAD_REF}" = "" ]
then
    COMMIT_MESSAGE="[${PROJECT_NAME}] [${BRANCH}] Commit: https://github.com/${PROJECT_REPO}/${PROJECT_NAME}/commit/${GITHUB_SHA}"
fi

eval "$(ssh-agent -s)"

PROJECT_DIR="$PROJECT_NAME"

upload_file() {
	local from="$1"
	local to="$2"
	for i in 1 2 3
	do
		scp -o "StrictHostKeyChecking no" "$from" "$to"
		[ $? = 0 ] && return 0
		sleep 1
	done
	exit 1
}

for ARCHIVE_PATH in $DEPLOY_DIR/*; do
	ARCHIVE_NAME=${ARCHIVE_PATH##*/}
	upload_file "$ARCHIVE_PATH" "${UPLOAD_DIR}/${PROJECT_DIR}/${ARCHIVE_NAME}"
done

if test "${PROJECT_VERSION}" != ""; then
	echo ${PROJECT_NAME}-${PROJECT_VERSION}-${SHORT_ID} > .latest_version
	upload_file .latest_version "${UPLOAD_DIR}/${PROJECT_DIR}/.latest_version"
fi
