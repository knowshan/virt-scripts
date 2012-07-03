#!/usr/bin/env ruby

require 'rubygems'
require 'libvirt'
require 'nokogiri'
require 'DomainStruct'
require 'optparse'
require 'ostruct'
require 'oca'

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
    @options.ip = '172.20.100.22'
    @options.gw = '172.20.0.5'
    @options.ksurl = 'http://172.20.0.103:10007/atlab/kickstart/rcs-el6/generic-server-centos6-ccts.cfg'
    @options.vmdisk = '/lustre/scratch/pavgi/testkvmperms/vmimages'
  end
  
  def parsed_options?
    @optionparser_obj = OptionParser.new do |opts|
      # diskpath / vmdisk
      # ip
      # netmask
      # gw
      # ksurl
      # vmlinuz / kernel
      # initrd
      # oneuser
      # image_regi
      opts.on('-h', '--help', 'Display Help') { @options.help = true }
      opts.on('-n', '--name NAME', 'Domain name') { |v| @options.name = v }
      opts.on('-m', '--memory MEMORY', 'Memory') { |v| @options.memory = v }
      opts.on('-v', '--vncport VNCPORT', 'VNC port') { |v| @options.vncport = v }
      opts.on('-s', '--server SERVER', 'Cloud server hostname') { |v| @options.server = v }
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
    process_options
    true  
  end
  
  def process_options
    output_help if @options.help
    @name = @options.name
    @server = @options.server
    @memory = @options.memory
    @ip = @options.ip
    @gw = @options.gw
    @ksurl = @options.ksurl
    @vmdisk = @options.vmdisk
  end
  
  def output_help
    puts "HELP"
    puts "Script to create VM!"
    puts @optionparser_obj
    exit
  end
 
  def process_command
    # puts @name,@memory
    d = DomainStruct.new(@name,@memory,@vncport)
    dxml = d.to_xml
    puts dxml

    begin 
      @conn = Libvirt::open("qemu+ssh://#{@server}/system")
      @dobj = @conn.define_domain_xml(dxml)
      puts '****** active' if @dobj.active?
      puts '****** Domain info:'
      puts @dobj.info.state
      # dobj.undefine
      # puts '****** active' if dobj.active?
    rescue => e
      puts e
    else
      sleep_time=6
      interval_time=3
      while sleep_time>0
        puts "BRB in #{sleep_time} seconds"
        sleep interval_time
	sleep_time-=interval_time
      end
      while exists? do
        puts 'Domain exists'
	sleep 2
      end
      puts 'Domain undefined'
    ensure
      @conn.close
       img_template = <<EOF
NAME = "domain01"
PATH = "/lustre/scratch/pavgi/vmimages/domain01.disk"
TYPE = "OS"
PUBLIC = YES
DESCRIPTION = "domain01 image. Source - generic-server-centos6-ccts.cfg file, GirRev: atlab:56b6221"
IMGTYPE=ccts
EOF
    puts img_template
    client = OpenNebula::Client.new
    image = OpenNebula::Image.new(OpenNebula::Image.build_xml,client)
    end
    # puts conn.closed?
    # puts @name,@memory
    # dobj = conn.create_domain_xml(dxml)
    # while domain.active? do
    #   puts 'polling state'
    #   new_state = dobj
    # end
    
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
