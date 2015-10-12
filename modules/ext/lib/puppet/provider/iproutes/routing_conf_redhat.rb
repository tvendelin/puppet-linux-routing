#require 'puppet/provider/iproutes'

Puppet::Type.type(:iproutes).provide( :routing_conf_redhat, :parent => :iproutes, :source => :iproutes ) do
	defaultfor :operatingsystem => [:redhat, :centos]
	confine :operatingsystem => [:redhat, :centos]
	commands :netcat => '/usr/bin/nc', :network_service => '/etc/init.d/network'

	def flush
		Puppet.debug "leaf #{self.class.name} flush start."
		Puppet.debug "On leaf, @property_hash: >#{@property_hash.to_a.join(", ")}<"

		set_routes_nonpersistent

		# If we made it so far, at least DNS and Puppet-master were reachable with new routing
		# Write the config file(s) as necessary

		Puppet.debug "Back on leaf"

		ef_routes = self.class.routes or return

		Puppet.debug "Routes to write: %s" % ef_routes.to_s

		futility_mantra = "# Written by Puppet, manual editing is futile.\n\n"
		networkf = '/etc/sysconfig/network'

		r = {}

		ef_routes.each do |dest, route|
			# Default gateway goes into /etc/sysconfig/network
			if dest == '0.0.0.0/0'

				# Read /etc/sysconfig/network into isnet Hash
				isnet = Hash[(File.open(networkf, 'r'){|x| x.read}).split("\n").grep(/^[^#\s]/).map{|l| p=l.split('='); p[0].upcase!; p}]

				# If GATEWAY different or absent, rewrite /etc/sysconfig/network
				if ! isnet.key?('GATEWAY') or isnet['GATEWAY'] != route['gateway']
					Puppet.info "Will overwrite %s" % networkf
					isnet['GATEWAY'] = route['gateway']

					f = File.open(networkf, 'w')
					f.write futility_mantra
					isnet.keys.sort.each{|k| f.write "#{k}=#{isnet[k]}\n" }
					f.close
				end
				next
			end

			# rearrange all other routes into a Hash, with interfaces for keys
			# and an array of lines of route-<iface> config for values
			r[ route['iface'] ] ||= []
			r[ route['iface'] ].push("%s via %s dev %s" % [dest, route['gateway'], route['iface']])
		end

		# Compare IS-configuration against SHOUD-configuration, and make them match
		r.keys.each do |iface|
			Puppet.debug "Routes for >%s<" % iface
			configf = "/etc/sysconfig/network-scripts/route-#{iface}"

			shlines = futility_mantra + r[iface].sort.join("\n") + "\n"

			Puppet.debug "Should lines\n %s" % shlines

			islines = File.readable?(configf) ? File.open( configf, 'r' ){|x| x.read} : ''

			Puppet.debug "Is lines\n %s" % islines

			next if islines == shlines

			Puppet.debug "Changes in routing configuration detected. Will write >%s<" % configf

			f = File.open( configf, 'w' )
			f.write shlines
			f.close

			Puppet.notice "Routing configuration for %s was rewritten from:\n %s to:\n %s" %
				[iface, islines, shlines]
		end
	end
end









