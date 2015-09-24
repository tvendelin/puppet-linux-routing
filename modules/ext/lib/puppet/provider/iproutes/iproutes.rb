require 'set'

Puppet::Type.type(:iproutes).provide( :iproutes ) do
	commands :ip => '/sbin/ip'
	#, :ping =>'/bin/ping'

	mk_resource_methods

	def create
		Puppet.debug "Useless create method, that still has to exist"
	end

	def destroy
		Puppet.debug "Useless destroy method, that still has to exist"
	end

	def exists?
		@property_hash[:ensure] == :present
	end

	def routes=(val)
		#@resource[:routes]
	end

	@routes = {}
	@ifaces = {}
	#@rewrite = []

	def self.routes
		Puppet.debug "Class @routes #{@routes.to_s}"
		return @routes
	end

	def self.ifaddr(iface)
		@ifaces[iface.to_s]
	end

	def self.add_route_to_config(dest,route)
		Puppet.debug ">#{dest}< >#{route}< "
		@routes ||={}
		@routes[dest.to_s] = route
	end

	def self.instances
		Puppet.debug "Running self.instances method, #{self.name}"
		@ifaces = {}
		@ifaces = get_ifaces
		Puppet.debug "Active interfaces: >%s<" % @ifaces.to_a.join(',')
		[ new( get_ipv4_routes ) ]
	end

	def self.prefetch( resources )
		Puppet.debug "Running self.prefetch method, #{self.name}"
		instances.each do |prov|
			if resource = resources[prov.name]
				Puppet.debug "Prefetch: resource exists!"
				resource.provider = prov
			end
		end
		Puppet.debug "On trunk, @property_hash: >#{@property_hash.to_a.join(", ")}<"
	end

	def set_routes_nonpersistent
		Puppet.debug "Will check if routes in your manifest are suitable for active interfaces..."

		ifdown = []
		changes_pending = false
		bad_gateway = false

		@resource[:routes].keys.each do |dest|
			if ! ifaddr = self.class.ifaddr(@resource[:routes][dest]['iface'])
				ifdown.push(@resource[:routes][dest]['iface'])
				next
			end

			begin
				badgateway?({ 	:ifip => ifaddr,
								:gw => @resource[:routes][dest]['gateway'],
								:iface => @resource[:routes][dest]['iface']
				})
			rescue => ex
				Puppet.err ex.message
				bad_gateway = true
			end
		end

		if ! ifdown.empty? or bad_gateway
			Puppet.err "Interfaces down/missing: %s" % ifdown.uniq.join(', ') if ! ifdown.empty?
			raise 'Problems with routing definition detected, leaving routing table and config files untouched'
		else
			Puppet.debug "All interfaces are active and no subnetting errors found."
		end

		# Remove multiple entries for the same subnet (route add -net ... thing
		if( multi = @property_hash[:routes].keys.grep(/@/) and ! multi.empty? )

      if @resource[:stop_on_repeating_subnet]
        raise "Multiple entries for the same subnet(s) found, stopping. Set stop_on_repeating_subnet => false to override"
      end

      Puppet.warning "Multiple entries for the same subnet(s) found..."
      changes_pending = true

      multi.each do |entry|
        Puppet.debug "Processing entry >%s<" % entry

        entry =~ /^(.+?)@(.+)$/ or raise "Entry was >%s<" % entry
        dest = $1; gw = $2

        if @resource[:routes].key?(dest) and @resource[:routes][dest]['gateway'] == gw
          # Rewrite @property_hash entry, if it exists in catalog
          @property_hash[:routes][dest] = @property_hash[:routes].delete(entry)
        else
          # Delete the double entries not found in the catalog
          Puppet.warning "The route to %s via %s will be deleted" % [dest,gw]
          ip 'route', 'delete', dest, 'via', gw

          @property_hash[:routes].delete( entry )
        end
      end
    end

    # At this point, no double entries should exist neither on the system nor in @property_hash

		@resource[:routes].keys.each do |dest|
			Puppet.debug "Flush: dest: %s" % dest
			if @property_hash[:routes].key?(dest)
			  Puppet.debug "Flush: IS %s" % @property_hash[:routes][dest].to_a.sort.join(',')
			end
			Puppet.debug "Flush: SHOULD %s" % @resource[:routes][dest].to_a.sort.join(',')

			if (! @property_hash[:routes].key?(dest)) or (@resource[:routes][dest] != @property_hash[:routes][dest] )
				# Give the user the last chance
				if ! changes_pending and @resource[:safety_sleep] > 0
					Puppet.warning \
					  "The routing definition has changed! Will start applying in %s sec. Hit ^C to abort." \
					  % @resource[:safety_sleep]
					sleep @resource[:safety_sleep]
				end
				changes_pending = true

				Puppet.debug "Flush: need to change %s"  % dest
				args = []
				args.push( 'via', @resource[:routes][dest]['gateway'] )
				args.push( 'dev', @resource[:routes][dest]['iface'] ) if @resource[:routes][dest]['iface']

				begin
					ip 'route', 'replace', dest, args
				rescue => ex
					raise "#{ex.message}. This route won't be written to any config file(s)"
				end

        # Report the change
				# Did it exist previously?
				from = 'non-existent'

				if @property_hash[:routes][dest]
					from = dest +
					' via ' + @property_hash[:routes][dest]['gateway'] +
					' dev ' + @property_hash[:routes][dest]['iface']
				end

				Puppet.notice "Route changed from: >" + from +
					'< to >' + dest + ' ' + args.join(' ') + '<'

			end

			# Clean up
			@property_hash[:routes].delete(dest)

			# Add route for writing into config files
			self.class.add_route_to_config( dest, @resource[:routes][dest] )
		end

    # Done adding/modifying routes
    # Delete the routes not set in resource/catalog

    changes_pending = true if ! @property_hash[:routes].empty?

		@property_hash[:routes].keys.each do |dest|
		  Puppet.warning "The route to %s will be deleted" % dest
      ip 'route', 'delete', dest
		end

		if ! changes_pending # no need for expensive netcat test
			Puppet.info "routing has not changed"
			return
		end

		# The moment of truth: if we cannot get TCP connection the puppet master, raise an exception
		begin
			netcat( '-w', '3', '-z', Puppet['server'], Puppet['masterport'] )
		rescue
			Puppet.err "Cannot reach the master >%s< at TCP port >%s<" %  [ Puppet['server'], Puppet['masterport'] ]
			network_service 'restart'
			raise Puppet::Error.new('Routing broken. Network has been restarted, previous routing configuration loaded.')
		end
	end

	def self.get_ipv4_routes

		routes = {}
		doubles = Set.new

		lines = ( File.open('/proc/net/route', 'r') { |x| x.read } ).split("\n")
		lines.shift
		lines.each do |l|
			l.sub(/\s+$/, '')
			r = l.split("\t")

			# If the route is not through a gateway, ignore it
			next if ( r[3].to_i & 2 ) == 0

			netip = [ r[1] ].pack('H*').unpack('C*').reverse.join('.')
			netmask = [ r[7] ].pack('H*').unpack('b*').pop.sub(/0+/,'').length
			destination = "#{netip}/#{netmask}"

			gateway = [ r[2] ].pack('H*').unpack('C*').reverse.join('.')

			if( routes.key?(destination) )
			  # route add -net ... allows this!
			  Puppet.debug "Another route to identical subnet >%s< found" % destination

			  # Handle the existing Hash entry
			  routes["#{destination}@#{routes[destination]['gateway']}"] = routes[destination]
			  doubles.add( destination )

			  # Add a new one
			  routes["#{destination}@#{gateway}"] = { 'gateway' => gateway, 'iface' => r[0] }
			else
			  routes[destination] = { 'gateway' => gateway, 'iface' => r[0] }
			end
		end

		doubles.each do |destination|
		  routes.delete(destination)
		end

		return { :name => 'main', :routes =>routes, :ensure => :present }
	end

	def self.get_ifaces
		ifaces = {}

		(ip 'a').split("\n").each do |l|
			# inet 172.16.1.30/24 brd 172.16.1.255 scope global bond0
			/^\s*inet\s*(\d{1,3}(?:\.\d{1,3}){3}\/\d\d?).+?(\w+)$/ =~l or next
			ifaces[$2] = $1
		end
		Puppet.debug "Interfaces: %s" % ifaces.to_a.join(',')
		return ifaces
	end

	def ip_b(ip)
		ip =~ /^(\d{1,3}(?:\.\d{1,3}){3})$/ or
			raise "Expecting IPv4 address, got >%s<" % ip

		ip_b = ip.split('.').map{|s| s.to_i}.pack('C*').unpack('B*').pop

		Puppet.debug "IP >%s< is binary >%s<" % [ip, ip_b]
		return ip_b
	end

	def badgateway?(args={})
		# This part of validation needs the interface IP (not part of the catalog),
		# hence performed here.

		Puppet.debug "Is gateway >%s< suitable for IF >%s<?" % [args[:gw], args[:ifip]]

		args[:ifip] =~ /^(\d{1,3}(?:\.\d{1,3}){3})\/(\d\d?)$/ or
			raise "Expecting interface IP in CIDR notation, got >%s<" % args[:ifip]
		mask = $2.to_i
		ifip_b = ip_b($1)
		gw_b = ip_b( args[:gw] )

		# Now that we know what should be the mask for our gateway...
		Puppet.debug "Are gateway >%s< and interface >%s< in the same subnet?" % [gw_b, ifip_b]

		gw_b[0..(mask-1)] == ifip_b[0..(mask-1)] or
			raise "Gateway >%s< is not reachable from interface >%s< with IP >%s<" % [args[:gw], args[:iface], args[:ifip]]

		Puppet.debug "Is gateway IP >%s< a valid host address (i.e., not a network or broadcast)?" % args[:gw]

		if gw_b[mask..31] =~ /^1+$/ or gw_b[mask..31] =~ /^0+$/
			raise "Gateway >%s< is not a valid host IP" % args[:gw]
		end

	end
end








