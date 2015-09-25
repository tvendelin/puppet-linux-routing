# puppet-linux-routing
Routing type and providers for Linux.
Defines 'main' Linux routing table for IPv4 routes to gateways.
The associated configuration files for a particular distribution
are handled by respective providers. 
Currently tested against:
 - Debian
 - Red Hat
 - CentOS
 - Fedora
 - SLES11

More to be added as necessary.

###Installation:

This repository contains two Puppet modules, ext and iproute_test:
```
├── modules
│   ├── ext
│   │   └── lib
│   │       └── puppet
│   │           ├── provider
│   │           │   └── iproutes
│   │           │       ├── iproutes.rb
│   │           │       ├── routing_conf_debian.rb
│   │           │       ├── routing_conf_redhat.rb
│   │           │       └── routing_conf_sles.rb
│   │           └── type
│   │               └── iproutes.rb
│   └── iproute_test
│       └── manifests
│           └── init.pp
└── README.md

```
Create an ordinary Puppet module for holding Puppet extensions, if you haven't done it already, and copy (or merge) the contents of modules/ext directory found in this repository into it.

The iproute_test module is provided for testing and as a usage example.

###Usage:
```
	 iproutes{'main':
	 	routes => {
			'10.1.28.0/24'  => { 'gateway' => '172.16.2.2', 'iface' => 'eth0' },
			'172.24.0.0/16' => { 'gateway' => '172.16.1.31', 'iface' => 'bond0' },
			'default'       => { 'gateway' => '172.16.2.2', 'iface' => 'eth0' },
		}
		safety_sleep              => 30     # Default is 0.
		stop_on_repeating_subnet  => false  # Default is true
	 }
```
Both 'default' and '0.0.0.0/0' can be used for default route. 
Internally, 'default' will be converted into '0.0.0.0/0'. 

Not suitable (intentionally) for setups using IP-forwarding.

###Provider Structure:

There is one principal provider - iproutes - that performs the unpersistent changes to the main routing table. It relies on ip utility and (currently) on netcat to test the TCP connection to puppet master after the routing has changed.

All other providers are responsible for writing the routing configuration to files (which is done depending on the Linux distro), and inherit from iproutes.

### Safety measures against misconfiguration (in addition to validation):

- All interfaces are checked to be active
- The routing is changed non-persistently first
- Once done, a TCP connection is attempted to puppet master (currently using netcat)
- Should the said connection fail, the network service is restarted, loading the last
persistent configuration, which was good enough to ssh to the host and run puppet agent.

Thus, if there was no manual intervention, the client's ability to
contact the master should persist (your ssh session might not,
though). If the ssh session is lost, the routing can be corrected
in the manifest and will be applied in the next run of puppet agent.

####Parameters
**name**
The resource title is always 'main' as only the main routing table is handled

**safety_sleep**
A time to wait (in seconds) before applying changes, allowing the user to hit ^C.

Hint: set this in a default declaration, like
```
Iproutes{
  safety_sleep => 20,
}
```
Defaults to "0". Converted into integer internally.

**stop_on_repeating_subnet**

What to do if multiple entries found for exactly the same 
subnet. WARNING: if that be the case, it is a strong 
indication of manual intervention. That means, it cannot be 
guaranteed, that after the double entries are removed, the 
client could still reach the puppet master in case of a 
configuration error. This is because the deleted routes might 
not have been persistently configured.

The default is "true"

Hint: set this in a default declaration, like
```
Iproutes{
  stop_on_repeating_subnet => false,
}
```
Defaults to "true"

#### Properties

**routes**

A Hash of Hashes that holds all routing configuration. See the usage example above.



