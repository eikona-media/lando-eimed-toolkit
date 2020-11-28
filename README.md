# EIKONA Media Lando Toolkit Plugin

This is a plugin for https://github.com/lando/lando.

## Toolings

### Sync database and files

Clone the repository to your plugins directory:
```
git clone git@github.com:eikona-media/lando-eimed-toolkit.git ~/.lando/plugins/lando-eimed-toolkit
```

Copy the configuration [sync.env](scripts/sync.env) to your project:
```
cp ~/.lando/plugins/lando-eimed-toolkit/scripts/sync.env [project_dir]/.lando/sync.env
```
Remove all active default variables which you don't want to overwrite.
**Uncomment all inactive variables and configure them to use the sync!**

Add the tooling to your `.lando.yml`:
```yaml
tooling:
    sync:
        service: appserver
        description: Sync database and files between remote and local
        cmd: /helpers/sync.sh
        user: root
```

Now you should be able to call `lando sync` in your project!
