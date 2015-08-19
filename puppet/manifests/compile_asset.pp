## include puppet modules
include stdlib
include nodejs

## define $PATH for all execs, and packages
Exec {path => ['/usr/bin/', '/sbin/']}

## variables
$compilers       = ['uglifyjs', 'sass', 'imagemin']
$directory_src   = ['js', 'scss', 'img']
$directory_asset = ['js', 'css', 'img']
$packages_general = ['dos2unix', 'inotify-tools', 'ruby-devel']
$packages_npm     = ['uglify-js', 'imagemin', 'node-sass']

## packages: install general packages (apt, yum)
package {$packages_general:
    ensure => 'installed',
    before => Package[$packages_general_pip],
}

## packages: install general packages (npm)
package {$packages_npm:
    ensure => 'present',
    provider => 'npm',
    require => Package['npm'],
}

## create log directory
file {'/vagrant/log/':
    ensure => 'directory',
}

## create source directory
file {'/vagrant/sites/all/themes/custom/sample_theme/src/':
    ensure => 'directory',
}

## create asset directory
file {'/vagrant/sites/all/themes/custom/sample_theme/asset/':
    ensure => 'directory',
}

## dynamically create compilers
$compilers.each |Integer $index, String $compiler| {
    ## create asset directories
    file {"/vagrant/sites/all/themes/custom/sample_theme/src/${directory_asset[$index]}/":
        ensure => 'directory',
        before => File["/vagrant/sites/all/themes/custom/sample_theme/asset/${directory_asset[$index]}/"],
    }

    ## create asset directories
    file {"/vagrant/sites/all/themes/custom/sample_theme/asset/${directory_asset[$index]}/":
        ensure => 'directory',
        before => File["${compiler}-startup-script"],
    }

    ## create startup script (heredoc syntax)
    #
    #  @("EOT"), the use double quotes on the end tag, allows variable interpolation within the puppet heredoc.
    file {"${compiler}-startup-script":
        path    => "/etc/init/${compiler}.conf",
        ensure  => 'present',
        content => @("EOT"),
                   #!upstart
                   description 'start ${compiler}'

                   ## start job defined in this file after system services, and processes have already loaded
                   #       (to prevent conflict).
                   #
                   #  @vagrant-mounted, an event that executes after the shared folder is mounted
                   #  @[2345], represents all configuration states with general linux, and networking access
                   start on (vagrant-mounted and runlevel [2345])

                   ## stop upstart job
                   stop on runlevel [!2345]

                   ## restart upstart job continuously
                   respawn

                   # required for permission to write to '/vagrant/' files (pre-stop stanza)
                   setuid vagrant
                   setgid vagrant

                   ## run upstart job as a background process
                   expect fork

                   ## start upstart job
                   #
                   #  @chdir, change the current working directory
                   chdir /vagrant/puppet/scripts/
                   exec ./${compiler}

                   ## log start-up date
                   #
                   #  @[`date`], current date script executed
                   pre-start script
                       echo "[`date`] ${compiler} service watcher starting" >> /vagrant/log/${compiler}.log 
                   end script

                   ## log shut-down date, remove process id from log before '/vagrant' is unmounted
                   #
                   #  @[`date`], current date script executed
                   pre-stop script
                       echo "[`date`] ${compiler} watcher stopping" >> /vagrant/log/${compiler}.log
                   end script
                   | EOT
               notify  => Exec["dos2unix-upstart-${compiler}"],
        }

    ## dos2unix upstart: convert clrf (windows to linux) in case host machine is windows.
    #
    #  @notify, ensure the webserver service is started. This is similar to an exec statement, where the
    #      'refreshonly => true' would be implemented on the corresponding listening end point. But, the
    #      'service' end point does not require the 'refreshonly' attribute.
    exec {"dos2unix-upstart-${compiler}":
        command => "dos2unix /etc/init/${compiler}.conf",
        notify  => Exec["dos2unix-bash-${compiler}"],
    }

    ## dos2unix bash: convert clrf (windows to linux) in case host machine is windows.
    #
    #  @notify, ensure the webserver service is started. This is similar to an exec statement, where the
    #      'refreshonly => true' would be implemented on the corresponding listening end point. But, the
    #      'service' end point does not require the 'refreshonly' attribute.
    exec {"dos2unix-bash-${compiler}":
        command => "dos2unix /vagrant/puppet/scripts/${compiler}",
        notify  => Service["${compiler}"],
    }

    ## start ${compiler} service
    service {"${compiler}":
        ensure => 'running',
        enable => 'true',
        notify  => Exec["touch-${directory_src[$index]}-files"],
    }

    ## touch source: ensure initial build compiles every source file
    #
    #  @touch, changes the modification time to the current system time.
    #
    #  Note: the current inotifywait implementation watches close_write, move, and create. However, the source files
    #        will already exist before this 'inotifywait', since the '/vagrant' directory will already have been mounted
    #        on the initial build.
    exec {"touch-${directory_src[$index]}-files":
        command => "touch /vagrant/sites/all/themes/custom/sample_theme/src/${directory_src[$index]}/*",
        refreshonly => true,
    }
}