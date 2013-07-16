Video server
============

Note
----

Please do remember to update your `server_conf.yml` file according to `server_conf.yml.skel`.

Usage
-----

    cp server_conf.yml.skel server_conf.yml
    rackup -p4567 -E production config.ru

Deployment
----------

**nginx + passenger**

Before you run nginx:

    cd /webapps/movie_server
    mkdir tmp
    cp server_conf.yml.skel server_conf.yml
    edit server_conf.yml

_Change the /path/to/movie/files to real movie files path_

Nginx configuration -- **Only works for passenger 4.x.**

    server {
        listen       4567;  # <-- Change to the port you want
        server_name  server.local;  # <--  Change to your host name
        root /path/to/video/files;  # <--  Remember to point to your movie files folder
        rack_env production;
        passenger_enabled on;
        passenger_app_root /webapps/movie_server; # <-- This is where you place this code
        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   html;
        }
    }

Now run(as root):

    nginx
    nginx -s reload # if nginx is running

Just like normal rack app running on passenger, `cd` to `/webapps/movie_server`, then run

    touch tmp/restart.txt

**Thin**

If you using thin as your server, a new `thin.yml.skel` file is included in project code. 

    cp thin.yml.skel thin.yml
    edit thin.yml              # Change to your needs
    thin start -C thin.yml     # also accept restart/stop/start

You can also use this `thin.yml` with nginx to use load balance.

Or you can run thin as service on Linux (run as root):

    thin install               # on Linux
    cp thin.yml /etc/thin      # On Debian 6.x
    thin start --all           # Start all thin servers

Torrents feature
----------------

You may not use it. It is really personal. If you have my BitTorrent Sync secret for my torrents, you may want to use the torrents code. Or, you can ignore these junk code.

Please do remember to put the torrents folder inside your download folder. Because, actually torrents folder should be in public folder.

**Sort Torrent Date List**

Change `default_sort_order` settings in `server_conf.yml` to use default sort or not.
