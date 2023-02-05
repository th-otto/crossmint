#!/bin/sh -x

UPLOAD_DIR=web196@server43.webgo24.de:/home/www/snapshots/crossmint/${HOST_TYPE}

PROJECT_REPO=$(echo "${GITHUB_REPOSITORY}" | cut -d '/' -f 1)
# PROJECT_VERSION is defined in the action script
DEPLOY_DIR=pkgs

SHORT_ID=$(echo ${GITHUB_SHA} | cut -c 1-3)
LONG_ID=$(echo ${GITHUB_SHA} | cut -c 1-8)
BRANCH=$(echo "${GITHUB_REF}" | cut -d '/' -f 3)

# GITHUB_HEAD_REF is only set for pull requests
if [ "${GITHUB_HEAD_REF}" = "" ]
then
    COMMIT_MESSAGE="[${PROJECT_NAME}] [${BRANCH}] Commit: https://github.com/${PROJECT_REPO}/${PROJECT_NAME}/commit/${GITHUB_SHA}"
fi

# must match TARNAME in build script
ARCHIVE_NAME="${PROJECT_NAME}-${VERSION}-${TARGET##*-}${VERSIONPATCH}-bin-${HOST_TYPE}.tar.xz"
ARCHIVE_PATH="${DEPLOY_DIR}/${ARCHIVE_NAME}"

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

upload_file "$ARCHIVE_PATH" "${UPLOAD_DIR}/${PROJECT_DIR}/${ARCHIVE_NAME}"

echo ${PROJECT_NAME}-${PROJECT_VERSION}-${SHORT_ID} > .latest_version
upload_file .latest_version "${UPLOAD_DIR}/${PROJECT_DIR}/.latest_version"
