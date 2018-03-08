#!/bin/sh
#
# Copyright (c) 2017-2018 Oliver Pinter <oliver.pinter@hardenedbsd.org>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

for i in $*
do
	_skip="YES"
	_commit_message=$(mktemp)
	note=$(git notes show ${i} 2>/dev/null)
	if [ $? -eq 0 ]
	then
		svn_commit=$(echo ${note} | sed -n -e 's/.*revision=\(.*\)$/r\1/gp')
		svn_ref=$(echo ${note} | sed -n -e 's/.*path=\(.*\);.*revision=\(.*\)$/svn-commit-id: \1 r\2/gp')
		format_string="format:opBSD MFC ${svn_commit}: %s%n%n%b%nAuthor: %an <%ae>%nOriginal-commit-date: %ad%n${svn_ref}"
	else
		format_string="format:opBSD MFC: %s%n%n%b%nAuthor: %an <%ae>%nOriginal-commit-date: %aD"
	fi

	git cherry-pick -x ${i}
	case $? in
		0)
			_skip="no"
			;;
		1)
			# Ignore empty commits
			git reset
			_skip="YES"
			;;
		*)
			# Merge conflict or other error
			echo "Dropping into recovery shell."
			echo "Fix the issue, and press ^D to continue."
			env PS1="git cherry-pick error> " sh
			echo
			read -p "do you want to skip the current patch (YES/no): " _skip
			;;
	esac

	if [ "${_skip}" = "no" ]
	then
		git show -s --format="${format_string}" ${HEAD} > ${_commit_message}
		git commit --amend -F ${_commit_message} --reset-author -s

		read -p "Press ENTER to continue." __dummy
		git show
	else
		echo "skipped ${i} commit ..."
	fi

	unlink ${_commit_message}
done
