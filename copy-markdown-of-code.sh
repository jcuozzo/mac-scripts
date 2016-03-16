#!/bin/bash

case $# in
	0)
		pbpaste | sed -e 's/^/    /' | pbcopy
		exit 0
		;;
	1)
		sed -e 's/^/    /' "$1" | pbcopy
		exit 0
		;;
	*)
		echo "Error: Too many arguments."
		exit 1
		;;
esac