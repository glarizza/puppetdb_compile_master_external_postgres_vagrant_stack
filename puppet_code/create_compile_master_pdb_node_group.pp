  pe_node_group { 'PE Compile Master w/ PuppetDB':
    #parent  => 'PE Infrastructure',
    parent  => 'All Nodes',
    pinned  => ['compile-master-puppetdb'],
    classes => {
      'puppet_enterprise::profile::master' => { 'puppetdb_host' => '${fqdn}', 'puppetdb_port' => '8081' },
      'puppet_enterprise::profile::master::mcollective' => {},
      'puppet_enterprise::profile::mcollective::peadmin' => {},
      'puppet_enterprise::profile::puppetdb' => {},
    }
  }

  pe_node_group { 'PE Master Override' :
    #parent  => 'PE Master',
    parent  => 'All Nodes',
    pinned  => ['pe-mom'],
    classes => {
      'puppet_enterprise::profile::master' => { 'puppetdb_host' => ['pe-mom', 'compile-master-puppetdb'] },
    }
  }

  pe_node_group { 'PE Postgres':
    ensure             => 'present',
    classes            => {'puppet_enterprise::profile::database' => {'max_connections' => 200}},
    parent             => 'All Nodes',
    pinned             => ['external-postgres'],
  }
