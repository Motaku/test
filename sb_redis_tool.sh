#!/bin/bash

redis_cli="/home/ukai/redis-3.0.2/src/redis-cli"
command=$1
app_id=$2
from=$3
to=$4

# get key
template_keys="${redis_cli} -h HOST keys KEY"
template_keys_from="${template_keys/HOST/$from}"
template_keys_to="${template_keys/HOST/$to}"
# get value
template_zrange_md5="${redis_cli} -h HOST zrange KEY 0 -1 | md5sum"
template_zrange_md5_from="${template_zrange_md5/HOST/$from}"
template_zrange_md5_to="${template_zrange_md5/HOST/$to}"
template_get_md5="${redis_cli} -h HOST get KEY | md5sum"
template_get_md5_from="${template_get_md5/HOST/$from}"
template_get_md5_to="${template_get_md5/HOST/$to}"
# dump & restore
template_dump_restore="${redis_cli} -h ${from} --raw dump KEY | head -c-1 | ${redis_cli} -h ${to} -x restore KEY 0"
# dump to file
template_dump_file="${redis_cli} -h ${from} --raw dump KEY | head -c-1 > ${to}/dump/${from}/DATETIME/KEY"
# delete
template_del="${redis_cli} -h ${from} del KEY"

users_key="users-${app_id}"

function copy {
  ## COPY
  
  # users-***はコピー先に無いよね?
  cmd=`echo ${template_keys_to/KEY/$users_key}`
  echo $cmd
  result=`eval $cmd`
  if [ "$result" = '' ]; then
    echo copy: $users_key
  else
    echo already exists: $users_key
    exit 1
  fi
  
  # users-***をdumpします
  cmd=`echo ${template_dump_restore//KEY/$users_key}`
  echo $cmd
  eval $cmd
  
  # その他のキーリストを取得
  keys=(`echo "keys *_${app_id}_*" | ${redis_cli} -h ${from} | sort`)
  
  for key in ${keys[@]}; do
    # コピー先に無いよね?
    cmd=`echo ${template_keys_to/KEY/${key}}`
    echo $cmd
    result=`eval $cmd`
    if [ "$result" = '' ]; then
      echo copy: key
    else
      echo already exists: $key
      exit 1
    fi
  
    # その他のキーを全部dumpします
    cmd=`echo ${template_dump_restore//KEY/${key}}`
    echo $cmd
    eval $cmd
  done;
  
  echo copy completed
}

function diff {
  ## DIFF
  
  cmd=`echo ${template_keys_from//KEY/$users_key}`
  #echo $cmd
  key=`eval $cmd`
  if [ "$key" = "" ]; then
    echo key does not exist \(from\): $users_key
    exit 1
  fi
  cmd=`echo ${template_zrange_md5_from//KEY/$users_key}`
  #echo $cmd
  md5_from=`eval $cmd`
  
  cmd=`echo ${template_keys_to//KEY/$users_key}`
  #echo $cmd
  key=`eval $cmd`
  if [ "$key" = "" ]; then
    echo key does not exist \(to\): $users_key
    exit 1
  fi
  cmd=`echo ${template_zrange_md5_to//KEY/$users_key}`
  #echo $cmd
  md5_to=`eval $cmd`
  
  if [ "${md5_from}" = "${md5_to}" ]; then
    echo match: $users_key from: $md5_from to: $md5_to
  else
    echo unmatch: $users_key
    echo from: $md5_from
    echo to: $md5_to
    exit 1
  fi
  
  # その他のキーリストを取得
  keys=(`echo "keys *_${app_id}_*" | ${redis_cli} -h ${from} | sort`)
  
  for key in ${keys[@]}; do
    # fromのgetのmd5
    cmd=`echo ${template_get_md5_from/KEY/$key}`
    md5_from=`eval $cmd`

    # toにキーがあるよね?
    cmd=`echo ${template_keys_to//KEY/$key}`
    #echo $cmd
    key_to=`eval $cmd`
    if [ "$key_to" = "" ]; then
      echo key does not exist \(to\): $key
      exit 1
    fi
    
    # toのgetのmd5
    cmd=`echo ${template_get_md5_to/KEY/$key}`
    md5_to=`eval $cmd`
  
    if [ "${md5_from}" = "${md5_to}" ]; then
      echo match: $key from: $md5_from to: $md5_to
    else
      echo unmatch: $key
      echo from: $md5_from
      echo to: $md5_to
      exit 1
    fi
  done;
  echo all keys are matched
}

function del {
  ## DELETE
  echo DELETE app_id: $app_id FROM $from
  echo -n "Are you ready? (yes/no) "
  read OK
  if [ $OK != "yes" ]; then
    echo stopped
    exit 1
  fi
  
  dt=`date +"%Y%m%d_%k%M%S"`
  
  mkdir -p "$to/dump/${from}/$dt"
  
  # 削除前にdumpする
  cmd=${template_dump_file/DATETIME/$dt}
  cmd=${cmd//KEY/$users_key}
  echo $cmd
  eval $cmd
  
  # 削除する
  cmd=${template_del/KEY/$users_key}
  echo $cmd
  eval $cmd
  
  # その他のキーリストを取得
  keys=(`echo "keys *_${app_id}_*" | ${redis_cli} -h ${from} | sort`)
  
  for key in ${keys[@]}; do
    # 削除前にdumpする(その他全て)
    cmd=${template_dump_file/DATETIME/$dt}
    cmd=${cmd//KEY/$key}
    echo $cmd
    eval $cmd
  
    # 削除する(その他全て)
    cmd=${template_del/KEY/$key}
    echo $cmd
    eval $cmd
  done;
  
  echo all keys are deleted
}

if [ $command = 'copy' ]; then
  copy
elif [ $command = 'diff' ]; then
  diff
elif [ $command = 'del' ]; then
  del
else
  echo err
  exit 1
fi
exit
