#!/bin/bash
set -e

# Get the lando logger
. /helpers/log.sh

# Set generic config
NOW=$(date +"%Y%m%d-%H%M")

source /helpers/sync.env

# Load config file
if [ -z "$SYNC_CONFIG" ]; then
  SYNC_CONFIG=$(pwd)/.lando/sync.env
fi
if [ ! -z "$SYNC_SSH_USER" ] && [ ! -f "$SYNC_CONFIG" ]; then
  lando_red "Sync config $SYNC_CONFIG not found!"
  exit 1
fi

if [ -f "$SYNC_CONFIG" ]; then
source $SYNC_CONFIG
fi

pause() {
  read -p "Press [Enter] key to continue..." fackEnterKey
}

doValidateParams() {
  if [ -z "$SYNC_SSH_USER" ] || [ -z "$SYNC_SERVER" ]; then
    lando_red "Missing param: ssh user '$SYNC_SSH_USER' and server '$SYNC_SERVER'"
    exit
  fi

  if [ "$SYNC_DO_MIGRATION" == "true" ] && [ -z "$SYNC_PROJECT_PATH" ]; then
    lando_red "Missing param: project path $SYNC_PROJECT_PATH"
    exit
  fi
}

doSyncRemote2Local() {
  doValidateParams
  if [ "$SYNC_DO_DB_SYNC" == "true" ]; then
    lando_yellow "Dumping database to $SYNC_DB_SOURCE_DUMP_FILE"
    eval "ssh -C $SYNC_SSH_USER@$SYNC_SERVER \"mysqldump --compress $SYNC_DB_SOURCE_CRED $SYNC_DB_DUMP_PARAMS | gzip -9 -c\" > $SYNC_DB_SOURCE_DUMP_FILE"

    lando_yellow "Dumping database to $SYNC_DB_TARGET_DUMP_FILE"
    eval "mysqldump --compress $SYNC_DB_TARGET_CRED $SYNC_DB_DUMP_PARAMS | gzip -9 -c > $SYNC_DB_TARGET_DUMP_FILE"

    lando_pink "Importing database"
    eval "gunzip -c < $SYNC_DB_SOURCE_DUMP_FILE | mysql $SYNC_DB_TARGET_CRED"
  fi

  if [ "$SYNC_DO_FILES_SYNC" == "true" ]; then
    for i in "${!SYNC_FILES_SOURCE_PATHS[@]}"; do
      if [ "$SYNC_REMOTE_HAS_RSYNC" == "true" ]; then
        lando_pink "Rsync ${SYNC_FILES_SOURCE_PATHS[i]} to ${SYNC_FILES_TARGET_PATHS[i]}"
        eval "rsync -a --info=progress2 --delete --rsync-path=\"$SYNC_REMOTE_USE_SUDO rsync\" -e ssh $SYNC_SSH_USER@$SYNC_SERVER:${SYNC_FILES_SOURCE_PATHS[i]} ${SYNC_FILES_TARGET_PATHS[i]}"
      else
        lando_pink "Remove ${SYNC_FILES_TARGET_PATHS[i]}"
        eval "rm -rf ${SYNC_FILES_TARGET_PATHS[i]}"
        lando_pink "Scp ${SYNC_FILES_SOURCE_PATHS[i]} to ${SYNC_FILES_TARGET_PATHS[i]}"
        eval "scp -rCq $SYNC_SSH_USER@$SYNC_SERVER:${SYNC_FILES_SOURCE_PATHS[i]} ${SYNC_FILES_TARGET_PATHS[i]}"
      fi
    done
  fi

  if [ ! -z "$SYNC_MIGRATION_CMD" ] && [ "$SYNC_DO_MIGRATION" == "true" ]; then
    lando_pink "Run migration in $SYNC_PROJECT_PATH"
    eval "${SYNC_PHP_BINARY} ${SYNC_PROJECT_PATH}${SYNC_MIGRATION_CMD}"
  fi

  lando_green "Utinni!"

  exit 0
}

doSyncRemote2Remote() {
  doValidateParams
  if [ "$SYNC_DO_DB_SYNC" == "true" ]; then
    lando_yellow "Dumping database to $SYNC_DB_SOURCE_DUMP_FILE"
    eval "ssh -C $SYNC_SSH_USER@$SYNC_SERVER \"mysqldump --compress $SYNC_DB_SOURCE_CRED $SYNC_DB_DUMP_PARAMS | gzip -9 -c\" > $SYNC_DB_SOURCE_DUMP_FILE"

    lando_yellow "Dumping database to $SYNC_DB_TARGET_DUMP_FILE"
    eval "ssh -C $SYNC_SSH_USER@$SYNC_SERVER \"mysqldump --compress $SYNC_DB_TARGET_CRED $SYNC_DB_DUMP_PARAMS | gzip -9 -c\" > $SYNC_DB_TARGET_DUMP_FILE"

    lando_pink "Importing database"
    eval "scp $SYNC_DB_SOURCE_DUMP_FILE $SYNC_SSH_USER@$SYNC_SERVER:~/"
    eval "ssh $SYNC_SSH_USER@$SYNC_SERVER \"gunzip -c < $SYNC_DB_SOURCE_DUMP_FILE | mysql $SYNC_DB_TARGET_CRED\""
    eval "ssh $SYNC_SSH_USER@$SYNC_SERVER \"rm $SYNC_DB_SOURCE_DUMP_FILE\""
  fi

  if [ "$SYNC_DO_FILES_SYNC" == "true" ]; then
    for i in "${!SYNC_FILES_SOURCE_PATHS[@]}"; do
      if [ "$SYNC_REMOTE_HAS_RSYNC" == "true" ]; then
        lando_pink "Rsync ${SYNC_FILES_SOURCE_PATHS[i]} to ${SYNC_FILES_TARGET_PATHS[i]}"
        eval "ssh $SYNC_SSH_USER@$SYNC_SERVER '$SYNC_REMOTE_USE_SUDO rsync -aL --info=progress2 --delete ${SYNC_FILES_SOURCE_PATHS[i]} ${SYNC_FILES_TARGET_PATHS[i]}'"
      else
        lando_pink "Remove ${SYNC_FILES_TARGET_PATHS[i]}"
        eval "ssh $SYNC_SSH_USER@$SYNC_SERVER '$SYNC_REMOTE_USE_SUDO rm -rf ${SYNC_FILES_TARGET_PATHS[i]}'"
        lando_pink "Copy ${SYNC_FILES_SOURCE_PATHS[i]} to ${SYNC_FILES_TARGET_PATHS[i]}"
        eval "ssh $SYNC_SSH_USER@$SYNC_SERVER '$SYNC_REMOTE_USE_SUDO cp -r ${SYNC_FILES_SOURCE_PATHS[i]} ${SYNC_FILES_TARGET_PATHS[i]}'"
      fi
    done
  fi

  if [ ! -z "$SYNC_MIGRATION_CMD" ] && [ "$SYNC_DO_MIGRATION" == "true" ]; then
    lando_pink "Run migration in $SYNC_PROJECT_PATH"
    eval "ssh $SYNC_SSH_USER@$SYNC_SERVER '$SYNC_REMOTE_USE_SUDO ${SYNC_PHP_BINARY} ${SYNC_PROJECT_PATH}${SYNC_MIGRATION_CMD}'"
  fi

  lando_green "Utinni!"

  exit 0
}

doSyncLocal2Remote() {
  doValidateParams
  if [ "$SYNC_DO_DB_SYNC" == "true" ]; then
    lando_yellow "Dumping database to $SYNC_DB_SOURCE_DUMP_FILE"
    eval "mysqldump --compress $SYNC_DB_SOURCE_CRED $SYNC_DB_DUMP_PARAMS | gzip -9 -c > $SYNC_DB_SOURCE_DUMP_FILE"

    lando_yellow "Dumping database to $SYNC_DB_TARGET_DUMP_FILE"
    eval "ssh -C $SYNC_SSH_USER@$SYNC_SERVER \"mysqldump --compress $SYNC_DB_TARGET_CRED $SYNC_DB_DUMP_PARAMS | gzip -9 -c\" > $SYNC_DB_TARGET_DUMP_FILE"

    lando_pink "Importing database"
    eval "scp $SYNC_DB_SOURCE_DUMP_FILE $SYNC_SSH_USER@$SYNC_SERVER:~/"
    eval "ssh $SYNC_SSH_USER@$SYNC_SERVER \"gunzip -c < $SYNC_DB_SOURCE_DUMP_FILE | mysql $SYNC_DB_TARGET_CRED\""
    eval "ssh $SYNC_SSH_USER@$SYNC_SERVER \"rm $SYNC_DB_SOURCE_DUMP_FILE\""
  fi

  if [ "$SYNC_DO_FILES_SYNC" == "true" ]; then
    for i in "${!SYNC_FILES_SOURCE_PATHS[@]}"; do
      if [ "$SYNC_REMOTE_HAS_RSYNC" == "true" ]; then
        lando_pink "Rsync ${SYNC_FILES_SOURCE_PATHS[i]} to ${SYNC_FILES_TARGET_PATHS[i]}"
        eval "rsync --chown=$SYNC_REMOTE_FILES_RSYNC_CHOWN --chmod=$SYNC_REMOTE_FILES_RSYNC_CHMOD -a --info=progress2 --delete --rsync-path=\"$SYNC_REMOTE_USE_SUDO rsync\" -e ssh ${SYNC_FILES_SOURCE_PATHS[i]} $SYNC_SSH_USER@$SYNC_SERVER:${SYNC_FILES_TARGET_PATHS[i]}"
      else
        lando_pink "Remove ${SYNC_FILES_TARGET_PATHS[i]}"
        eval "ssh $SYNC_SSH_USER@$SYNC_SERVER '$SYNC_REMOTE_USE_SUDO rm -rf ${SYNC_FILES_TARGET_PATHS[i]}'"
        lando_pink "Scp ${SYNC_FILES_SOURCE_PATHS[i]} to ${SYNC_FILES_TARGET_PATHS[i]}"
        eval "scp -rCq ${SYNC_FILES_SOURCE_PATHS[i]} $SYNC_SSH_USER@$SYNC_SERVER:${SYNC_FILES_TARGET_PATHS[i]}"
      fi
    done
  fi

  if [ ! -z "$SYNC_MIGRATION_CMD" ] && [ "$SYNC_DO_MIGRATION" == "true" ]; then
    lando_pink "Run migration in $SYNC_PROJECT_PATH"
    eval "ssh $SYNC_SSH_USER@$SYNC_SERVER '$SYNC_REMOTE_USE_SUDO ${SYNC_PHP_BINARY} ${SYNC_PROJECT_PATH}${SYNC_MIGRATION_CMD}'"
  fi

  lando_green "Utinni!"

  exit 0
}

prod2local() {
  SYNC_DB_SOURCE_CRED="-h $SYNC_PROD_DB_HOST -P $SYNC_PROD_DB_PORT -u $SYNC_PROD_DB_USER -p'$SYNC_PROD_DB_PASS' $SYNC_PROD_DB_NAME"
  SYNC_DB_TARGET_CRED="-h $SYNC_LOCAL_DB_HOST -P $SYNC_LOCAL_DB_PORT -u $SYNC_LOCAL_DB_USER -p'$SYNC_LOCAL_DB_PASS' $SYNC_LOCAL_DB_NAME"
  SYNC_DB_SOURCE_DUMP_FILE="db-prod-$NOW-$SYNC_PROD_DB_NAME.sql.gz"
  SYNC_DB_TARGET_DUMP_FILE="db-local-$NOW-$SYNC_LOCAL_DB_NAME.sql.gz"
  SYNC_FILES_SOURCE_PATHS=("${SYNC_PROD_FILES_PATHS[@]}")
  SYNC_FILES_TARGET_PATHS=("${SYNC_LOCAL_FILES_PATHS[@]}")
  SYNC_PHP_BINARY="$SYNC_LOCAL_PHP_BINARY"
  SYNC_PROJECT_PATH="$SYNC_LOCAL_PROJECT_PATH"
  doSyncRemote2Local
}

stage2local() {
  SYNC_DB_SOURCE_CRED="-h $SYNC_STAGE_DB_HOST -P $SYNC_STAGE_DB_PORT -u $SYNC_STAGE_DB_USER -p'$SYNC_STAGE_DB_PASS' $SYNC_STAGE_DB_NAME"
  SYNC_DB_TARGET_CRED="-h $SYNC_LOCAL_DB_HOST -P $SYNC_LOCAL_DB_PORT -u $SYNC_LOCAL_DB_USER -p'$SYNC_LOCAL_DB_PASS' $SYNC_LOCAL_DB_NAME"
  SYNC_DB_SOURCE_DUMP_FILE="db-stage-$NOW-$SYNC_STAGE_DB_NAME.sql.gz"
  SYNC_DB_TARGET_DUMP_FILE="db-local-$NOW-$SYNC_LOCAL_DB_NAME.sql.gz"
  SYNC_FILES_SOURCE_PATHS=("${SYNC_STAGE_FILES_PATHS[@]}")
  SYNC_FILES_TARGET_PATHS=("${SYNC_LOCAL_FILES_PATHS[@]}")
  SYNC_PHP_BINARY="$SYNC_LOCAL_PHP_BINARY"
  SYNC_PROJECT_PATH="$SYNC_LOCAL_PROJECT_PATH"
  doSyncRemote2Local
}

dev2local() {
  SYNC_DB_SOURCE_CRED="-h $SYNC_DEV_DB_HOST -P $SYNC_DEV_DB_PORT -u $SYNC_DEV_DB_USER -p'$SYNC_DEV_DB_PASS' $SYNC_DEV_DB_NAME"
  SYNC_DB_TARGET_CRED="-h $SYNC_LOCAL_DB_HOST -P $SYNC_LOCAL_DB_PORT -u $SYNC_LOCAL_DB_USER -p'$SYNC_LOCAL_DB_PASS' $SYNC_LOCAL_DB_NAME"
  SYNC_DB_SOURCE_DUMP_FILE="db-dev-$NOW-$SYNC_DEV_DB_NAME.sql.gz"
  SYNC_DB_TARGET_DUMP_FILE="db-local-$NOW-$SYNC_LOCAL_DB_NAME.sql.gz"
  SYNC_FILES_SOURCE_PATHS=("${SYNC_DEV_FILES_PATHS[@]}")
  SYNC_FILES_TARGET_PATHS=("${SYNC_LOCAL_FILES_PATHS[@]}")
  SYNC_PHP_BINARY="$SYNC_LOCAL_PHP_BINARY"
  SYNC_PROJECT_PATH="$SYNC_LOCAL_PROJECT_PATH"
  doSyncRemote2Local
}

prod2dev() {
  SYNC_DB_SOURCE_CRED="-h $SYNC_PROD_DB_HOST -P $SYNC_PROD_DB_PORT -u $SYNC_PROD_DB_USER -p'$SYNC_PROD_DB_PASS' $SYNC_PROD_DB_NAME"
  SYNC_DB_TARGET_CRED="-h $SYNC_DEV_DB_HOST -P $SYNC_DEV_DB_PORT -u $SYNC_DEV_DB_USER -p'$SYNC_DEV_DB_PASS' $SYNC_DEV_DB_NAME"
  SYNC_DB_SOURCE_DUMP_FILE="db-prod-$NOW-$SYNC_PROD_DB_NAME.sql.gz"
  SYNC_DB_TARGET_DUMP_FILE="db-dev-$NOW-$SYNC_DEV_DB_NAME.sql.gz"
  SYNC_FILES_SOURCE_PATHS=("${SYNC_PROD_FILES_PATHS[@]}")
  SYNC_FILES_TARGET_PATHS=("${SYNC_DEV_FILES_PATHS[@]}")
  SYNC_PHP_BINARY="$SYNC_REMOTE_PHP_BINARY"
  SYNC_PROJECT_PATH="$SYNC_DEV_PROJECT_PATH"
  doSyncRemote2Remote
}

prod2stage() {
  SYNC_DB_SOURCE_CRED="-h $SYNC_PROD_DB_HOST -P $SYNC_PROD_DB_PORT -u $SYNC_PROD_DB_USER -p'$SYNC_PROD_DB_PASS' $SYNC_PROD_DB_NAME"
  SYNC_DB_TARGET_CRED="-h $SYNC_STAGE_DB_HOST -P $SYNC_STAGE_DB_PORT -u $SYNC_STAGE_DB_USER -p'$SYNC_STAGE_DB_PASS' $SYNC_STAGE_DB_NAME"
  SYNC_DB_SOURCE_DUMP_FILE="db-prod-$NOW-$SYNC_PROD_DB_NAME.sql.gz"
  SYNC_DB_TARGET_DUMP_FILE="db-stage-$NOW-$SYNC_STAGE_DB_NAME.sql.gz"
  SYNC_FILES_SOURCE_PATHS=("${SYNC_PROD_FILES_PATHS[@]}")
  SYNC_FILES_TARGET_PATHS=("${SYNC_STAGE_FILES_PATHS[@]}")
  SYNC_PHP_BINARY="$SYNC_REMOTE_PHP_BINARY"
  SYNC_PROJECT_PATH="$SYNC_STAGE_PROJECT_PATH"
  doSyncRemote2Remote
}

stage2dev() {
  SYNC_DB_SOURCE_CRED="-h $SYNC_STAGE_DB_HOST -P $SYNC_STAGE_DB_PORT -u $SYNC_STAGE_DB_USER -p'$SYNC_STAGE_DB_PASS' $SYNC_STAGE_DB_NAME"
  SYNC_DB_TARGET_CRED="-h $SYNC_DEV_DB_HOST -P $SYNC_DEV_DB_PORT -u $SYNC_DEV_DB_USER -p'$SYNC_DEV_DB_PASS' $SYNC_DEV_DB_NAME"
  SYNC_DB_SOURCE_DUMP_FILE="db-stage-$NOW-$SYNC_STAGE_DB_NAME.sql.gz"
  SYNC_DB_TARGET_DUMP_FILE="db-dev-$NOW-$SYNC_DEV_DB_NAME.sql.gz"
  SYNC_FILES_SOURCE_PATHS=("${SYNC_STAGE_FILES_PATHS[@]}")
  SYNC_FILES_TARGET_PATHS=("${SYNC_DEV_FILES_PATHS[@]}")
  SYNC_PHP_BINARY="$SYNC_REMOTE_PHP_BINARY"
  SYNC_PROJECT_PATH="$SYNC_DEV_PROJECT_PATH"
  doSyncRemote2Remote
}

dev2stage() {
  SYNC_DB_SOURCE_CRED="-h $SYNC_DEV_DB_HOST -P $SYNC_DEV_DB_PORT -u $SYNC_DEV_DB_USER -p'$SYNC_DEV_DB_PASS' $SYNC_DEV_DB_NAME"
  SYNC_DB_TARGET_CRED="-h $SYNC_STAGE_DB_HOST -P $SYNC_STAGE_DB_PORT -u $SYNC_STAGE_DB_USER -p'$SYNC_STAGE_DB_PASS' $SYNC_STAGE_DB_NAME"
  SYNC_DB_SOURCE_DUMP_FILE="db-dev-$NOW-$SYNC_DEV_DB_NAME.sql.gz"
  SYNC_DB_TARGET_DUMP_FILE="db-stage-$NOW-$SYNC_STAGE_DB_NAME.sql.gz"
  SYNC_FILES_SOURCE_PATHS=("${SYNC_DEV_FILES_PATHS[@]}")
  SYNC_FILES_TARGET_PATHS=("${SYNC_STAGE_FILES_PATHS[@]}")
  SYNC_PHP_BINARY="$SYNC_REMOTE_PHP_BINARY"
  SYNC_PROJECT_PATH="$SYNC_STAGE_PROJECT_PATH"
  doSyncRemote2Remote
}

local2dev() {
  SYNC_DB_SOURCE_CRED="-h $SYNC_LOCAL_DB_HOST -P $SYNC_LOCAL_DB_PORT -u$SYNC_LOCAL_DB_USER -p'$SYNC_LOCAL_DB_PASS' $SYNC_LOCAL_DB_NAME"
  SYNC_DB_TARGET_CRED="-h $SYNC_DEV_DB_HOST -P $SYNC_DEV_DB_PORT -u $SYNC_DEV_DB_USER -p'$SYNC_DEV_DB_PASS' $SYNC_DEV_DB_NAME"
  SYNC_DB_SOURCE_DUMP_FILE="db-local-$NOW-$SYNC_LOCAL_DB_NAME.sql.gz"
  SYNC_DB_TARGET_DUMP_FILE="db-dev-$NOW-$SYNC_DEV_DB_NAME.sql.gz"
  SYNC_FILES_SOURCE_PATHS=("${SYNC_LOCAL_FILES_PATHS[@]}")
  SYNC_FILES_TARGET_PATHS=("${SYNC_DEV_FILES_PATHS[@]}")
  SYNC_PHP_BINARY="$SYNC_REMOTE_PHP_BINARY"
  SYNC_PROJECT_PATH="$SYNC_DEV_PROJECT_PATH"
  doSyncLocal2Remote
}

# function to display menus
show_menus() {
  clear
  echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  lando_green "   SYNC-OPTIONS "
  echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  echo " 1. PROD  >  LOCAL -p2l"
  echo " 2. STAGE >  LOCAL -s2l"
  echo " 3. DEV   >  LOCAL -d2l"
  echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  lando_yellow " 4. PROD  > DEV"
  lando_yellow " 5. PROD  > STAGE"
  echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  lando_yellow " 6. STAGE > DEV"
  lando_yellow " 7. DEV > STAGE"
  echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  lando_yellow " 8. LOCAL > DEV"
  echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  echo " 9. Exit"
  echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  lando_green "Options:"
  echo "--no-db         Skip the database sync"
  echo "--no-files      Skip the files sync"
  echo "--no-migration  Skip the migration"
  echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
}

read_options() {
  local choice
  read -p "Enter choice [ 1 - 8 ] " choice
  case $choice in
  1) prod2local ;;
  2) stage2local ;;
  3) dev2local ;;
  4) prod2dev ;;
  5) prod2stage ;;
  6) stage2dev ;;
  7) dev2stage ;;
  8) local2dev ;;
  9) exit 0 ;;
  *) lando_red -e "Only Numbers please..." && sleep 1 ;;
  esac
}

trap exit SIGINT SIGQUIT SIGTSTP

while (("$#")); do
  case "$1" in
  -p2l | --prod2local)
    SYNC_CMD=prod2local
    shift
    ;;
  -s2l | --stage2local)
    SYNC_CMD=stage2local
    shift
    ;;
  -d2l | --dev2local)
    SYNC_CMD=dev2local
    shift
    ;;
  --no-db)
    SYNC_DO_DB_SYNC=false
    shift
    ;;
  --no-files)
    SYNC_DO_FILES_SYNC=false
    shift
    ;;
  --no-migration)
    SYNC_DO_MIGRATION=false
    shift
    ;;
  *)
    shift
    ;;
  esac
done

case "$SYNC_CMD" in
prod2local)
  prod2local
  ;;
stage2local)
  stage2local
  ;;
dev2local)
  dev2local
  ;;
esac

while true; do
  show_menus
  read_options
done
