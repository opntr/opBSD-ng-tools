#!/bin/csh

git clone git@github.com:opntr/opBSD-ng.git opBSD-ng.git
if ( $? != 0 ) then
	git clone https://github.com/opntr/opBSD-ng.git opBSD-ng.git
endif

cd opBSD-ng.git

git remote add freebsd https://github.com/freebsd/freebsd.git
git config --add remote.freebsd.fetch '+refs/notes/*:refs/notes/*'
git fetch freebsd

# FreeBSD upstream repos
git branch --track freebsd/current/master freebsd/master
git branch --track freebsd/10-stable/master freebsd/stable/10
git branch --track freebsd/11-stable/master freebsd/stable/11

# opBSD-ng 10-STABLE master branches
git branch --track {,origin/}opbsd/10-stable/master

# opBSD-ng 11-STABLE master branches
git branch --track {,origin/}opbsd/11-stable/master

# opBSD-ng master branch
git branch --track {,origin/}opbsd/current/master
