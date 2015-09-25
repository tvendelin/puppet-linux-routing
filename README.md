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
