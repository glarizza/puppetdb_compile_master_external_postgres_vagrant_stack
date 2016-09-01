# Testing external postgres with PuppetDB on compile masters

## TL;DR: Starting the stack (order matters)

```
vagrant up pe-mom;
vagrant up external-postgres;
vagrant provision pe-mom --provision-with hosts;
vagrant ssh pe-mom -c "sudo su - -c 'puppet enterprise configure; puppet agent -t;'"
vagrant provision pe-mom
vagrant ssh external-postgres -c "sudo su - -c 'puppet agent -t;'"
vagrant up compile-master-puppetdb
vagrant ssh pe-mom -c "sudo su - -c 'puppet agent -t;'"
```

## Nodes within the stack

This Vagrant stack will stand up three machines with the following roles:

* PE Master of Masters node (pe-mom) with...
  * Puppet Enterprise Console
  * PostgreSQL with the Console database
  * Certificate Authority
  * Puppetserver (master role)
  * PuppetDB instance pointing back to the external PostgreSQL database
* External PostgreSQL node (external-postgres) with...
  * The PuppetDB Database
* Compilation Master node (compile-master-puppetdb) with...
  * Puppetserver (master role)
  * PuppetDB instance pointing back to the external PostgreSQL database

## Detailed instructions for starting the stack

* `vagrant up pe-mom`
  * This will bring up the Master of Masters (MOM) **BUT INSTALLATION WILL
  FAIL** this is expected because the external postgres database isn't up yet.
  When the MOM fails, though, it still has Puppetserver running with the CA
  role, which is what we need to get the external postgres node registered with
  Puppet and configured
* `vagrant up external-postgres`
  * This brings up the external postgres node, and everything should succeed as
    expected
* `vagrant provision pe-mom --provision-with hosts`
  * Because the external postgres node came up AFTER the MOM, the MOM doesn't
    have a host entry for it. This command ensures the MOM can contact the
    external postgres node
* `vagrant ssh pe-mom -c "sudo su - -c 'puppet enterprise configure; puppet
  agent -t;'"`
  * This step completes the setup of the MOM and runs Puppet to ensure
    everything is completely setup
* `vagrant provision pe-mom`
  * This step runs through all the provisioners, but specifically we're looking
    for the provisioner that configures the necessary Console node groups that
    are necessary for the external postgres node and the compilation master (it
    never ran because it's ordered AFTER the PE installation provisioner, and
    that provisioner failed during the first run)
* `vagrant ssh external-postgres -c "sudo su - -c 'puppet agent -t;'"`
  * The previous step setup the classification necessary for the external
    postgres node, and now a puppet run will complete the configuration
    (specifically setting up rules in pg_ident.conf for both the MOM and
    compile master)
* `vagrant up compile-master-puppetdb`
  * Bring up the compilation master
  * NOTE: The puppet run AFTER this step takes a couple of minutes. We need to
    wait for the node to export all the whitelist resources necessary so that
    the MOM will trust the node as a compilation master and a PuppetDB node
* `vagrant ssh pe-mom -c "sudo su - -c 'puppet agent -t;'"`
  * This run allows the MOM to pick up the exported resources from the
    compilation master and ensures that the compilation master is on the
    whitelist for the Console and PuppetDB

At this point the entire stack should be up and functional.  You can test the
stack in the following section.


## Testing the stack

A full and complete test of all components would be to do a puppet agent run
with a new certname so Puppet would see the new certname as a new 'node.' Do
that with the following command:

```
vagrant ssh compile-master-puppetdb -c "sudo /opt/puppetlabs/bin/puppet agent -t --server compile-master-puppetdb --certname test"

```

After that completes, sign the cert on the MOM with the following command:

```
vagrant ssh pe-mom -c "sudo /opt/puppetlabs/bin/puppet cert sign --all"

```

Finally, run puppet again. If the run completes successfully, then all
components are up and functioning properly:

```
vagrant ssh compile-master-puppetdb -c "sudo /opt/puppetlabs/bin/puppet agent -t --server compile-master-puppetdb --certname test"

```

## PuppetDB Status

PuppetDB has a status endpoint that will provide you with the current state of
PuppetDB (including whether the database backend is up). Execute the following
curl directly from a machine that has PuppetDB installed to see the output.
Here's what the status endpoint returns if the external postgres database is
down (i.e. right after you bring up pe-mom for the first time):

```
[vagrant@pe-mom ~]$ curl -k -X GET -H "Accept: application/json" http://localhost:8080/status/v1/services/puppetdb-status | python -m json.tool

{
    "detail_level": "info",
    "service_name": "puppetdb-status",
    "service_status_version": 1,
    "service_version": "4.1.4",
    "state": "starting",
    "status": {
        "maintenance_mode?": true,
        "queue_depth": null,
        "rbac_status": "error",
        "read_db_up?": false,
        "write_db_up?": false
    }
}
```


## Inspecting the PostgreSQL databases directly

To see the status of the PostgreSQL database directly from the `psql` binary,
you can execute the following three commands (as displayed below):

1. `su - pe-postgres -s /bin/bash -c /opt/puppetlabs/server/bin/psql`
2. `\c pe-puppetdb`
3. `SELECT * from certnames;`

```
[root@external-postgres vagrant]# su - pe-postgres -s /bin/bash -c /opt/puppetlabs/server/bin/psql
psql (9.4.7)
Type "help" for help.

pe-postgres=# \c pe-puppetdb
You are now connected to database "pe-puppetdb" as user "pe-postgres".
pe-puppetdb=# SELECT * from certnames;
 id |        certname         | latest_report_id | deactivated | expired
----+-------------------------+------------------+-------------+---------
  2 | external-postgres       |                5 |             |
  3 | compile-master-puppetdb |                8 |             |
  1 | pe-mom                  |               10 |             |
(3 rows)

```

You can see from the output that we have three entries in that database, and
that data is getting populated from PuppetDB.


## Necessary steps to get this working OUTSIDE of Vagrant

Obviously this stack is meant to be spun up by Vagrant, but if you need to set
this up on existing infrastructure, below is some of the "magic" that was done in the
background by the various provisioners.

**NOTE: This was tested on Puppet Enterprise 2016.2.0 and I expect will
continue to work during the 2016.2.x series. Because this work is dependent on
the state of the `puppet_enterprise` module, I would expect the class
parameters and Hiera data to be different across major releases. You've been
warned!**

### Console node groups for classification

Due to the way the `puppet_enterprise` module works in 2016.2.x, there is some
data that needs to be set within the Puppet Enterprise Console as well as
within `pe.conf` initially and Hiera. The puppet code within
`puppet_code/create_compile_master_pdb_node_group.pp` in this repo models the
node groups that need be created inside the console (including all class
parameters). Broken down, however, there are the node groups that need to be
created or modified:

* PE Compile Master with PuppetDB
  * This group is created SPECIFICALLY for new/additional compilation masters
    that will also contain PuppetDB instances (and specifically NOT the MOM)
  * The following three profiles are added without modification
    * `puppet_enterprise::profile::master::mcollective`
    * `puppet_enterprise::profile::mcollective::peadmin`
    * `puppet_enterprise::profile::puppetdb`
  * The `puppet_enterprise::profile::master` class is added, however
    `puppetdb_host` and `puppetdb_port` are specified because these two
    parameters are what control the order in which puppet attempts to send data
    to PuppetDB
    * Right now it's just `${fqdn}` so every compilation master uses ITSELF as
      the only PuppetDB host, but you can optionally specify an array with both the
      compilation master (first) and the MOM so that puppet will failover to
      the MOM if the compilation master PuppetDB instance is down
    * This COULD cause issues if a large number of CMs fail and puppet starts
      failing over PuppetDB requests to the MOM node all at once, so that's
      something to monitor
* PE Master Override
  * TODO: I have no idea why this override exists - I see it as doing nothing
* PE External Postgres
  * This group is created for the external postgres node and for the purpose of
    continuous management/enforcement
  * The only class necessary is `puppet_enterprise::profile::database` (without
    modification)
* PE Infrastructure
  * This group already exists in the console and contains the declaration of
    the `puppet_enterprise` class with key parameters that most of the other
    node groups rely upon
  * Because parameters are specified explicitly in this group, Hiera cannot be
    used for any of these parameters (i.e. it's a resource-style declaration of
    the class, and thus these values trump everything else)
  * The only parameter that need be modified in this node group is
    `puppetdb_host`
    * Currently (as of 2016.2.x), the value of `puppetdb_host` is set by
      the `pe_install::puppetdb_certname` parameter, which is currently
      restricted to be a single string value
    * Problems arise because the value of `$puppet_enterprise::puppetdb_host`
      is used to create rules in `pg_ident.conf` on the external postgres node
      for the purpose of allowing PuppetDB instances to write to the
      `pe-puppetdb` database
    * The value of `$puppet_enterprise::puppetdb_host` needs to include ALL
      nodes that contain a PuppetDB instance, and so this value needs to be
      modified to explicitly list all PuppetDB nodes (i.e. `['pe-mom', 'compile-master-puppetdb']`)

### What about Hiera?

I've left all the Hiera entries commented out in `config/hierafiles/defaults.yaml`
for posterity, but the crux of the matter is that most of the data needed for this
stack relies on parameters in the PE Infrastructure's declaration of
`puppet_enterprise`. The way the `puppet_enterprise` module is laid out in 2016.2.x,
there are certain parameters that are explicitly set by that group and thus
Hiera wouldn't be effective. I expect this to change in the next major PE
release (and beyond), but this is the way it is right now


# Puppet Debugging Kit
_The only good bug is a dead bug._

This project provides a batteries-included Vagrant environment for debugging Puppet powered infrastructures.

# Tuning PuppetDB and Puppet Server Together

## Disable gc-interval on PuppetDB

Only one PuppetDB should ever perform GC on the database so each compile master should disable [gc-interval](https://docs.puppet.com/puppetdb/latest/configure.html#gc-interval).

## CPUs = puppet server jrubies + puppetdb command processing threads + 1

In order to prevent a situation in which a thundering herd of traffic would cause puppet server and puppetdb to compete for resources you want to make sure jrubies + command processing threads < # CPUs.

I recommend setting PuppetDB command processing threads to 1 to start with and see if that allows for adequate throughput.  You can monitor the QueueSize in PuppetDB with the [pe_metric_curl_cron_jobs](https://github.com/npwalker/pe_metric_curl_cron_jobs) to make sure you're not seeing a backup of commands.  If you do see a backup then add a command processing thread and reduce by one jruby.

## Set max_connections in PostgreSQL to 1000

Each PuppetDB uses 50 connections to PostgreSQL by default.  So, you need to increase max_connections to allow for all of those connections.

If you are adding more than 4 puppetdb nodes then you might want to consider tuning down the connection pools to reduce the connection overhead on the postgresql side.  There are parameters for read and write connection pool sizes in the puppet_enterprise module.

My understanding is that you need a read connection for each jruby instance and you need roughly 2x command processing threads for write connections.  This assumes the console will use the PuppetDB instance on the MoM for it's read queries.

## Setup

Getting the debugging kit ready for use consists of three steps:

  - Ensure the proper Vagrant plugins are installed.

  - Create VM definitions in `config/vms.yaml`.

  - Clone Puppet Open Source projects to `src/puppetlabs` (optional).

Rake tasks and templates are provided to help with all three steps.

### Install Vagrant Plugins

Two methods are avaible depending on whether a global Vagrant installation, such as provided by the official packages from [vagrantup.com](http://vagrantup.com), is in use:

  - `rake setup:global`:
    This Rake task will add all plugins required by the debugging kit to a global Vagrant installation.

  - `rake setup:sandboxed`:
    This Rake task will use Bundler to create a completely sandboxed Vagrant installation that includes the plugins required by the debugging kit.
    The contents of the sandbox can be customized by creating a `Gemfile.local` that specifies additional gems and Bundler environment parameters.

### Create VM Definitions

Debugging Kit virtual machine definitions are stored in the file `config/vms.yaml` and an example is provided as `config/vms.yaml.example`.
The example can simply be copied to `config/vms.yaml` but it contains a large number of VM definitions which adds some notable lag to Vagrant start-up times.
Start-up lag can be remedied by pruning unwanted definitions after copying the example file.

### Clone Puppet Open Source Projects

The `poss-envpuppet` role is designed to run Puppet in guest machines directly from Git clones located on the host machine at `src/puppetlabs/`.
This role is useful for inspecting and debugging changes in behavior between versions without re-installing packages.
The required Git clones can be created by running the following Rake task:

    rake setup:poss


## Usage

Use of the debugging kit consists of:

  - Creating a new VM definition in `config/vms.yaml`.
    The `box` component determines which Vagrant basebox will be used.
    The default baseboxes can be found in [`data/puppet_debugging_kit/boxes.yaml`](https://github.com/puppetlabs/puppet-debugging-kit/blob/internal/data/puppet_debugging_kit/boxes.yaml).

  - Assigning a list of "roles" that customize the VM behavior.
    The role list can be viewed as a stack in which the last entry is applied first.
    Most VMs start with the `base` role which auto-assigns an IP address and sets up network connectivity.
    The default roles can be found in [`data/puppet_debugging_kit/roles.yaml`](https://github.com/puppetlabs/puppet-debugging-kit/blob/internal/data/puppet_debugging_kit/roles.yaml) and are explained in more detail below.


### PE Specific Roles

There are three roles that assist with creating PE machines:

  - `pe-forward-console`:
    This role sets up a port forward for console accesss from 443 on the guest VM to 4443 on the host machine.
    If some other running VM is already forwarding to 4443 on the host, Vagrant will choose a random port number that will be displayed in the log output when the VM starts up.

  - `pe-<version>-master`:
    This role performs an all-in-one master installation of PE `<version>` on the guest VM.
    When specifying the version number, remove any separators such that `3.2.1` becomes `321`.
    The PE console is configured with username `admin@puppetlabs.com` and password `puppetlabs`.

  - `pe-<version>-agent`:
    This role performs an agent installation of PE `<version>` on the guest VM.
    The agent is configured to contact a master running at `pe-<version>-master.puppetdebug.vlan` --- so ensure a VM with that hostname is configured and running before bringing up any agents.


### POSS Specific Roles

There are a few roles that assist with creating VMs that run Puppet Open Source Software (POSS).

  - `poss-apt-repos`:
    This role configures access to the official repositories at apt.puppetlabs.com for Debian and Ubuntu VMs.

  - `poss-yum-repos`:
    This role configures access to the official repositories at yum.puppetlabs.com for CentOS and Fedora VMs.


## Extending and Contributing

The debugging kit can be thought of as a library of configuration and data for [Oscar](https://github.com/adrienthebo/oscar).
Data is loaded from two sets of YAML files:

```
config
└── *.yaml         # <-- User-specific customizations
data
└── puppet_debugging_kit
    └── *.yaml     # <-- The debugging kit library
```

Everything under `data/puppet_debugging_kit` is loaded first.
In order to avoid merge conflicts when the library is updated, these files should never be edited unless you plan to submit your changes as a pull request.

The contents of `config/*.yaml` are loaded next and can be used to extend or override anything provided by `data/puppet_debugging_kit`.
These files are not tracked by Git and are where user-specific customizations should go.

---
<p align="center">
  <img src="http://i.imgur.com/TFTT0Jh.png" />
</p>
