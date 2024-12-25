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
VERSION="0.7.0"
USER_AGENT="$NAME/$VERSION (/bin/sh)"

# If we do not have the 'mktemp' program then we can stop immediately.
which mktemp >/dev/null
if test "$?" -ne "0"
then
    echo "error: missing mktemp program"
    exit 3
fi

# This represents the URL format we use for output.  Here are the
# valid values with examples of the URLs they ultimate create:
#
#     ".git_url"  - git://github.com/ejmr/git-ls-github-forks
#     ".http_url" - https://github.com/ejmr/git-ls-github-forks
#     ".svn_url"  - https://svn.github.com/ejmr/git-ls-github-forks
#     ".ssh_url"  - git@github.com:ejmr/git-ls-github-forks
#     ".url"      - https://api.github.com/repos/ejmr/git-ls-github-forks
#
# By default we use the Git format.  Assigning any other string to
# this variable will break the program.  The $FORMAT_URL variable
# names the JSON property we extract to get the desired URL, and it
# must be syntactically valid for the jq program.  See the $JSON_QUERY
# variable to see exactly where $FORMAT_URL fits in.
FORMAT_URL="\(.git_url)"

# Here we define all of the command-line options, process them so that
# they are available variables, and then perform the necessary actions
# for each.

USAGE=$(cat <<EOF
$NAME [options]

-f, --format <format>
    Display the URLs in the style of <format>, which must be one of
    the following: "git", "http", "svn", "ssh", or "api".  The value
    "git" is the default.

-n, --name
    Display the owner of the fork.

-s, --sort <property>
    Sort all URLs based on <property>, which must one of the
    following: "newest", "oldest", or "watchers".  The default is
    "newest", which lists forks with the most recent changes first.

--rate-limit
    GitHub places an hourly limit on the number of API requests the
    program can make.  This option shows two values: the number of
    remaining requests available and the date and time when the amount
    of requests allowed will reset to its maximum value.  Using this
    option does not count against the number of remaining requests.
    The program will exit without displaying any forks if given this
    option, which makes it mutually exclusive to the default behavior
    of listing forks.

--verbose
    The program saves the response from GitHub in a temporary file
    debugging purposes.  This option will print that filename to
    standard error.

--usage    Display this help
--version  Show the current version number
EOF
)

OPTIONS=$(getopt --name "$NAME" \
    --quiet \
    --shell "sh" \
    --options "f:ns:" \
    --longoptions "format:" \
    --longoptions "name" \
    --longoptions "sort:" \
    --longoptions "rate-limit" \
    --longoptions "verbose" \
    --longoptions "version" \
    --longoptions "usage" \
    -- "$@")

# If $? is not zero then getopt received an unrecognized option, which
# is a fatal error.  So we print the $USAGE string and exit.  It would
# be better, however, if we pointed out the bad option.  The getopt
# program does this by default but we throw away everything sent to
# Standard Error when calling getopt because otherwise the output
# looks like clutter.
if test "$?" -ne "0"
then
    echo "usage: $USAGE"
    exit 1
fi

# If this has a non-zero value then we print the name of the temporary
# output file later.  The --verbose flag enables this behavior.
VERBOSE="0"

# This variable contains text that we give to the 'jq' program in
# order to select the owner of each fork.  However, we only do this
# when invoking the program with the '-n' or '--name' options.  By
# default the variable is an empty string so that we can insert it
# directly into the query for 'jq' later regardless of whether or not
# the program receives those options.
FORK_OWNER=""

# This variable contains value of the 'sort' parameter that we give to
# the GitHub API call.  See the documentation at
#
#     http://developer.github.com/v3/repos/forks/
#
# for details on acceptable values.  We also document those same
# values in the program, but the documentation in the URL above is
# always correct in the event of any discrepancies.  This is an
# optional parameter for the GitHub API but we always explicitly use
# it with our API calls.  Therefore we give it the default value that
# GitHub uses in the absence of the parameter.
SORT_ORDER="newest"

# Perform actions and set variables based on the command-line options.
while true
do
    case "$1" in

        # Reading http://developer.github.com/v3/#rate-limiting
        # explains the 'GET /rate_limit' method we call.  We must
        # create raw output from 'jq', otherwise the results will be
        # wrapped in quotes that will screw up 'date' later on.
        --rate-limit)
            curl --silent "$API_URL/rate_limit" \
                | jq --raw-output "\"\(.rate.remaining) \(.rate.reset)\"" \
                | while read REMAINING RESET_DATE
            do
                echo "Status: $REMAINING remaining API requests until $(date --date=@$RESET_DATE)"
            done
            exit 0 ;;

        -f|--format)
            case "$2" in
                git) ;;
                http) FORMAT_URL="\(.html_url)" ;;
                svn) FORMAT_URL="\(.svn_url)" ;;
                ssh) FORMAT_URL="\(.ssh_url)" ;;
                api) FORMAT_URL="\(.url)" ;;
                *) echo "usage: $USAGE"; exit 1 ;;
            esac
            shift 2 ;;

        -s|--sort)
            SORT_ORDER="$2"
            shift 2 ;;

        --verbose)
            VERBOSE="1"
            shift ;;

        # Later we add the contents of $FORK_OWNER to the query we
        # give to the 'jq' program.  Note that the value must begin
        # with a comma so that ultimately we end up with a
        # syntactically correct query.
        -n|--name)
            FORK_OWNER="\(.owner.login)"
            shift ;;
        
        --version) echo "$NAME $VERSION"; exit 0 ;;
        --usage) echo "usage: $USAGE"; exit 0 ;;
        
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
# Finally, we also add the $SORT_ORDER parameter to the request.
REPOSITORY=$(basename --suffix=".git" "$REPOSITORY_URL")
OWNER=${REPOSITORY_URL#https://github.com/}
OWNER=${OWNER%/${REPOSITORY}.*}

DATA_URL="/repos/$OWNER/$REPOSITORY/forks"

# We save output from GitHub into a temporary file for debugging
# purposes.  The file will be in the system's temporary directory and
# will have the filename 'github.json.XXXXXX' where the final six
# characters are random.
TEMPORARY_OUTPUT_FILE=$(mktemp -t "github.json.XXXXXX")

# Fetch the JSON data about forks from GitHub and extract all of the
# URLs for those forks, sending them to standard output.
gh api \
    --header "Accept: application/vnd.github+json" \
    --method GET "$DATA_URL" \
    --paginate \
    -F sort=${SORT_ORDER} \
    -F per_page=100 \
    -q ".[] | @text \"$FORMAT_URL $FORK_OWNER\"" \
    | tee "$TEMPORARY_OUTPUT_FILE"

# If we are running in verbose mode then we echo the name of
# $TEMPORARY_OUTPUT_FILE to standard error.  The primary purpose of
# the program is to provide 'plumbing' output for other Git commands
# which is why we use standard error to show this information instead
# of standard output.
if test "$VERBOSE" -ne "0"
then
    echo "$TEMPORARY_OUTPUT_FILE" >/dev/stderr
fi

# Mission accomplished, so we exit successfully and then try to think
# of something actually productive to do as opposed to doing anything
# to this script.
exit 0
