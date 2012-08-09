#!/usr/bin/env ruby

# Quick HowTo:
# 1. Make sure you have all the necessary files in virt-scripts repo and not
#  just this script.
# 2. Install required gems using Gemfile (Optional: Use rvm and bundler to
#  manage gem environment.
# 3. Make sure you have access - connectivity and authorization - to OpenNebula
#  server host and KVM host. You should have SSH key based auth setup with KVM
#  host as libvirt connection will be qemu+ssh.
# 4. Run 'oneimager.rb -h' to get help on the script


# Added kernel method using which can be used to carry out
# libvirt actions 'using' passed connection object and action block
# using - ensures that libvirt connection is closed
# Alternatively, I could have added connection close after every
# libvirt action. But this becomes complicated, rather, difficult to remember
# with conditional actions. Hence, I am using 'using'.
# TODO: fail/exit gracefully if no action block is given
module Kernel
  def using(connection_resource)
    begin
      yield
    ensure
      connection_resource.close
    end
  end
end

require 'rubygems'
# Load dependency Ruby gems
gem_req = {'libvirt' => 'creating VM domain','nokogiri' => 'XML formatting', 'oca' => 'OpenNebula actions'}
gem_req.each do |g,u|
  begin
    require g
  rescue Exception => e
    puts "This script requires #{g} gem."
    puts "The #{g} gem is used for #{u}"
    puts "Install all gems listed in the Gemfile"
    exit 1
  end
end
# Load external scripts
# DomainStruct - used to create domain xml
# TODO: exception handling isn't working well
script_req = ['DomainStruct']
script_req.each do |s|
  begin
    require 'DomainStruct'
  rescue Exception => e
    puts "This script requires external script #{s}."
    puts "You can download all required scripts from github repo:"
    exit
  end
end
# option parsing
require 'optparse'
require 'ostruct'

class OneImager
  @@VERSION = '1.0.0'
  attr_reader :options
  def initialize(arguments)
    @arguments = arguments
    @options = OpenStruct.new
    @options.help = false
    @options.name = nil
    @options.server = 'localhost'
    @options.memory = '1048576'
    @options.vncport = '-1'
    ip = '172.20.100.22'
    netmask = '255.255.0.0'
    gateway = '172.20.0.1'
    nameserver = '172.20.0.5'
    install_tree = 'http://172.20.0.5/repo/centos/6/os/x86_64'
    ksurl = 'http://172.20.0.103:10007/atlab/kickstart/rcs-el6/postgresql-centos6.cfg'
    @options.extraargs = "method=#{install_tree} ks=#{ksurl} ksdevice=eth0 ip=#{ip} netmask=#{netmask} gateway=#{gateway} nameserver=#{nameserver}"
    @options.transient = false
  end

  def parsed_options?
    mem_regex = /\d+([mMgG]|$)/
    @optionparser_obj = OptionParser.new do |opts|
      opts.on('-h', '--help', 'Display Help') { @options.help = true }
      opts.on('-n', '--name NAME', 'Domain name') { |v| @options.name = v }
      opts.on('-d', '--disk DISK', 'VM disk path  (Optional, Default: /lustre/scratch/pavgi/vmimages/<name>.disk)') {|v| @options.disk = v }
      opts.on('-m', '--memory MEMORY', mem_regex, "Memory for both currentMemory and maxMemory of the domain Numeric m|M|g|G  (Optional, Default: #{@options.memory})") { |v| @options.memory = v }
      opts.on('-v', '--vncport VNCPORT', "VNC port number for the domain  (Optional, Default: #{@options.vncport}") { |v| @options.vncport = v }
      opts.on('-s', '--server SERVER', "Cloud server hostname  (Optional, Default: #{@options.server})") { |v| @options.server = v }
      opts.on('-x', '--extra-args EXTRAARGS', "Extra kernel arguments  (Optional, Default: #{@options.extraargs})") {|v| @options.extraargs = v }
      opts.on('-t', '--transient', 'Transient or persistent domain,  (Optional, Default: false)') { @options.transient = true }
      opts.on('-i', '--image-description IMGDESC', 'Image description') { |v| @options.desc = v }
    end
    begin
      @optionparser_obj.parse!(@arguments)
    rescue OptionParser::InvalidOption => e
      puts e
      puts "See help using #{$0} -h"
      exit 1
    rescue OptionParser::MissingArgument => e
      puts e
      puts "See help using #{$0} -h"
      exit 1
    rescue OptionParser::InvalidArgument => e
      puts e
      puts "See help using #{$0} -h"
      exit 1
    end
    process_validate_options
    true
  end

  def process_validate_options
    output_help if @options.help
    @name = @options.name
    @server = @options.server

    # Memory option validation
    case @options.memory
      when /\d+[m|M]/
        @memory = @options.memory.to_i * 1024
      when /\d+[g|G]/
        @memory = @options.memory.to_i * 1024 * 1024
      when /\d+$/
        @memory = @options.memory.to_i
      else
        puts "Unexpected pattern!"
    end

    @vncport = @options.vncport
    # default for disk can't be added during initialize as at that time @options.name is not set
    # TODO: ^^ Hence, need to revise this pattern - use trollop??
    @disk = @options.disk.nil? ? "/lustre/scratch/pavgi/vmimages/#{@name}.disk" : @options.disk
    @extraargs = @options.extraargs
    @transient = @options.transient
    @desc = @options.desc
    # if image desc is provided then try registering the disk in OpenNebula
    # so this options serves two things at the moment - provides image desc and image registration trigger
    # @desc = @options.desc.nil? ? "#{@name} image" : @options.desc
  end

  def output_help
    puts "HELP"
    puts "Script to create VM!"
    puts @optionparser_obj
    exit
  end

  # Create raw disk image using qemu-img
  # TODO: what if file already exists??
  def create_raw_disk
    cmd = "qemu-img create #{@disk} 40G"
    puts "Creating disk image using qemu-img:"
    puts cmd
    `#{cmd}`
    File.chmod(0660,@disk)
  end

  def process_command
    # puts @name,@memory
    d = DomainStruct.new(@name,@memory,@disk,@vncport,@extraargs)
    dxml = d.to_xml
    puts dxml
    # create libvirt connection
    begin
      conn = Libvirt::open("qemu+ssh://#{@server}/system")
    rescue Exception => e
      puts "Error connecting to the #{@server}"
      puts e
    end
    # end of libvirt connection
    # connection available for use
    # hence using conn block starts
    using (conn) do
      # check if domain already exists
      begin
        conn.lookup_domain_by_name @name
      # here exception means domain doesn't exist yet and hence call
      # further actions
      rescue Exception => e
        # create raw disk
        create_raw_disk
        # if transient then create a domain without defining it
        if @transient
          begin
	    @dobj = conn.create_domain_xml(dxml)
	  rescue Exception => e
	    puts "Failed to create a domain."
	    puts e
	  else
	    # if desc was not nil then register the image
            if @desc.nil?
              # provide VM details and exit
              puts '****** Domain state information ******'
              puts "Domain #{@dobj.name} is active on #{@server}" if @dobj.active?
	    else
              opennebula_register
	    end
	  end
        else
          begin
	    @dobj = conn.define_domain_xml(dxml)
	    #### @dobj.create
	  rescue Exception => e
	    puts "Failed to create a domain."
	    puts e
	  else
	    # if desc was not nil then register the image
            if @desc.nil?
              # provide VM details and exit
              puts '****** Domain state information ******'
              puts "Domain #{@dobj.name} is active on #{@server}" if @dobj.active?
	    else
              opennebula_register
	    end
	  end
        end
        # end-if transient/persistent domain actions
      else
        # if no error is received - which means domain exists
	# hence exit of the loop
	puts "A domain by name #{@name} already exists on the #{@server}"
	exit
      end
    end
  end

  def opennebula_register
    # wait till VM is undefined/safe-for-one-registration
    # TODO - make sleep time user configurable??
    sleep_time = 6
    interval_time = 3
    while sleep_time > 0
      puts "Next domain status check will be done after #{sleep_time} seconds"
      sleep interval_time
      sleep_time-=interval_time
    end
    # Image registration takes place only after VM is shutdown and remove
    # from the KVM host. The later step isn't really required, but usually
    # we don't any such VM copies on the host.
    # Hence create transient VMs (-t flag) and power-off VMs in the kickstart
    # if you plan to register them in opennebula after creation.
    while exists? do
      puts "Domain #{@dobj.name} is still active on the #{@server}. It needs to be undefined for OpenNebula image registration"
      sleep 2
    end
    puts "Domain #{@dobj.name} is now undefined on the #{@server}."
    puts "Starting with #{@disk} image registration in OpenNebula"
img_template = <<EOF
NAME = "#{@name}"
PATH = "#{@disk}"
TYPE = "OS"
PUBLIC = YES
DESCRIPTION = "#{@desc}"
EOF
    puts "Registering image template:"
    puts img_template
    client = OpenNebula::Client.new
    image = OpenNebula::Image.new(OpenNebula::Image.build_xml,client)
    image.allocate(img_template)
    puts 'closed' if conn.closed?
  end

  def exists?
    begin
      @dobj.info.state
    rescue => e
      # puts e
      false
    else
      true
    end
  end

  def run
    if parsed_options?
      process_command
    else
      puts 'Unknown error... No donuts for you!'
      exit 1
    end
  end

end

oneimager = OneImager.new(ARGV)
oneimager.run
