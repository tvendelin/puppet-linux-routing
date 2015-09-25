#require 'puppet/provider/iproutes'

Puppet::Type.type(:iproutes).provide( :routing_conf_sles, :parent => :iproutes, :source => :iproutes ) do
	defaultfor :operatingsystem => [:sles]
	confine :operatingsystem => [:sles]
	commands :netcat => '/usr/bin/netcat', :network_service => '/etc/init.d/network'
	
	def flush
		Puppet.debug "leaf #{self.class.name} flush start."
		Puppet.debug "On leaf, @property_hash: >#{@property_hash.to_a.join(", ")}<"
		
		set_routes_nonpersistent
		
		# If we made it so far, at least DNS and Puppet-master were reachable with new routing
		# Write the config file(s) as necessary
		
		Puppet.debug "Back on leaf"
		
		r = self.class.routes or return
		Puppet.debug "Routes to write: %s" % r.to_s
		
		futility_mantra = "# Written by Puppet, manual editing is futile.\n\n"
		configf = "/etc/sysconfig/network/routes"
		
		# Make SHOULD lines
		shlines = [futility_mantra]
		r.keys.sort.each do |dest|
			shlines << "#{dest} #{r[dest]['gateway']} - #{r[dest]['iface']}"
		end
		shlines = shlines.join("\n") + "\n"
		
		# Read the single config file
		islines = File.readable?(configf) ? File.open( configf, 'r' ){|x| x.read} : ''
		
		return if islines == shlines
		
		Puppet.notice "Routing configuration (in files) doesn't match the actual routes. Will write >%s<" % configf	
		
		f = File.open( configf, 'w' )
		f.write shlines
		f.close
	end
end









