  pe_node_group { 'PE Compile Master w/ PuppetDB':
    parent  => 'PE Infrastructure',
    pinned  => ['compile-master-puppetdb'],
    classes => {
      'puppet_enterprise::profile::master' => { 'puppetdb_host' => '${fqdn}', 'puppetdb_port' => '8081' },
      'puppet_enterprise::profile::master::mcollective' => {},
      'puppet_enterprise::profile::mcollective::peadmin' => {},
      'puppet_enterprise::profile::puppetdb' => {},
    }
  }

  pe_node_group { 'PE Master Override' :
    parent  => 'PE Master',
    pinned  => ['pe-mom'],
    classes => {
      'puppet_enterprise::profile::master' => { 'puppetdb_host' => ['pe-mom', 'compile-master-puppetdb'] },
    }
  }


