#!/bin/csh

set DATE=`date "+%Y%m%d%H%M%S"`

# set reply-to to robot in mail command
setenv REPLYTO "robot@hardenedbsd.org"

set TOOLS_DIR=`dirname ${0}`
set BRANCHES=`cat ${TOOLS_DIR}/opBSD-ng_branches.txt`

set SOURCE_DIR="/usr/data/source/git/opBSD"
set SOURCE="${SOURCE_DIR}/opBSD-ng.git"
set LOGS="${SOURCE_DIR}/log/opBSD-ng"
set LOCK="${SOURCE_DIR}/opBSD-ng_repo-lock"
set TEE_CMD="tee -a"
set DST_MAIL="op@hardenedbsd.org"
set ENABLE_MAIL="YES"

test -d $LOGS || mkdir -p $LOGS

if ( -e ${LOCK} ) then
	echo "update error at ${DATE} - lock exists"
	if ( ${ENABLE_MAIL} == "YES" ) then
		echo "update error at ${DATE} - lock exists" | mail -s "hbsd - lock error" ${DST_MAIL}
	endif
	exit 1
endif

touch ${LOCK}

cd ${SOURCE}

set OHEAD=`git branch | awk '/\*/{print $2}'`

git stash

(git fetch --progress origin) |& ${TEE_CMD} ${LOGS}/freebsd-fetch-${DATE}.log
(git fetch --progress freebsd) |& ${TEE_CMD} ${LOGS}/freebsd-fetch-${DATE}.log
# pushing the freshly fetched FreeBSD commit notes to hardenedbsd repo
# these contains the svn revision ids
(git push --atomic --progress origin refs/notes/commits) |& ${TEE_CMD} ${LOGS}/freebsd-fetch-${DATE}.log

foreach line ( ${BRANCHES} )
	set err=0
	set _mail_subject_prefix=""

	set rebase=`echo ${line} | cut -d ':' -f 1 | tr -d '#'`
	switch ( ${rebase} )
	case "MERGE":
		set rebase=0
		set action_string="merge"
		breaksw
	case "REBASE":
		set rebase=1
		set action_string="rebase"
		breaksw
	default:
		set _mail_subject_prefix="[PARSE]"
		set err=1
		goto out
		breaksw
	endsw

	set remote_branches=`echo ${line} | cut -d ':' -f 3 | tr '+' ' '`
	set branch=`echo ${line} | cut -d ':' -f 2`
	set _branch=`echo ${branch} | tr '/' '%'`

	echo "==== BEGIN: ${branch} ====" |& ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log

	echo "current branch: ${branch}" |& ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
	echo "${action_string}able branch: ${remote_branches}" |& ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log

	# Skip lines beginning with '#'
	echo ${line} | grep -Eq '^#.*'
	if ( $? == 0 ) then
		set _mail_subject_prefix="[SKIP]"
		echo "==== SKIP: ${line} ====" |& ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
		goto handle_err
	endif

	echo "==== change branch ====" |& ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
	# change branch
	(git checkout ${branch}) |& ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log

	echo "==== show current branch ====" |& ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
	# show, that branch correctly switched
	(git branch) |& ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log

	echo "==== drop stale changes ====" |& ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
	# drop any stale change
	(git reset --hard HEAD) |& ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log

	echo "==== update to latest origin ====" |& ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
	# pull in latest changes from main repo
	if ( ${rebase} == 1 ) then
		(git pull --progress --ff-only) |& ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
		set ret=$?
	else
		(git pull --progress) |& ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
		set ret=$?
	endif
	if ( ${ret} != 0 ) then
		echo "ERROR: git pull failed, try to recover" |& \
			${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
		( git merge --abort ) |& ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
		( git reset --hard ) |& ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
	endif

	echo "==== ${action_string} branches ====" |& ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
	foreach _remote_branch ( ${remote_branches} )
		if ( ${rebase} != 0 ) then
			# rebase ontop of specific branch
			echo "==== rebase ${_remote_branch} branch ====" |& \
			       	${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
			(git rebase ${_remote_branch}) |& \
				${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
			if ( $? != 0 ) then
				set err=1
				set _mail_subject_prefix="[MERGE]"
				# show what's wrong
				echo "==== rebase failed to ${_remote_branch} branch ====" |& \
					${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
				(git diff) |& head -500 | ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
				(git status) |& ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
				(git rebase --abort) |& ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
				(git reset --hard) |& ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
				(git clean -fd) |& ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
			endif
		else
			# merge specific branches to current branch
			echo "==== merge ${_remote_branch} branch ====" |& \
			       	${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
			(git merge --log ${branch} ${_remote_branch}) |& \
				${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
			if ( $? != 0 ) then
				set err=1
				set _mail_subject_prefix="[MERGE]"
				# show what's wrong
				echo "==== merge failed at ${_remote_branch} branch ====" |& \
					${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
				(git diff) |& head -500 | ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
				(git status) |& ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
				(git merge --abort) |& ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
				(git reset --hard) |& ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
				(git clean -fd) |& ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
			endif
		endif
	end

	if ( ${err} != 0 ) then
		goto handle_err
	endif

	if ( ${rebase} != 0 ) then
		# force update remote
		(git push --progress --force-with-lease --atomic origin ${branch}) |& \
			${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
		set ret=$?
		if ( ${ret} == 0 ) then
			# create a tag
			(git tag ${_branch}-${DATE}) |& \
				${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
			(git push --progress --tags) |& \
				${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
		endif
	else
		# update remote
		(git push --progress --atomic origin ${branch}) |& \
			${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
		set ret=$?
	endif
	if ( ${ret} != 0 ) then
		set _mail_subject_prefix="[PUSH]"
		set err=1
		goto handle_err
	endif

handle_err:
	if ( ${err} != 0 ) then
		set _mail_subject_prefix="[FAILED]${_mail_subject_prefix}"
		# create a clean state, if failed something
		if ( ${rebase} == 1 ) then
			echo "==== rebase failed and clean up after ====" |& \
				${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
			(git status) |& ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
			(git rebase --abort) |& ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
		else
			echo "==== merge failed and clean up after ====" |& \
				${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
			(git status) |& ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
			(git merge --abort) |& ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
		endif
		(git reset --hard) |& ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
		(git clean -fd) |& ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
	else
		set _mail_subject_prefix="[OK]"
	endif

	echo "==== END: ${branch} ====" |& ${TEE_CMD} ${LOGS}/${_branch}-${DATE}.log
	if ( ${ENABLE_MAIL} == "YES" ) then
		cat ${LOGS}/${_branch}-${DATE}.log | \
		    mail -s "${_mail_subject_prefix} ${_branch}-${DATE}.log" ${DST_MAIL}
	endif
	echo
end

git checkout ${OHEAD}
git stash pop

unlink ${LOCK}
