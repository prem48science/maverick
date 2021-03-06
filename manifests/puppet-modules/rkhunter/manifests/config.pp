# Class: rkhunter::config
#
# This module contain the configuration for rkhunter
#
# Parameters:   This module has no parameters
#
# Actions:      This module has no actions
#
# Requires:     This module has no requirements
#
# Sample Usage: include rkhunter::config
#
class rkhunter::config {

  file { $rkhunter::params::config_rkhunter_conf:
    ensure  => file,
    mode    => '0640',
    path    => $rkhunter::params::config_rkhunter_conf,
    content => template($rkhunter::params::config_rkhunter_conf_template);
  }

  file { $rkhunter::params::config_rkhunter_sys_conf:
    ensure  => file,
    mode    => '0640',
    path    => $rkhunter::params::config_rkhunter_sys_conf,
    content => template($rkhunter::params::config_rkhunter_sys_conf_template);
  }

  file { $rkhunter::params::config_rkhunter_script_directory:
    ensure  => directory,
    mode    => '0755';
  }

  file { $rkhunter::params::config_rkhunter_script:
    ensure  => file,
    mode    => '0755',
    path    => $rkhunter::params::config_rkhunter_script,
    content => template($rkhunter::params::config_rkhunter_script_template);
  }
}
