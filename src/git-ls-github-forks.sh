#!/bin/sh
#
# git ls-github-forks
#
# Project: https://github.com/ejmr/git-ls-github-forks
# Author:  Eric James Michael Ritz
# License: GNU General Public License 3
#
######################################################################

API_URL="https://api.github.com"

# GitHub will reject requests that do not send the User-Agent header.
# They suggest using either the author name or the program name as the
# User-Agent.  We use the program name since other programmers may
# create forks.  We also include the implementation because in the
# future this program may exist in different programming languages.
NAME="git-ls-github-forks"
VERSION="0.2.0"
USER_AGENT="$NAME/$VERSION (/bin/sh)"

# Here we define all of the command-line options, process them so that
# they are available variables, and then perform the necessary actions
# for each.

USAGE="[-v|--version]"

OPTIONS=$(getopt --name "$NAME" \
    --shell "sh" \
    --options "v::" \
    --longoptions "version::" \
    -- "$@" 2>/dev/null)

# If $? is not zero then getopt received an unrecognized option, which
# is a fatal error.  So we print the $USAGE string and exit.  It would
# be better, however, if we pointed out the bad option.  The getopt
# program does this by default but we throw away everything sent to
# Standard Error when calling getopt because otherwise the output
# looks like clutter.
if test "$?" -ne "0"
then
    echo "usage: $NAME $USAGE"
    exit 1
fi

eval set -- "$OPTIONS"

while true
do
    case "$1" in
        -v|--version) echo "Version $VERSION"; exit 0 ;;
        *) break ;;
    esac
done

# Get the remote GitHub repository URL.  We use this later but at
# first we want to make sure it exists so that we know this repository
# exists on GitHub.
REPOSITORY_URL=$(git ls-remote --get-url)

# It is possible for git-ls-remote to fail for different reasons, so
# if that happens then we exit immediately.  We do not use the exit
# code of git-ls-remote.  However, failure will show the user the
# error message from Git.
if test "$?" -ne "0"
then
    exit 2
fi

# We want to send a request to
#
#     https://api.github.com/repos/OWNER/REPOSITORY/forks
#
# so here we obtain the user's GitHub name and the repository name to
# insert into $DATA_URL, which will be in the format shown above.
OWNER=$(git config --get github.user)
REPOSITORY=$(basename --suffix=".git" "$REPOSITORY_URL")
DATA_URL="$API_URL/repos/$OWNER/$REPOSITORY/forks"

# This is the template we give to the jq program in order to extract
# and display the URL for each fork.
JSON_QUERY=".[] | .git_url"

# Fetch the JSON data about forks from GitHub and extract all of the
# URLs for those forks, sending them to standard output.
curl --silent \
    --user-agent "$USER_AGENT" \
    --header "Accept: application/vnd.github.beta+json" \
    "$DATA_URL" \
    | jq --raw-output --monochrome-output "$JSON_QUERY"

# Mission accomplished, so we exit successfully and then try to think
# of something actually productive to do as opposed to doing anything
# to this script.
exit 0
