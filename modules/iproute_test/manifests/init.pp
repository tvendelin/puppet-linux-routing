class iproute_test {
  Iproutes{
    #safety_sleep => 3,
    stop_on_repeating_subnet => false,
  }

  $routes = {
    '10.1.28.0/24'  => { 'gateway' => '172.16.1.2', 'iface' => 'eth0' },
    '10.1.29.0/24'  => { 'gateway' => '172.16.4.101', 'iface' => 'bond0' },
    '10.1.30.3/32'  => { 'gateway' => '172.16.4.102', 'iface' => 'bond0' },

    'default'       => { 'gateway' => '172.16.1.2', 'iface' => 'eth0' },

    # Invalid things

    # Gateway

#    # malformed IP, gateway, test OK
#    '10.1.61.0/24'  => { 'gateway' => '1722.16.1.2', 'iface' => 'eth0' },
#
#    # gateway with multicast IP, test OK
#    '10.1.62.0/24'  => { 'gateway' => '224.16.1.2', 'iface' => 'eth0' },
#
#    # gateway with link-local IP, test OK
#    '10.1.63.0/24'  => { 'gateway' => '169.254.1.2', 'iface' => 'eth0' },
#
#    # gateway with localhost IP, test OK
#    '10.1.64.0/24'  => { 'gateway' => '127.0.1.2', 'iface' => 'eth0' },
#
#    # Subnet
#
#    # malformed IP, subnet, test OK
#    '10.1.6511.0/24'  => { 'gateway' => '172.16.1.2', 'iface' => 'eth0' },
#
#    # missing mask, subnet, test OK
#    '10.1.66.0'  => { 'gateway' => '172.16.1.2', 'iface' => 'eth0' },
#
#    # malformed mask, subnet, test OK
#    '10.1.67.0/323'  => { 'gateway' => '172.16.1.2', 'iface' => 'eth0' },
#
#    # invalid IP mask length, subnet, test OK
#    '10.1.68.0/33'  => { 'gateway' => '172.16.1.2', 'iface' => 'eth0' },
#
#    # subnet with a host IP, test OK
#    '10.1.69.7/24'  => { 'gateway' => '172.16.1.2', 'iface' => 'eth0' },
#
#    # gateway belongs to the destination subnet, test OK
#    '172.16.1.0/24'  => { 'gateway' => '172.16.1.2', 'iface' => 'eth0' },
#
#    # Interfaces
#
#    # Malformed interface name, test OK
#    '10.1.80.2/24'  => { 'gateway' => '172.16.1.2', 'iface' => 'eth?0' },
#
#    # Non-existent interface name, test OK
#    '10.1.81.0/24'  => { 'gateway' => '172.16.1.2', 'iface' => 'eth16' },


  }

  iproutes{'main':
    routes => $routes,
    ensure => 'present',
  }

}
