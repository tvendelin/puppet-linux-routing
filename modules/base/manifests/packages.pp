class packages( $puppet_role = 'client'){
  package{[
    'vim',
    'tree',
  ]:
    ensure=>'latest',
  }
}