#  example-vagrant

vagrant starter kit 

## Requirements
    Virtualbox                  => https://www.virtualbox.org
    Vagrant                     => http://www.vagrantup.com
    vagrant-hostmanager         => vagrant plugin install vagrant-hostmanager
    vagrant-cachier  (optional) => vagrant plugin install vagrant-cachier
    vagrant-triggers (optional) => vagrant plugin install vagrant-triggers
    
## Preparation
    git submodule update --init
    
## Setup
    vagrant up

## Puppet Development

### Hiera

the puppet master deploys a fairly default hiera.yaml

    [vagrant@puppetmaster ~]$ cat /etc/puppet/hiera.yaml 
    ---
    # Managed by puppet
    :backends:
      - yaml
    :hierarchy:
      - "node/%{::hostname}"
      - "environment/%{::environment}"
      - "common"
    :yaml:
      :datadir: "/var/lib/hiera"

### Manifests

Place your own manifests in this directory. A fairly standard default.pp is already present which also creates and registers
a local yum repository called 'localhost'

### Modules

Place your own modules in this directory. 5 modules are alreayd present one of which is stdlib.

