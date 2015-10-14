#require 'puppet/provider/iproutes'

Puppet::Type.type(:iproutes).provide( :routing_conf_debian, :parent => :iproutes, :source => :iproutes ) do
	defaultfor :operatingsystem => [:debian]
	confine :operatingsystem => [:debian]
	commands :netcat => '/bin/nc', :network_service => '/etc/init.d/networking'

	def flush
		Puppet.debug "leaf #{self.class.name} flush start."
		Puppet.debug "On leaf, @property_hash: >#{@property_hash.to_a.join(", ")}<"

		set_routes_nonpersistent

		# If we made it so far, at least DNS and Puppet-master were reachable with new routing
		# Write the config file(s) as necessary

		Puppet.debug "Back on leaf"

		r = self.class.routes or return
		Puppet.debug "Routes to write: %s" % r.to_s

		configf = "/etc/network/if-up.d/routes"

		# Make SHOULD lines
		shlines = ['#!/bin/sh -e', "# Written by Puppet, manual editing is futile."]
		r.keys.sort.each do |dest|
			shlines << "/bin/ip route replace #{dest} via #{r[dest]['gateway']} dev #{r[dest]['iface']}"
		end
		shlines = shlines.join("\n") + "\n"

		# Read the single config file
		islines = ''
    if File.readable?(configf)
      f = File.open( configf, 'r' )
      islines = f.read
      f.chmod(0755)
      f.close
    end

		return if islines == shlines

		Puppet.notice "Routing configuration (in files) doesn't match the actual routes. Will write >%s<" % configf

		f = File.open( configf, 'w' )
		f.write shlines
		f.chmod(0755)
		f.close


	end
end









