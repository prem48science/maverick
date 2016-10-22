class maverick_ros::ros (
    $installtype = "",
    $distribution = "kinetic",
) {
    
    # If installtype is set then use it and skip autodetection
    if $installtype == "native" {
        $_installtype = "native"
    } elsif $installtype == "source" {
        $_installtype = "source"
    # First try and determine build type based on OS and architecture
    } elsif ($distribution == "kinetic") {
    
        if (    ($operatingsystem == "Ubuntu" and $lsbdistcodename == "xenial" and ($architecture == "armv7l" or $architecture == "amd64" or $architecture == "i386")) or
                ($operatingsystem == "Ubuntu" and $lsbdistcodename == "wily" and ($architecture == "amd64" or $architecture == "i386")) or
                ($operatingsystem == "Debian" and $lsbdistcodename == "jessie" and ($architecture == "amd64" or $architecture == "arm64"))
        ) {
            $_installtype = "native"
        } else {
            $_installtype = "source"
        }
    } elsif $distribution == "jade" {
        if (    ($operatingsystem == "Ubuntu" and $lsbdistcodename == "trusty" and $architecture == "armv7l") or
                ($operatingsystem == "Ubuntu" and ($lsbdistcodename =="trusty" or $lsbdistcodename == "utopic" or $lsbdistcodename == "vivid") and ($architecture == "amd64" or $architecture == "i386"))
        ) {
            $_installtype = "native"
        } else {
            $_installtype = "source"
        }
    }
    
    if $_installtype == "native" and $ros_installed == "no" {
        warning("ROS: supported platform detected for ${distribution} distribution, using native packages")
    } elsif $_installtype == "source" and $ros_installed == "no" {
        warning("ROS: unsupported platform for ${distribution} distribution, installing from source")
    }
    
    # Install ROS bootstrap from ros.org packages
    exec { "ros-repo":
        command     => '/bin/echo "deb http://packages.ros.org/ros/ubuntu $(lsb_release -sc) main" > /etc/apt/sources.list.d/ros-latest.list',
        creates      => "/etc/apt/sources.list.d/ros-latest.list",
    } ->
    exec { "ros-repo-key":
        #command     => "/usr/bin/wget https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -O - | apt-key add -",
        command     => "/usr/bin/apt-key adv --keyserver hkp://ha.pool.sks-keyservers.net:80 --recv-key 0xB01FA116",
        unless      => "/usr/bin/apt-key list |/bin/grep B01FA116",
    } ->
    exec { "ros-aptupdate":
        command     => "/usr/bin/apt-get update",
        unless      => "/usr/bin/dpkg -l python-rosinstall"
    } ->
    package { ["python-rosdep", "python-rosinstall", "python-rosinstall-generator"]:
        ensure      => installed,
        require     => Exec["ros-aptupdate"],
    }
    ensure_packages(["python-wstool", "build-essential"])

    # Install from ros repos
    if $_installtype == "native" {
        package { ["ros-${distribution}-ros-base", "ros-${distribution}-mavros", "ros-${distribution}-mavros-extras", "ros-${distribution}-mavros-msgs", "ros-${distribution}-test-mavros", "ros-${distribution}-vision-opencv"]:
            ensure      => installed
        }
        
    # Build from source
    } elsif $_installtype == "source" {
        $_installdir = "/srv/maverick/software/ros"
        file { "${_installdir}":
            ensure      => directory,
            owner       => "mav",
            group       => "mav",
            mode        => 755,
        }
        $_builddir = "/srv/maverick/var/build/ros_catkin_ws"
        file { "${_builddir}":
            ensure      => directory,
            owner       => "mav",
            group       => "mav",
            mode        => 755,
        }
        $buildparallel = ceiling((0 + $::processorcount) / 2) # Restrict build parallelization to roughly processors/2
        
        # Initialize rosdep
        exec { "rosdep-init":
            command         => "/usr/bin/rosdep init",
            creates         => "/etc/ros/rosdep/sources.list.d/20-default.list",
            require         => Package["python-rosdep"]
        } ->
        exec { "rosdep-update":
            user            => "mav",
            command         => "/usr/bin/rosdep update",
            creates         => "/srv/maverick/.ros/rosdep/sources.cache",
            require         => Package["python-rosdep"]
        } ->
        exec { "catkin_rosinstall":
            command         => "/usr/bin/rosinstall_generator ros_comm --rosdistro ${distribution} --deps --wet-only --tar > ${distribution}-ros_comm-wet.rosinstall && /usr/bin/wstool init -j${buildparallel} src ${distribution}-ros_comm-wet.rosinstall",
            cwd             => "${_builddir}",
            user            => "mav",
            creates         => "${_builddir}/src/.rosinstall"
        } ->
        exec { "rosdep-install":
            command         => "/usr/bin/rosdep install --from-paths src --ignore-src --rosdistro ${distribution} -y",
            cwd             => "${_builddir}",
            user            => "mav",
            timeout         => 0,
            unless          => "/usr/bin/rosdep check --from-paths src --ignore-src --rosdistro ${distribution} -y |/bin/grep 'have been satis'",
        } ->
        exec { "catkin_make":
            command         => "${_builddir}/src/catkin/bin/catkin_make_isolated --install --install-space ${_installdir} -DCMAKE_BUILD_TYPE=Release -j${buildparallel}",
            cwd             => "${_builddir}",
            user            => "mav",
            creates         => "${_installdir}/lib/rosbag/topic_renamer.py",
            timeout         => 0,
            require         => File["${_installdir}"]
        }
        
        # Add opencv to the existing workspace through vision_opencv package, this also installs std_msgs package as dependency
        ensure_packages(["libpoco-dev", "libyaml-cpp-dev"])
        exec { "ws_add_opencv":
            command         => "/usr/bin/rosinstall_generator vision_opencv --rosdistro ${distribution} --deps --wet-only --tar >${distribution}-vision_opencv-wet.rosinstall && /usr/bin/wstool merge -t src ${distribution}-vision_opencv-wet.rosinstall && /usr/bin/wstool update -t src",
            cwd             => "${_builddir}",
            user            => "mav",
            creates         => "${_builddir}/src/vision_opencv",
            require         => [ Package["libpoco-dev"], Exec["catkin_make"] ]
        } ->
        exec { "catkin_make_vision_opencv":
            command         => "${_builddir}/src/catkin/bin/catkin_make_isolated --install --install-space ${_installdir} -DCMAKE_BUILD_TYPE=Release -j${buildparallel}",
            cwd             => "${_builddir}",
            user            => "mav",
            creates         => "${_installdir}/lib/libopencv_optflow3.so.3.1.0",
            timeout         => 0,
            require         => File["${_installdir}"]
        }

        # Add mavros to the existing workspace, this also installs mavlink package as dependency
        exec { "ws_add_mavros":
            command         => "/usr/bin/rosinstall_generator mavros --rosdistro ${distribution} --deps --wet-only --tar >${distribution}-mavros-wet.rosinstall && /usr/bin/rosinstall_generator visualization_msgs --rosdistro ${distribution} --deps --wet-only --tar >>${distribution}-mavros-wet.rosinstall && /usr/bin/rosinstall_generator urdf --rosdistro ${distribution} --deps --wet-only --tar >>${distribution}-mavros-wet.rosinstall && /usr/bin/wstool merge -t src ${distribution}-mavros-wet.rosinstall && /usr/bin/wstool update -t src",
            cwd             => "${_builddir}",
            user            => "mav",
            creates         => "${_builddir}/src/mavros",
            require         => Exec["catkin_make"]
        } ->
        exec { "catkin_make_mavros":
            # Note must only use -j1 otherwise we get compiler errors
            command         => "/usr/bin/rosdep install --from-paths src --ignore-src --rosdistro ${distribution} -y && ${_builddir}/src/catkin/bin/catkin_make_isolated --install --install-space ${_installdir} -DCMAKE_BUILD_TYPE=Release -j1",
            cwd             => "${_builddir}",
            user            => "mav",
            creates         => "${_installdir}/lib/libmavros.so",
            timeout         => 0,
            require         => File["${_installdir}"]
        }

        # Create symlink to usual vendor install directory
        file { "/opt/ros":
            ensure      => directory,
            mode        => "755",
            owner       => "root",
            group       => "root",
        } ->
        file { "/opt/ros/${distribution}":
            ensure      => link,
            target      => "/srv/maverick/software/ros"
        }
    }  
    
    file { "/etc/profile.d/ros-env.sh":
        ensure      => present,
        mode        => 644,
        owner       => "root",
        group       => "root",
        content     => "source /opt/ros/${distribution}/setup.bash",
    }
    
}