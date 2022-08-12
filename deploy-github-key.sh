#!/bin/bash -e

# It should be the root path of github repo directory.
workdir=/home/{{SERVER_NAME}}

# parameters related to github
github_token_file=/root/.github_access_token
github_owner=telecelplay-infra
github_host=github

# ssh key & config file path
SSH_DIR=/root/.ssh
keyfile=$SSH_DIR/github-id_rsa
configfile=$SSH_DIR/config

# get hostname
hostname=`hostname`

if [ ! -d "$workdir" ]; then
  echo "ERROR : $workdir not found."
  exit 1
fi
cd "$workdir"

# check if current folder is a git repository.
is_gitrepo=$(git rev-parse --is-inside-work-tree 2>/dev/null)
if [ $? -eq 0 ] && [ "$is_gitrepo" = "true" ]; then
  git_url="$(git config --get remote.origin.url)"
  reponame_dot_git="$(basename $git_url)"
  reponame=${reponame_dot_git%.*}

  git remote set-url origin $github_host:$github_owner/$reponame_dot_git

  echo
  echo "+ generate a key: $keyfile"
  if [ ! -f "$keyfile" ]; then
    echo -e 'y\n' | ssh-keygen -t rsa \
      -f $keyfile \
      -C $reponame_dot_git\
      -N ''\
      -q 1>/dev/null
  else
    echo "Key file already exists."
  fi

  echo
  echo "+ configure a key: $configfile"
  if [ -e "$configfile" ] && grep -q "Host $github_host" "$configfile"; then
    echo "Key already configured in this server."
  else
    cat << EOF >> $configfile
Host $github_host
  HostName github.com
  User git
  IdentitiesOnly yes
  IdentityFile $keyfile
EOF
  fi

  # github_access_token file should exist
  if [ -f "$github_token_file" ]; then
    github_access_token=$(cat $github_token_file)
  else
    echo
    echo "ERROR : $github_token_file not found."
    exit 1
  fi

  api_url=https://api.github.com/repos/$github_owner/$reponame/keys

  # delete all existing deploy keys
  delete_all_existing_keys=false
  if [ "$delete_all_existing_keys" = true ]; then
    echo
    curl \
      -H "Authorization: token $github_access_token" \
      -H "Accept: application/vnd.github.v3+json" \
      $api_url 2>/dev/null \
      | jq '.[] | .id ' | \
      while read _id; do
        echo "- delete key: $_id"
        curl \
          -X "DELETE" \
          -H "Authorization: token $github_access_token" \
          -H "Accept: application/vnd.github.v3+json" \
          $api_url/$_id 2>/dev/null
      done
  fi

  # add the keyfile to github
  echo
  echo "+ deploy a key:"
  echo -n ">> "
  status_code=$(curl --write-out "%{http_code}\n" --silent --output /dev/null \
    -X POST \
    -H "Authorization: token $github_access_token" \
    -H "Accept: application/vnd.github.v3+json" \
    $api_url \
    --data @- << EOF
    {
      "title" : "$hostname $keyfile.pub",
      "key" : "$(cat $keyfile.pub)",
      "read_only" : true
    }
EOF
  )
  if [ "$status_code" -eq "201" ] ; then
    echo "successfully deployed."
  elif [ "$status_code" -eq "422" ] ; then
    echo "key already deployed."
  else
    echo "ERROR : Failed to deploy a key. HTTP response is $status_code"
    exit 1
  fi

  # remove the github_access_token file
  rm -f $github_token_file

  echo
  echo "local key:"
  ssh-keygen -lf $keyfile

  echo
  echo "config:"
  cat $configfile
else
  echo "This folder is not a git repository."
fi