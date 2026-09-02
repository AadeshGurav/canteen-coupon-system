# Included from inside a server{} block in canteen.conf and (once TLS is set
# up) canteen-tls.conf — kept in one place so the two never drift apart.
# Not matched by nginx.conf's `include conf.d/*.conf`, since a bare location{}
# block isn't valid directly inside the http{} context.

# nginx's own liveness check — doesn't touch the app, so it stays cheap and
# doesn't count against the app's rate limits.
location = /healthz {
    access_log off;
    return 200 "ok\n";
    add_header Content-Type text/plain;
}

# The counter scanner hits this every single scan, all meal period —
# tighter limit, small burst for a shaky phone connection retrying.
location = /scan {
    limit_req zone=scan burst=10 nodelay;
    proxy_pass http://canteen_app;
    include /etc/nginx/proxy_params.conf;
}

location / {
    limit_req zone=general burst=40 nodelay;
    proxy_pass http://canteen_app;
    include /etc/nginx/proxy_params.conf;
}
