#!/usr/bin/env ruby

require 'rubygems'
require 'libvirt'
require 'nokogiri'

# This class/file is not intended for end-user usage, although nothing
# prevents such usage.
# Other end-user oriented scripting classes should instantiate DomainStruct
# object and get it's xml formatted output.

# The custom initialize method of DomainStruct strictly requires five arguments.
# I have defined custom initialize method which overrides Struct's initialize
# method so that some validation checks can be added later.
# If I hadn't implemented custom initialize method then DomainStruct Struct
# would not have had such strict number of args requirement. 
# So how do other classes know number of args required and their order:
# 1. look at the source
# 2. query the source - DomainStruct.members - returns Array of members
# Using #2 aproach other classes can pass arguments dynamically, however, that
# may not be a good solution.

DomainStruct = Struct.new(:name,:memory,:disk,:vncport,:os_cmdline) do
  # Ideally - I would like to pass initialize values as a Hash
  # :name => 'server-01', :memory => '1048576', ...
  # that will need more hacking and being aware of it's side-effects
  def initialize(name,memory,disk,vncport,os_cmdline)
    super(name,memory,disk,vncport,os_cmdline)
    raise ArgumentError.new("You need to provide at least domain name!") if self.name.nil?
    # Set defaults if not provided
    # We can/should run additional validation checks as well
    # memory shouldn't be more than 8G!
    self.disk = "/lustre/scratch/pavgi/vmimages/#{name}.disk" if self.disk.nil?
    self.memory = '1048576' if self.memory.nil?
    self.vncport = '-1' if self.vncport.nil?
    # self.os_cmdline = self.cmdline
  end

  # Return domain xml as a string
  def to_xml
    dxml = Nokogiri::XML::Builder.new do |xml|
      xml.domain('type' => 'kvm'){
        xml.name name
        xml.memory memory
        xml.currentMemory memory
        xml.vcpu 1
        xml.os {
          xml.type_('hvm', 'arch' => 'x86_64', 'machine' => 'rhel6.2.0')
	  xml.boot('dev' => 'hd')
	  xml.kernel "/share/repo/mirror/centos/6.2/os/x86_64/images/pxeboot/vmlinuz"
	  xml.initrd "/share/repo/mirror/centos/6.2/os/x86_64/images/pxeboot/initrd.img"
	  xml.cmdline os_cmdline
	  # "method=http://172.20.0.5/repo/centos/6/os/x86_64 ks=http://172.20.0.103:10007/atlab/kickstart/rcs-el6/postgresql-centos6.cfg ksdevice=eth0 ip=172.20.100.22 netmask=255.255.0.0 nameserver=172.20.0.5 gateway=172.20.0.1"
        }
	xml.features {
          xml.acpi
	  xml.apic
	  xml.pae
	}
	xml.clock 'offset' => 'utc'
	xml.on_poweroff 'destroy'
	xml.on_reboot 'restart'
	xml.on_crash 'restart'
	xml.devices {
	  xml.emulator '/usr/libexec/qemu-kvm'
	  xml.disk('type' => 'file', 'device' => 'disk') {
            xml.driver('name' => 'qemu', 'type' => 'raw', 'cache' => 'none')
	    xml.source('file' => disk)
	    xml.target('dev' => 'hda', 'bus' => 'virtio')
	    # libvirt can auto-generate pci address space
	    # xml.address('type' => 'pci', 'domain' => '0x0000', 'bus' => '0x00', 'slot' => '0x04', 'function' => '0x0')
	  }
	  xml.interface('type' => 'bridge'){
	    xml.source('bridge' => 'br1')
	    xml.model('type' => 'virtio')
	    # xml.address('type' => 'pci', 'domain' => '0x0000', 'bus' => '0x00', 'slot' => '0x03', 'function' => '0x0')
	  }
	  xml.serial('type' => 'pty'){
            xml.target('port' => '0')
	  }
	  xml.console('type' => 'pty'){
            xml.target('type' => 'serial', 'port' => '0') 
	  }
	  xml.input('type' => 'tablet', 'bus' => 'usb')
	  xml.input('type' => 'mouse', 'bus' => 'ps2')
	  xml.graphics('type' => 'vnc', 'port' => '-1', 'autoport' => 'yes', 'keymap' => 'en-us')
	  xml.video {
	    xml.model('type' => 'cirrus', 'vram' => '9216', 'heads' => '1')
	    # xml.address('type' => 'pci', 'domain' => '0x0000', 'bus' => '0x00', 'slot' => '0x02', 'function' => '0x0')
	  }
	  xml.memballoon('model' => 'virtio'){
	    # xml.address('type' => 'pci', 'domain' => '0x0000', 'bus' => '0x00', 'slot' => '0x05', 'function' => '0x0')
          }
        }
      }
    end
    dxml.to_xml
  end
end

# d = DomainStruct.new('myserver','2000000','')
# puts d.name

