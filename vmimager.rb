#!/usr/bin/env ruby

# == Synopsis 
# Script to create a VM using libvirt's direct kernel boot method.
#    
# == Examples
# ./vmimager.rb -n vm-name -s kvm-02 -p rcs -d vm-name.raw
#
# == Usage 
#   vmimager.rb [options]
#   For help use: vmimager.rb -h
#
# == TODO/Issues:
#
# == Author
#   Shantanu Pavgi, knowshantanu@gmail.com  

#!/usr/bin/env ruby

# Requirements:
# 1. DomainStruct module - used to create domain xml and available in the 
# repository along with this script.
#
# Quick HowTo:
# 1. Make sure script dependencies like DomainStruct are available in required
# library path.
# 2. Install required gems in Gemfile.
# 3. Configure password-less key-based SSH access to the KVM host
#  server host and KVM host. You should have SSH key based auth setup with KVM
# 4. Run 'vmimager.rb -h' to get help on the script


# Added kernel method using which can be used to carry out libvirt actions 
# 'using' passed connection object and action block. 
# using - ensures that libvirt connection is closed during block termination.
# It's easier than closing connection explicitly.
#
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
gem_req = {'libvirt' => 'creating VM domain','nokogiri' => 'XML formatting'}
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
script_req = {'DomainStruct' => 'https://github.com/knowshan/virt-scripts'}
script_req.each do |d,u|
  begin
    require File.join(File.dirname(__FILE__), d)
  rescue Exception => e
    puts "This script requires external script #{d}. It can be downloaded from: #{u}"
    exit
  end
end

# option parsing
require 'optparse'
require 'ostruct'

class VmImager
  @@VERSION = '1.0.0'
  attr_reader :options
  def initialize(arguments)
    @arguments = arguments
    @options = OpenStruct.new
    @options.help = false
    @options.name = nil
    @options.pool = 'rcs-virt-nfs3'
    @options.disk = nil
    @options.network = 'default'
    @options.disksize = '20'
    @options.server = 'localhost'
    @options.memory = '1048576'
    @options.vncport = '-1'
    install_tree = 'http://172.20.0.5/repo/centos/6/os/x86_64'
    ksurl = 'http://172.20.0.103:10007/atlab/kickstart/rcs-el6/postgresql-centos6.cfg'
    @options.extraargs = "method=#{install_tree} ks=#{ksurl} ksdevice=eth0"
    @options.transient = false
  end

  def parsed_options?
    mem_regex = /\d+([mMgG]|$)/
    @optionparser_obj = OptionParser.new do |opts|
      opts.on('-h', '--help', 'Display Help') { @options.help = true }
      opts.on('-n', '--name NAME', 'Domain name') { |v| @options.name = v }
      opts.on('-p', '--pool POOL', 'Storage Pool') { |v| @options.pool = v }
      opts.on('-d', '--disk DISK', 'VM disk name') {|v| @options.disk = v }
      opts.on('-m', '--memory MEMORY', mem_regex, "Memory for both currentMemory and maxMemory of the domain Numeric m|M|g|G  (Optional, Default: #{@options.memory})") { |v| @options.memory = v }
      opts.on('-n', '--network NETWORK', 'Network name (Optional, Default: default)') {|v| @options.network = v }
      opts.on('-b', '--disksize DISKSIZE', Integer, "Disk size in GB  (Optional, Default: #{@options.disksize})") { |v| @options.disksize = v }
      opts.on('-v', '--vncport VNCPORT', "VNC port number for the domain  (Optional, Default: #{@options.vncport}") { |v| @options.vncport = v }
      opts.on('-s', '--server SERVER', "Cloud server hostname  (Optional, Default: #{@options.server})") { |v| @options.server = v }
      opts.on('-x', '--extra-args EXTRAARGS', "Extra kernel arguments  (Optional, Default: #{@options.extraargs})") {|v| @options.extraargs = v }
      opts.on('-t', '--transient', 'Transient or persistent domain,  (Optional, Default: false)') { @options.transient = true }
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
    # Memory option validation
    case @options.memory
      when /\d+[m|M]/
        @options.memory = @options.memory.to_i * 1024
      when /\d+[g|G]/
        @options.memory = @options.memory.to_i * 1024 * 1024
      when /\d+$/
        @options.memory = @options.memory.to_i
      else
        puts "Unexpected pattern!"
    end

    # default for disk can't be added during initialize as at that time @options.name is not set
    # TODO: ^^ Hence, need to revise this pattern - use trollop??
  end

  def output_help
    puts "HELP"
    puts "Script to create VM!"
    puts @optionparser_obj
    exit
  end

  def process_command
    # create libvirt connection
    begin
      conn = Libvirt::open("qemu+ssh://#{@options.server}/system")
    rescue Exception => e
      puts "Error connecting to the #{@options.server}"
      puts e.message
      puts e.backtrace
      exit 1
    end # end of libvirt connection
    # if conn succeeds use it
    using (conn) do
      # check if domain already exists
      begin
        conn.lookup_domain_by_name @options.name
      # here exception means domain doesn't exist yet and hence call
      # further actions
      rescue Exception => e
        # Create storage volume
        begin
          pool = conn.lookup_storage_pool_by_name @options.pool
        rescue Libvirt::RetrieveError => e
          puts "Couldn't find storage pool #{@options.pool}"
          puts e.message
          puts e.backtrace
          exit 1
        else
          begin
            storage_vol_xml = <<EOF
            <volume>
              <name>#{@options.disk}</name>
              <allocation>0</allocation>
              <capacity unit="G">#{@options.disksize}</capacity>
            </volume>
EOF
            vol = pool.create_volume_xml storage_vol_xml
          rescue Libvirt::Error => e
            puts "Failed to create storage volume"
            puts e.message
            puts e.backtrace
          else
            puts @options.name
            diskpath = vol.path
            d = DomainStruct.new(@options.name,@options.memory,diskpath,@options.network,@options.vncport,@options.extraargs)
            dxml = d.to_xml
            puts dxml

            #start define domain
            begin
              if @options.transient
                @dobj = conn.create_domain_xml(dxml)
              else
                @dobj = conn.define_domain_xml(dxml)
                @dobj.create
                @dobj.
              end
            rescue Exception => e
              puts "Failed to create a domain."
              puts e.message
              puts e.backtrace
              exit 1
            else
              # provide VM details and exit
              puts '****** Domain state information ******'
              puts "Domain #{@dobj.name} is active on #{@server}" if @dobj.active?
            end
          end # end storage vol
        end # end storage pool
      else
        # if no error is received - which means domain exists
        # hence exit of the loop
        raise "A domain by name #{@options.name} already exists on the #{@options.server}"
        puts e
      end
    end
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

vmimager = VmImager.new(ARGV)
vmimager.run
