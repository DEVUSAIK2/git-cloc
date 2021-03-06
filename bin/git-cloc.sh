#!/bin/bash

# flags
debug=

# tools
debug(){
    if [ -n "$debug" ]; then
        echo "$@" >&2
    fi
}

#overload arguments
after=
before=
author=
# branch=master
recursive=
recurse_depth=10
no_summary=
output=
month=
cwd="$PWD"

Y=`date +%Y`
M=`date +%m`
D=`date +%d`
h=`date +%H`
m=`date +%M`
s=`date +%S`
TIME="$Y-$M-$D $h.$m.$s"

cloc_counter=0
print_result=()
print_result[$cloc_counter]="Repos Changed-Files Insertions Deletions\n"

add_print(){
    (( cloc_counter += 1 ))
    print_result[$cloc_counter]="$1\n"
}


while [[ $# -gt 0 ]]; do
    opt="$1"
    shift
    case "$opt" in
        --no-summary)
            no_summary=1; debug "no summary: $no_summary"
            ;;

        --since|--after)
            after="$1"; debug "after: $after"
            shift
            ;;

        --until|--before)
            before="$1"; debug "before: $before"
            shift
            ;;

        # TODO
        -b|--branch)
            branch="$1"; debug "branch: $branch"
            shift
            ;;

        -r|--recursive)
            recursive=1; debug "recursive: on"
            # no shift
            ;;

        --month)
            month="$1"; debug "month: $month"
            shift
            ;;

        --recurse-depth)
            recurse_depth="$1"; debug "recurse depth: $recurse_depth"
            shift
            ;;

        -o|--output)
            output="$1"; debug "output file: $output"
            shift
            ;;

        -c|--cwd)
            cwd="$1"; debug "cwd: $cwd"
            shift
            ;;

        --)
            break
            ;;

        *)
            echo "Unexpected option: $opt"
            exit 1
            ;;
    esac
done

# generate git log query
log_query="git log"

if [[ -n "$month" ]]; then
    single_year=`echo $month | cut -d '-' -f1`
    single_month=`echo $month | cut -d '-' -f2`
    after="$month-1"
    before="$single_year-`expr $single_month + 1`-1"
fi

if [[ -n "$author" ]]; then
    log_query+=" --author $author"
fi

if [[ -n "$after" ]]; then
    log_query+=" --after $after"
fi

if [[ -n "$before" ]]; then
    log_query+=" --before $before"
fi

if [[ -n "$branch" ]]; then
    : # log_query=`echo "$log_query --branches $branch"`
fi

debug "git log query: $log_query"


# directory walker
# @private
# @param {string} $1 directory
# @param {int} $2 depth
git_repos(){
    # debug "seaching git repos in: $1"

    local current_depth="$2"
    local sub_depth=

    # or `expr` will throw a syntax error
    if [[ ! -n "$current_depth" ]]; then
        current_depth=0
    fi

    for file in $1/*
    do
        if [[ -d "$file" ]]; then
            if [[ -d "$file/.git" ]]; then
                # debug "git repo found: $file"
                cloc $file
            else
                if [[ "$current_depth" -gt "$recurse_depth" ]]; then
                    continue
                fi

                sub_depth=`expr $current_depth + 1`
                git_repos $file $sub_depth
            fi
        fi
    done
}


# main function
cloc(){
    cd $1

    local last_commit=$($log_query --pretty=format:'%H' -1)

    # use `echo` to convert the stdout into a single line
    # cut the first part
    local first_commit=`echo $($log_query --pretty=format:'%H' --reverse) | cut -d ' ' -f1`
    local diff_result=
    local repo=`basename $1`
    local print_line="$repo"

    local info=
    local info_len=

    local slice=
    local slice_i=
    local slice_i_plus_one=

    # debug "first commit: $first_commit"
    # debug "last commit: $last_commit"

    # test if `first_commit` is already the earlist commit
    # direct both stdout and stderr to NULL
    if git diff "$first_commit^1" "$first_commit" --shortstat &> /dev/null; then
        first_commit="$first_commit^1"
    fi

    if [[ -n "$last_commit" && -n "$first_commit" ]]; then
        diff_result=`git diff "$first_commit" "$last_commit" --shortstat`

        if [[ -n "$diff_result" ]]; then

            info=( $diff_result )
            info_len=${#info[@]}

            slice_i=0
            while [[ $slice_i -lt $info_len ]]; do

                slice=${info[$slice_i]}
                slice_i_plus_one=`expr $slice_i + 1`
                (( slice_i += 1 ))

                if [[ $slice_i_plus_one -ge $info_len ]]; then
                    continue
                fi

                case ${info[$slice_i_plus_one]} in

                    # file or files
                    file* )
                        print_line="$print_line $slice"; debug "files add $slice"
                        (( slice_i += 1 ))
                        ;;

                    # insertions
                    insertion* )
                        print_line="$print_line $slice"; debug "insertions add $slice"
                        (( slice_i += 1 ))
                        ;;

                    # deletions
                    deletion* )
                        print_line="$print_line $slice"; debug "deletions add $slice"
                        (( slice_i += 1 ))
                        ;;

                    * )
                        ;;
                esac
            done # end while slice_i   
        fi

    else
        print_line="$print_line 0 0 0"
    fi

    add_print "$print_line"
}


# print result
summary(){
    echo -e ${print_result[@]} | awk '{printf "%-30s %-15s %-12s %-11s\n",$1,$2,$3,$4}'

    if [[ -n $output ]]; then
        echo -e ${print_result[@]} | awk '{printf "%-30s %-15s %-12s %-11s\n",$1,$2,$3,$4}' > "$output"
    fi

    if [[ ! -n $no_summary ]]; then
        # local repos=${#print_result[@]}
        local repos=`echo -e ${print_result[@]} | awk 'NR!=1{a+=1;} END {print a}'`
        local changed_files=`echo -e ${print_result[@]} | awk 'NR!=1{a+=$2;} END {print a}'`
        local insertions=`echo -e ${print_result[@]} | awk 'NR!=1{a+=$3;} END {print a}'`
        local deletions=`echo -e ${print_result[@]} | awk 'NR!=1{a+=$4;} END {print a}'`

        echo "Summary: ----------------------------"
        echo "Repos        : $repos"
        echo "Changed files: $changed_files"
        echo "Insertions   : $insertions"
        echo "Deletions    : $deletions"
    fi
}


if [[ -n "$recursive" ]]; then
    git_repos $cwd
else
    if [[ -d "$cwd/.git" ]]; then
        cloc $cwd
    else
        # TODO:
        # support sub directories of a git repo
        # (or any of the parent directories)
        echo "fatal: Not a git repository: .git"
        echo "Use '-r' option, if you wanna recursively search all git repos"
        exit 1
    fi
fi

summary

exit 0

