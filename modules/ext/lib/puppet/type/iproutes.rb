Puppet::Type.newtype(:iproutes) do
	ensurable

	desc "Defines 'main' Linux routing table for IPv4 routes to gateways.
	The associated configuration files for a particular distribution
	are handled by respective providers. 
  Currently supported distribution are:
	 - Debian
	 - Red Hat
	 - CentOS
	 - Fedora

	 More to be added as necessary.

	 Example usage:

	 iproutes{'main':
	 	routes => {
			'10.1.28.0/24'  => { 'gateway' => '172.16.2.2', 'iface' => 'eth0' },
			'172.24.0.0/16' => { 'gateway' => '172.16.1.31', 'iface' => 'bond0' },
			'default'       => { 'gateway' => '172.16.2.2', 'iface' => 'eth0' },
		}
	 }

	 Not suitable (intentionally) for setups using IP-forwarding.

	 Safety measures against misconfiguration (in addition to validation):

	 - All interfaces are checked to be active
	 - The routing is changed non-persistently first
	 - Once done, a TCP connection is attempted to puppet master (currently using netcat)
	 - Should the said connection fail, the network service is restarted, loading the last
	 persistent configuration, which was good enough to ssh to the host and run puppet agent.

	 Thus, if there was no manual intervention, the client's ability to
	 contact the master should persist (your ssh session might not,
	 though). If the ssh session is lost, the routing can be corrected
	 in the manifest and will be applied in the next run of puppet agent.

	"

	newparam(:name, :namevar=> true) do
		desc 'A name that is always "main".
		'

		validate do |value|
			unless value == 'main'
				raise ArgumentError, "%s is invalid (should be \"main\"" % value
			end
		end

	end

	newparam(:safety_sleep) do
		desc 'A time to wait (in seconds) before applying changes,
		allowing the user to hit ^C.

		Hint: set this in a default declaration, like

		    Iproutes{
		      safety_sleep => 20,
		    }

		Defaults to "0". Converted into integer internally.
		'

    validate do |value|
			value =~/^\d+$/ or
				raise ArgumentError, "Expecting an integer, got >%s<" % value
		end

		munge do |value|
		  value.to_i
		end

		defaultto '0'
	end

	newparam(:stop_on_repeating_subnet) do
    desc 'What to do if multiple entries found for exactly the same 
    subnet. WARNING: if that be the case, it is a strong 
    indication of manual intervention. That means, it cannot be 
    guaranteed, that after the double entries are removed, the 
    client could still reach the puppet master in case of a 
    configuration error. This is because the deleted routes might 
    not have been persistently configured.

		The default is "true"

		Hint: set this in a default declaration, like

		Iproutes{
		  stop_on_repeating_subnet => false,
		    }

    Defaults to "true"
		'

    validate do |value|
			value == true or value == false or
				raise ArgumentError, "Expecting an integer, got >%s<" % value
		end

    defaultto true
	end

	newproperty(:routes) do
		desc "A Hash of Hashes that holds all routing configuration.
		Example:

		routes => {
			'10.1.28.0/24'  => { 'gateway' => '172.16.2.2', 'iface' => 'eth0' },
			'172.24.0.0/16' => { 'gateway' => '172.16.1.31', 'iface' => 'bond0' },
			'default'       => { 'gateway' => '172.16.2.2', 'iface' => 'eth0' },
		}

    Both 'default' and '0.0.0.0/0' can be used for default route. 
    Internally, 'default' will be converted into '0.0.0.0/0'. 
    
    Each route must contain the name of respective interface. This 
    restriction is intended to ensure that whoever defines/changes 
    the routing configuration, knows exactly what (s)he is doing. 
    IP-forwarding won't work, of course.
		"

		# To avoid the default uglified log output.
		# Safe, because newvalue is validated as Hash.
		def should_to_s(newvalue)
    		newvalue
  		end

  		def change_to_s(currentvalue, newvalue)
  			'checking...'
  		end

		validate do |r|
			unless r.class.name == 'Hash'
				raise ArgumentError, '"routes" must be a Hash'
			end

			if r.key?('default') and r.key?('0.0.0.0/0')
				if r['0.0.0.0/0'] != r['default']
					raise ArgumentError, "Both '0.0.0.0/0' and 'default' non-identical routes defined."
				end
				Puppet.warning "'0.0.0.0/0' and 'default' are the same routes, double-definition makes no sense."
			end

			r.each do |dest,route|
				Puppet.debug "Validating interface >%s<" % route['iface']
				route['iface'] =~ /^\w([\:\w]*\w)?$/ or
					raise ArgumentError, "Malformed interface name >%s<" % route['iface']

				Puppet.debug "Validating gateway >%s<" % route['gateway']

				if ! route['gateway'] =~ /^\d{1,3}(?:\.\d{1,3}){3}$/
					raise ArgumentError, "Expecting an IP address in dotted-decimal notation, got >%s<" % route['gateway']
				end

				gw_b = dot2b(route['gateway']) # to binary

				if(( gw_b =~/^111/ ) or ( route['gateway'] =~/^0+?\./ ))
					raise ArgumentError, "The gateway >%s< is out of unicast range" % route['gateway']
				end

				if route['gateway'] =~/^169\.254/
					raise ArgumentError, "The gateway >%s< is a link-local address" % route['gateway']
				end

				if route['gateway'] =~/^127\./
					raise ArgumentError, "The gateway >%s< is a localhost address" % route['gateway']
				end

				next if(( dest == 'default' ) or ( dest == '0.0.0.0/0' ))

				Puppet.debug "Validating destination subnet >%s<" % dest
				if dest =~ /^(\d{1,3}(?:\.\d{1,3}){3})\/(\d\d?)$/
					Puppet.debug "Subnet: #{$1} mask: #{$2}"
					( subnet, mask ) = $1, $2.to_i

					if mask <= 0 or mask > 32
						raise ArgumentError, "Invalid mask length for >%s<" % dest
					end
				else
					raise ArgumentError, "Expecting IP subnet in CIDR notation, got >%s<" % dest
				end

				subnet_b = dot2b(subnet) # to binary

				subnet_b[mask..31] =~/^0+$/ or mask == 32 or
					raise ArgumentError, "Not a valid subnet address %s" % dest

			end
		end

		munge do |r|
			if r.key?('default')
				r['0.0.0.0/0'] = { 'gateway' => r['default']['gateway'], 'iface' => r['default']['iface'] }
				r.delete('default')
			end
			return r
		end

		def insync?(is)
			Puppet.debug 'Insyncing routes...'
			# Since we overriding nearly everything...
			return false
		end

		def dot2b(ip)
			ip.split('.').map{|s| s.to_i}.pack('C*').unpack('B*').pop
		end

	end

end











