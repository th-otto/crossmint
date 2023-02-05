#!/bin/sh

project=$1
target=$2

./$project-build.sh $target
status=$?

if test $status != 0; then
	# DEPLOY_DIR must match the settings in the build script(s) and in deploy.sh
	DEPLOY_DIR=pkgs
	mkdir -p $DEPLOY_DIR
	find . -name config.log | xargs tar cvfJ $DEPLOY_DIR/$project-$target-logs.tar.xz
	if test -f $DEPLOY_DIR/$project-$target-logs.tar.xz; then
		export PROJECT_NAME=$project
		.scripts/deploy.sh
	fi
fi

exit $status
