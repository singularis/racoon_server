#!/bin/bash
sudo snap install openstack
sunbeam prepare-node-script | bash -x && newgrp snap_daemon
sunbeam cluster bootstrap --accept-defaults
sunbeam configure --accept-defaults --openrc demo-openrc
sunbeam openrc > ~/admin-openrc
sunbeam dashboard-url
