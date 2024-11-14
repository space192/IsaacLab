function print_step_header {
    # Cyan
    echo -e "\e[36m  - ${@}\e[0m"
}

function print_header {
    # Magenta
    echo -e "\e[35m**** ${@} ****\e[0m"
}

# TODO: Move this to its own 'display' init script. It does not really belong here
# Configure the 'XDG_RUNTIME_DIR' path
print_step_header "Create the user XDG_RUNTIME_DIR path '${XDG_RUNTIME_DIR}'"
mkdir -p ${XDG_RUNTIME_DIR}
# Ensure only the 'default' user can access this directory
chmod 700 ${XDG_RUNTIME_DIR}
# Set the default background
mkdir -p /etc/alternatives
ln -sf /usr/share/backgrounds/steam.jpg /etc/alternatives/desktop-background
chmod a+r /etc/alternatives/desktop-background


# Setup services log path
print_step_header "Setting ownership of all log files in '${USER_HOME}/.cache/log'"
mkdir -p "${USER_HOME}/.cache/log"


# Set the root and user password
print_step_header "Setting root password"
echo "root:${USER_PASSWORD}" | chpasswd
print_step_header "Setting user password"
echo "${USER}:${USER_PASSWORD}" | chpasswd

# Set root XDG_RUNTIME_DIR path
mkdir -p /tmp/runtime-root
chown root:root /tmp/runtime-root

echo -e "\e[34mDONE\e[0m"


#########################################################



print_header "Configure container dbus"
if ([ "${MODE}" != "s" ] && [ "${MODE}" != "secondary" ]); then
    if [[ "${HOST_DBUS}" == "true" ]]; then
        print_step_header "Container configured to use the host dbus";
        # Disable supervisord script
        sed -i 's|^autostart.*=.*$|autostart=false|' /app/conf.d/dbus.conf
    else
        print_step_header "Container configured to run its own dbus";
        # Enable supervisord script
        sed -i 's|^autostart.*=.*$|autostart=true|' /app/conf.d/dbus.conf
        # Configure dbus to run as USER
        sed -i "/  <user>/c\  <user>${USER}</user>" /usr/share/dbus-1/system.conf
        # Remove old dbus session
        rm -rf ${USER_HOME}/.dbus/session-bus/* 2> /dev/null
        # Remove old dbus pids
        mkdir -p /var/run/dbus
        chmod -R 770 /var/run/dbus/
        # Generate a dbus machine ID
        dbus-uuidgen > /var/lib/dbus/machine-id
        # Remove old lockfiles
        find /var/run/dbus -name "pid" -exec rm -f {} \;
    fi
else
    print_step_header "Dbus service not available when container is run in 'secondary' mode."
    sed -i 's|^autostart.*=.*$|autostart=false|' /app/conf.d/dbus.conf
fi

echo -e "\e[34mDONE\e[0m"



print_header "Configure udevd"

# Since this container may also be run with CAP_SYS_ADMIN, ensure we can actually execute "udevadm trigger"
run_dumb_udev="false"
if [ ! -w /sys ]; then
    # Disable supervisord script since we are not able to write to sysfs
    print_step_header "Disable udevd - /sys is mounted RO"
    sed -i 's|^autostart.*=.*$|autostart=false|' /app/conf.d/udex.conf
    run_dumb_udev="true"
elif [ ! -d /run/udev ]; then
    # Disable supervisord script since we are not able to write to udev/data path
    print_step_header "Disable udevd - /run/udev does not exist"
    sed -i 's|^autostart.*=.*$|autostart=false|' /app/conf.d/udex.conf
    run_dumb_udev="true"
elif [ ! -w /run/udev ]; then
    # Disable supervisord script since we are not able to write to udev/data path
    print_step_header "Disable udevd - /run/udev is mounted RO"
    sed -i 's|^autostart.*=.*$|autostart=false|' /app/conf.d/udex.conf
    run_dumb_udev="false"
elif udevadm trigger &> /dev/null; then
    print_step_header "Configure container to run udev management"
    # Enable supervisord script
    sed -i 's|^autostart.*=.*$|autostart=true|' /app/conf.d/udex.conf
    # Configure udev permissions
    if [[ -f /lib/udev/rules.d/60-steam-input.rules ]]; then
        sed -i 's/MODE="0660"/MODE="0666"/' /lib/udev/rules.d/60-steam-input.rules
    fi
    run_dumb_udev="false"
else
    # Disable supervisord script since we are not able to execute "udevadm trigger"
    print_step_header "Disable udev service due to privilege restrictions"
    sed -i 's|^autostart.*=.*$|autostart=false|' /app/conf.d/udex.conf
    run_dumb_udev="true"
fi

if [ "${run_dumb_udev}" = "true" ]; then
    # Enable dumb-udev instead of udevd
    print_step_header "Enable dumb-udev service"
    sed -i 's|^command.*=.*$|command=start-dumb-udev.sh|' /app/conf.d/udex.conf
    sed -i 's|^autostart.*=.*$|autostart=true|' /app/conf.d/udex.conf
fi


if [[ -e /dev/uinput ]]; then
    print_step_header "Ensure the default user has permission to r/w on input devices"
    chmod 0666 /dev/uinput
fi

echo -e "\e[34mDONE\e[0m"


#######################################################
# Configure dbus
print_header "Configure local"

current_local=$(head -n 1 /etc/locale.gen)
user_local=$(echo ${USER_LOCALES} | cut -d ' ' -f 1)

if [ "${current_local}" != "${USER_LOCALES}" ]; then
    print_step_header "Configuring Locales to ${USER_LOCALES}"
	rm /etc/locale.gen
	echo -e "${USER_LOCALES}\nen_US.UTF-8 UTF-8" > "/etc/locale.gen"
	export LANGUAGE="${user_local}"
	export LANG="${user_local}"
	export LC_ALL="${user_local}" 2> /dev/null
	sleep 0.5
	locale-gen
	update-locale LC_ALL="${user_local}"
else
    print_step_header "Locales already set correctly to ${USER_LOCALES}"
fi

echo -e "\e[34mDONE\e[0m"
######################################################










# Fech NVIDIA GPU device (if one exists)
if [ "${NVIDIA_VISIBLE_DEVICES:-}" = "all" ]; then
    export gpu_select=$(nvidia-smi --format=csv --query-gpu=uuid 2> /dev/null | sed -n 2p)
elif [ "${NVIDIA_VISIBLE_DEVICES:-}X" = "X" ]; then
    export gpu_select=$(nvidia-smi --format=csv --query-gpu=uuid 2> /dev/null | sed -n 2p)
else
    export gpu_select=$(nvidia-smi --format=csv --id=$(echo "$NVIDIA_VISIBLE_DEVICES" | cut -d ',' -f1) --query-gpu=uuid | sed -n 2p)
    if [ "${gpu_select:-}X" = "X" ]; then
        export gpu_select=$(nvidia-smi --format=csv --query-gpu=uuid 2> /dev/null | sed -n 2p)
    fi
fi

# NVIDIA Params
if [ "X${gpu_select:-}" != "X" ]; then
    export nvidia_pci_address="$(nvidia-smi --format=csv --query-gpu=pci.bus_id --id="${gpu_select:?}" 2> /dev/null | sed -n 2p | cut -d ':' -f2,3)"
    export nvidia_gpu_name=$(nvidia-smi --format=csv --query-gpu=name --id="${gpu_select:?}" 2> /dev/null | sed -n 2p)
    export nvidia_host_driver_version="$(nvidia-smi 2> /dev/null | grep NVIDIA-SMI | cut -d ' ' -f3)"
fi

# Intel params
# This figures out if it's an intel CPU with integrated GPU
export intel_cpu_model="$(lscpu | grep 'Model name:' | grep -i intel | cut -d':' -f2 | xargs)"
# We need to check if the user has an intel ARC GPU as well
export intel_gpu_model="$(lspci | grep -i "VGA compatible controller: Intel" | cut -d':' -f3 | xargs)"

# AMD params
export amd_cpu_model="$(lscpu | grep 'Model name:' | grep -i amd | cut -d':' -f2 | xargs)"
export amd_gpu_model="$(lspci | grep -i vga | grep -i amd)"


function download_driver {
    mkdir -p "/tmp/Downloads"
    chown -R "/tmp/Downloads"

    if [[ ! -f "/tmp/Downloads/NVIDIA_${nvidia_host_driver_version:?}.run" ]]; then
        print_step_header "Downloading driver v${nvidia_host_driver_version:?}"
        wget -q --show-progress --progress=bar:force:noscroll \
            -O /tmp/NVIDIA.run \
            "http://download.nvidia.com/XFree86/Linux-x86_64/${nvidia_host_driver_version:?}/NVIDIA-Linux-x86_64-${nvidia_host_driver_version:?}.run"
        [[ $? -gt 0 ]] && print_error "Unable to download driver. Exit!" && return 1

        mv /tmp/NVIDIA.run "/tmp/Downloads/NVIDIA_${nvidia_host_driver_version:?}.run"
    fi
}

function install_nvidia_driver {
    USER_HOME="/root"
    # Check here if the currently installed version matches using nvidia-settings
    nvidia_settings_version=$(nvidia-settings --version 2> /dev/null | grep version | cut -d ' ' -f 4)
    if [ "${nvidia_settings_version:-}X" != "${nvidia_host_driver_version:-}X" ]; then
        # Download the driver (if it does not yet exist locally)
        download_driver

        if (($(echo $nvidia_host_driver_version | cut -d '.' -f 1) > 500)); then
            print_step_header "Installing NVIDIA driver v${nvidia_host_driver_version:?} to match what is running on the host"
            chmod +x "/tmp/Downloads/NVIDIA_${nvidia_host_driver_version:?}.run"
            "/tmp/Downloads/NVIDIA_${nvidia_host_driver_version:?}.run" \
                --silent \
                --accept-license \
                --skip-depmod \
                --skip-module-unload \
                --no-kernel-modules \
                --no-kernel-module-source \
                --install-compat32-libs \
                --no-nouveau-check \
                --no-nvidia-modprobe \
                --no-systemd \
                --no-distro-scripts \
                --no-rpms \
                --no-backup \
                --no-check-for-alternate-installs \
                --no-libglx-indirect \
                --no-install-libglvnd \
                > "/tmp/Downloads/nvidia_gpu_install.log" 2>&1
        else 
            print_step_header "Installing Legacy NVIDIA driver v${nvidia_host_driver_version:?} to match what is running on the host"
            chmod +x "/tmp/Downloads/NVIDIA_${nvidia_host_driver_version:?}.run"
            "/tmp/Downloads/NVIDIA_${nvidia_host_driver_version:?}.run" \
                --silent \
                --accept-license \
                --skip-depmod \
                --skip-module-unload \
                --no-kernel-module \
                --no-kernel-module-source \
                --install-compat32-libs \
                --no-nouveau-check \
                --no-nvidia-modprobe \
                --no-systemd \
                --no-distro-scripts \
                --no-rpms \
                --no-backup \
                --no-check-for-alternate-installs \
                --no-libglx-indirect \
                --no-install-libglvnd \
                > "/tmp/Downloads/nvidia_gpu_install.log" 2>&1
        fi
    fi
}

function patch_nvidia_driver {
    USER_HOME="/root"
    # REF: https://github.com/keylase/nvidia-patch#docker-support
    if [ "${NVIDIA_PATCH_VERSION:-}X" != "X" ]; then
        # Don't fail boot if something goes wrong here. Set +e
        (
            set +e
            if [ ! -f "/tmp/Downloads/nvidia-patch.${NVIDIA_PATCH_VERSION:?}.sh" ]; then
                print_step_header "Fetch NVIDIA NVENC patch"
                wget -q --show-progress --progress=bar:force:noscroll \
                    -O "/tmp/Downloads/nvidia-patch.${NVIDIA_PATCH_VERSION:?}.sh" \
                    "https://raw.githubusercontent.com/keylase/nvidia-patch/${NVIDIA_PATCH_VERSION:?}/patch.sh"
            fi
            if [ ! -f "/tmp/Downloads/nvidia-patch-fbc.${NVIDIA_PATCH_VERSION:?}.sh" ]; then
                print_step_header "Fetch NVIDIA NvFBC patch"
                wget -q --show-progress --progress=bar:force:noscroll \
                    -O "/tmp/Downloads/nvidia-patch-fbc.${NVIDIA_PATCH_VERSION:?}.sh" \
                    "https://raw.githubusercontent.com/keylase/nvidia-patch/${NVIDIA_PATCH_VERSION:?}/patch-fbc.sh"
            fi
            chmod +x \
                "/tmp/Downloads/nvidia-patch.${NVIDIA_PATCH_VERSION:?}.sh" \
                "/tmp/Downloads/nvidia-patch-fbc.${NVIDIA_PATCH_VERSION:?}.sh"

            print_step_header "Install NVIDIA driver patches"
            echo "/patched-lib" > /etc/ld.so.conf.d/000-patched-lib.conf
            mkdir -p "/patched-lib"
            PATCH_OUTPUT_DIR="/patched-lib" "/tmp/Downloads/nvidia-patch.${NVIDIA_PATCH_VERSION:?}.sh"
            PATCH_OUTPUT_DIR="/patched-lib" "/tmp/Downloads/nvidia-patch-fbc.${NVIDIA_PATCH_VERSION:?}.sh"

            pushd "/patched-lib" &> /dev/null || { print_error "Failed to push directory to /patched-lib"; exit 1; }
            for f in * ; do
                suffix="${f##*.so}"
                name="$(basename "$f" "$suffix")"
                [ -h "$name" ] || ln -sf "$f" "$name"
                [ -h "$name" ] || ln -sf "$f" "$name.1"
            done
            ldconfig
            popd &> /dev/null || { print_error "Failed to pop directory out of /patched-lib"; exit 1; }
        )
    else
        print_step_header "Leaving NVIDIA driver stock without patching"
    fi
}

function install_deb_mesa {
    if [ ! -f /tmp/init-mesa-libs-install.log ]; then
        print_step_header "Enable i386 arch"
        dpkg --add-architecture i386
        print_step_header "Add Debian SID sources"
        echo "deb http://deb.debian.org/debian/ sid main" > /etc/apt/sources.list
        apt-get update &>> /tmp/init-mesa-libs-install.log
        print_step_header "Install mesa vulkan drivers"
        echo "" >> /tmp/init-mesa-libs-install.log
        apt-get install -y --no-install-recommends \
            libvulkan1 \
            libvulkan1:i386 \
            mesa-vulkan-drivers \
            mesa-vulkan-drivers:i386 \
            mesa-utils \
            mesa-utils-extra \
            vulkan-tools \
            &>> /tmp/init-mesa-libs-install.log
    else
        print_step_header "Mesa has already been installed into this container"
    fi
}

function install_amd_gpu_driver {
    if command -v pacman &> /dev/null; then
        print_step_header "Install AMD Mesa driver"
        pacman -Syu --noconfirm --needed \
            lib32-vulkan-icd-loader \
            lib32-vulkan-radeon \
            vulkan-icd-loader \
            vulkan-radeon
    elif command -v apt-get &> /dev/null; then
        install_deb_mesa
    fi
}

function install_intel_gpu_driver {
    if command -v pacman &> /dev/null; then
        print_step_header "Install Intel Mesa driver"
        pacman -Syu --noconfirm --needed \
            lib32-vulkan-icd-loader \
            lib32-vulkan-intel \
            vulkan-icd-loader \
            vulkan-intel
    elif command -v apt-get &> /dev/null; then
        install_deb_mesa
    fi
}

# Intel Arc GPU or Intel CPU with possible iGPU
if [ "${intel_gpu_model:-}X" != "X" ]; then
    print_header "Found Intel device '${intel_gpu_model:?}'"
    install_intel_gpu_driver
elif [ "${intel_cpu_model:-}X" != "X" ]; then
    print_header "Found Intel device '${intel_cpu_model:?}'"
    install_intel_gpu_driver
else
    print_header "No Intel device found"
fi
# AMD GPU
if [ "${amd_gpu_model:-}X" != "X" ]; then
    print_header "Found AMD device '${amd_gpu_model:?}'"
    install_amd_gpu_driver
else
    print_header "No AMD device found"
fi
# NVIDIA GPU
if [ "${nvidia_pci_address:-}X" != "X" ]; then
    print_header "Found NVIDIA device '${nvidia_gpu_name:?}'"
    install_nvidia_driver
    patch_nvidia_driver
else
    print_header "No NVIDIA device found"
fi

echo -e "\e[34mDONE\e[0m"





############################################################

# Fech NVIDIA GPU device (if one exists)
if [ "${NVIDIA_VISIBLE_DEVICES:-}" == "all" ]; then
    export gpu_select=$(nvidia-smi --format=csv --query-gpu=uuid 2> /dev/null | sed -n 2p)
elif [ -z "${NVIDIA_VISIBLE_DEVICES:-}" ]; then
    export gpu_select=$(nvidia-smi --format=csv --query-gpu=uuid 2> /dev/null | sed -n 2p)
else
    export gpu_select=$(nvidia-smi --format=csv --id=$(echo "$NVIDIA_VISIBLE_DEVICES" | cut -d ',' -f1) --query-gpu=uuid | sed -n 2p)
    if [ -z "$gpu_select" ]; then
        export gpu_select=$(nvidia-smi --format=csv --query-gpu=uuid 2> /dev/null | sed -n 2p)
    fi
fi

export nvidia_gpu_hex_id=$(nvidia-smi --format=csv --query-gpu=pci.bus_id --id="${gpu_select}" 2> /dev/null | sed -n 2p)


# Configure a NVIDIA X11 config
function configure_nvidia_x_server {
    print_step_header "Configuring X11 with GPU ID: '${gpu_select}'"
    nvidia_gpu_hex_id=$(nvidia-smi --format=csv --query-gpu=pci.bus_id --id="${gpu_select}" 2> /dev/null | sed -n 2p)
    IFS=":." ARR_ID=(${nvidia_gpu_hex_id})
    unset IFS
    bus_id=PCI:$((16#${ARR_ID[1]})):$((16#${ARR_ID[2]})):$((16#${ARR_ID[3]}))
    print_step_header "Configuring X11 with PCI bus ID: '${bus_id}'"
    export MODELINE=$(cvt -r "${DISPLAY_SIZEW}" "${DISPLAY_SIZEH}" "${DISPLAY_REFRESH}" | sed -n 2p)
    
    
    print_step_header "Writing X11 config with ${MODELINE}"
    connected_monitor="--use-display-device=None"
    if [[ "X${DISPLAY_VIDEO_PORT:-}" != "X" ]]; then
        connected_monitor="--connected-monitor=${DISPLAY_VIDEO_PORT:?}"
    fi
    
    
    nvidia-xconfig --virtual="${DISPLAY_SIZEW:?}x${DISPLAY_SIZEH:?}" --depth="${DISPLAY_CDEPTH:?}" --mode=$(echo "${MODELINE:?}" | awk '{print $2}' | tr -d '"') --allow-empty-initial-configuration --no-probe-all-gpus --busid="${bus_id:?}" --no-sli --no-base-mosaic --only-one-x-screen ${connected_monitor:?}




    
    sed -i '/Driver\s\+"nvidia"/a\    Option         "ModeValidation" "NoMaxPClkCheck, NoEdidMaxPClkCheck, NoMaxSizeCheck, NoHorizSyncCheck, NoVertRefreshCheck, NoVirtualSizeCheck, NoTotalSizeCheck, NoDualLinkDVICheck, NoDisplayPortBandwidthCheck, AllowNon3DVisionModes, AllowNonHDMI3DModes, AllowNonEdidModes, NoEdidHDMI2Check, AllowDpInterlaced"\n    Option         "HardDPMS" "False"' /etc/X11/xorg.conf
    sed -i '/Section\s\+"Monitor"/a\    '"${MODELINE}" /etc/X11/xorg.conf
    # Prevent interference between GPUs
    echo -e "Section \"ServerFlags\"\n    Option \"AutoAddGPU\" \"false\"\nEndSection" | tee -a /etc/X11/xorg.conf > /dev/null
    # Configure primary GPU
    sed -i '/Driver\s\+"nvidia"/a\    Option "AllowEmptyInitialConfiguration"\n    Option "PrimaryGPU" "yes"' /usr/share/X11/xorg.conf.d/nvidia-drm-outputclass.conf 
}

# Allow anybody for running x server
function configure_x_server {
    # Function to print step header
    print_step_header() {
        echo "Step: $1"
    }

    # Configure x to be run by anyone
    if [[ ! -f /etc/X11/Xwrapper.config ]]; then
        print_step_header "Create Xwrapper.config"
        echo 'allowed_users=anybody' > /etc/X11/Xwrapper.config
        echo 'needs_root_rights=yes' >> /etc/X11/Xwrapper.config
    elif grep -Fxq "allowed_users=console" /etc/X11/Xwrapper.config; then
        print_step_header "Configure Xwrapper.config"
        sed -i "s/allowed_users=console/allowed_users=anybody/" /etc/X11/Xwrapper.config
        echo 'needs_root_rights=yes' >> /etc/X11/Xwrapper.config
    fi
    
    # Remove previous Xorg config
    rm -f /etc/X11/xorg.conf

    # Ensure the X socket path exists
    mkdir -p ${XORG_SOCKET_DIR:?}

    # Clear out old lock files
    display_file=${XORG_SOCKET_DIR}/X${DISPLAY#:}
    if [ -S ${display_file} ]; then
        print_step_header "Removing ${display_file} before starting"
        rm -f /tmp/.X${DISPLAY#:}-lock
        rm ${display_file}
    fi

    # Ensure X-windows session path is owned by root 
    mkdir -p /tmp/.ICE-unix
    chown root:root /tmp/.ICE-unix/
    chmod 1777 /tmp/.ICE-unix/

    # Check if this container is being run as a secondary instance
    if ([ "${MODE}" = "p" ] || [ "${MODE}" = "primary" ]); then
        print_step_header "Configure container as primary the X server"
        # Enable supervisord script
        sed -i 's|^autostart.*=.*$|autostart=true|' /app/conf.d/xorg.conf
    fi

    # Enable KB/Mouse input capture with Xorg if configured
    if [ "${ENABLE_EVDEV_INPUTS:-}" = "true" ]; then
        print_step_header "Enabling evdev input class on pointers, keyboards, touchpads, touch screens, etc."
        cp -f /usr/share/X11/xorg.conf.d/10-evdev.conf /etc/X11/xorg.conf.d/10-evdev.conf
    else
        print_step_header "Leaving evdev inputs disabled"
    fi
}

if ([ "${MODE}" != "s" ] && [ "${MODE}" != "secondary" ]); then
    if [[ -z ${nvidia_gpu_hex_id} ]]; then
        print_header "Generate default xorg.conf"
        configure_x_server
    else
        print_header "Generate NVIDIA xorg.conf"
        configure_x_server
        configure_nvidia_x_server
    fi
fi

echo -e "\e[34mDONE\e[0m"

print_header "Configure Sunshine"

if ([ "${MODE}" != "s" ] && [ "${MODE}" != "secondary" ]); then
    if [ "${ENABLE_SUNSHINE:-}" = "true" ]; then
        print_step_header "Enable Sunshine server"
        sed -i 's|^autostart.*=.*$|autostart=true|' /app/conf.d/sunshine.conf
    else
        print_step_header "Disable Sunshine server"
    fi
else
    print_step_header "Sunshine server not available when container is run in 'secondary' mode"
fi

echo -e "\e[34mDONE\e[0m"