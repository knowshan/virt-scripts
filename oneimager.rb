#!/usr/bin/env ruby

require 'rubygems'
require 'libvirt'
require 'nokogiri'
require 'DomainStruct'
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
    @options.ip = '172.20.100.22'
    @options.gw = '172.20.0.5'
    @options.ksurl = 'http://172.20.0.103:10007/atlab/kickstart/rcs-el6/generic-server-centos6-ccts.cfg'
    @options.vmdisk = '/lustre/scratch/pavgi/testkvmperms/vmimages'
  end
  
  def parsed_options?
    @optionparser_obj = OptionParser.new do |opts|
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

    conn = Libvirt::open("qemu+ssh://#{@server}/system")
    # puts conn.closed?
    # puts @name,@memory
    conn.create_domain_xml(dxml)
    # conn.define_domain_xml(dxml)
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
