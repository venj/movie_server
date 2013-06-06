Video server
============

Usage
-----

    $ cp server_conf.yml.skel server_conf.yml
    $ rackup -p4567 -E production config.ru

Deployment
----------

Before you run nginx:

    $ cd /webapps/movie_server
    $ mkdir tmp
    $ cp server_conf.yml.skel server_conf.yml
    $ edit server_conf.yml

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

Now run:

    # nginx
    # nginx -s reload # if nginx is running

**Restart the app**

Just like normal rack app running on passenger, `cd` to `/webapps/movie_server`, then run

    $ touch tmp/restart.txt