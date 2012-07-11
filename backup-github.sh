#!/bin/bash 
# A simple script to backup an organization's GitHub repositories.
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
#
# WHAT IT DOES
#
# This script uses the GitHub API and Git itself to:
#
# 1) Fetch a list of all repositories assocaited with a user or org.
#
# 2) Create a complete backup (mirror) each of those repositories.
#
# 3) Create a complete backup (mirror) each of wiki associated with 
#    those repositories.
#
# 4) Create a backup of the GitHub issue database associated with 
#    those repositorie
#
# SETUP
# 
# You'll need a GitHub account with read (pull) access to these
# repositories.
#
#   I. Generate an SSH key:
#
#        ssh-keygen -t rsa -f ~/.ssh/id_rsa.ghbu
#
#  II. Add it to your GitHub account at: 
#
#        <https://github.com/settings/ssh>
#
# III. Add the following to ~/.ssh/config
#
#        Host ghbu.github.com
#          HostName github.com
#          PreferredAuthentications publickey
#          IdentityFile ~/.ssh/id_rsa.ghbu
#
#  IV. "Log in" with ssh-add:
#
#        ssh-add ~/.ssh/id_rsa.ghbu
#
#   V. Configure the script (change GHBU_ORG, *_UNAME, *_PASSWD and *_GITHOST).
#
#  VI. Run it:
#
#        ./backup-github.sh
#
#-------------------------------------------------------------------------------

GHBU_BACKUP_DIR=${GHBU_BACKUP_DIR-"github-backups"}                  # where to place the backup files
GHBU_ORG=${GHBU_ORG-"<CHANGE-ME>"}                                   # the GitHub organization whose repos will be backed up
GHBU_UNAME=${GHBU_UNAME-"<CHANGE-ME>"}                               # the username of a GitHub account (to use with the GitHub API)
GHBU_PASSWD=${GHBU_PASSWD-"<CHANGE-ME>"}                             # the password for that account 
GHBU_GITHOST=${GHBU_GITHOST-"<CHANGE-ME>.github.com"}                # the GitHub hostname (see notes)
GHBU_PRUNE_OLD=${GHBU_PRUNE_OLD-true}                                # when `true`, old backups will be deleted
GHBU_PRUNE_AFTER_N_DAYS=${GHBU_PRUNE_AFTER_N_DAYS-3}                 # the min age (in days) of backup files to delete
GHBU_SILENT=${GHBU_SILENT-false}                                     # when `true`, only show error messages 
GHBU_API=${GHBU_API-"https://api.github.com"}                        # base URI for the GitHub API
GHBU_GIT_CLONE_CMD="git clone --quiet --mirror git@${GHBU_GITHOST}:" # base command to use to clone GitHub repos

TSTAMP=`date "+%Y%m%d-%H%M"`

# The function `check` will exit the script if the given command fails.
function check {
  "$@"
  status=$?
  if [ $status -ne 0 ]; then
    echo "ERROR: Encountered error (${status}) while running the following:" >&2
    echo "           $@"  >&2
    echo "       (at line ${BASH_LINENO[0]} of file $0.)"  >&2
    echo "       Aborting." >&2
    exit $status
  fi
}

# The function `tgz` will create a gzipped tar archive of the specified file ($1) and then remove the original
function tgz {
   check tar zcf $1.tar.gz $1 && check rm -rf $1
}

$GHBU_SILENT || (echo "" && echo "=== INITIALIZING ===" && echo "")

$GHBU_SILENT || echo "Using backup directory $GHBU_BACKUP_DIR"
check mkdir -p $GHBU_BACKUP_DIR

$GHBU_SILENT || echo -n "Fetching list of repositories for ${GHBU_ORG}..."
REPOLIST=`check curl --silent -u $GHBU_UNAME:$GHBU_PASSWD ${GHBU_API}/orgs/${GHBU_ORG}/repos -q | check grep "\"name\"" | check awk -F': "' '{print $2}' | check sed -e 's/",//g'`
$GHBU_SILENT || echo "found `echo $REPOLIST | wc -w` repositories."


$GHBU_SILENT || (echo "" && echo "=== BACKING UP ===" && echo "")

for REPO in $REPOLIST; do
   $GHBU_SILENT || echo "Backing up ${GHBU_ORG}/${REPO}"
   check ${GHBU_GIT_CLONE_CMD}${GHBU_ORG}/${REPO}.git ${GHBU_BACKUP_DIR}/${GHBU_ORG}-${REPO}-${TSTAMP}.git && tgz ${GHBU_BACKUP_DIR}/${GHBU_ORG}-${REPO}-${TSTAMP}.git

   $GHBU_SILENT || echo "Backing up ${GHBU_ORG}/${REPO}.wiki (if any)"
   ${GHBU_GIT_CLONE_CMD}${GHBU_ORG}/${REPO}.wiki.git ${GHBU_BACKUP_DIR}/${GHBU_ORG}-${REPO}.wiki-${TSTAMP}.git 2>/dev/null && tgz ${GHBU_BACKUP_DIR}/${GHBU_ORG}-${REPO}.wiki-${TSTAMP}.git

   $GHBU_SILENT || echo "Backing up ${GHBU_ORG}/${REPO} issues"
   check curl --silent -u $GHBU_UNAME:$GHBU_PASSWD ${GHBU_API}/repos/${GHBU_ORG}/${REPO}/issues -q > ${GHBU_BACKUP_DIR}/${GHBU_ORG}-${REPO}.issues-${TSTAMP} && tgz ${GHBU_BACKUP_DIR}/${GHBU_ORG}-${REPO}.issues-${TSTAMP}
done

if $GHBU_PRUNE_OLD; then
  $GHBU_SILENT || (echo "" && echo "=== PRUNING ===" && echo "")
  $GHBU_SILENT || echo "Pruning backup files ${GHBU_PRUNE_AFTER_N_DAYS} days old or older."
  $GHBU_SILENT || echo "Found `find $GHBU_BACKUP_DIR -name '*.tar.gz' -mtime +$GHBU_PRUNE_AFTER_N_DAYS | wc -l` files to prune."
  find $GHBU_BACKUP_DIR -name '*.tar.gz' -mtime +$GHBU_PRUNE_AFTER_N_DAYS -exec rm -fv {} > /dev/null \; 
fi

$GHBU_SILENT || (echo "" && echo "=== DONE ===" && echo "")
$GHBU_SILENT || (echo "GitHub backup completed." && echo "")
