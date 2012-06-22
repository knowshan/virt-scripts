#!/usr/bin/env ruby

# Module to check if OpenNebula environment is properly configured
# Instead of repeating these steps in every script, I think it's better to
# write them in a module

# 'require' this file in other OpenNebula scripts to check environment setup

module OneEnvironment
  
  # Checks if all files in given file array are readable
  # Returns false unless ALL files are readable - checks effective UID
  # Note: Ruby 1.9 has all? method which returns true if every block element
  # passes the boolean test
  def self.files_readable?(files)
    files.each do |f|
      return false unless File.readable?(f)
    end
    return true
  end
  
  # Returns array of readable files from the given file array
  def self.readable_files(files)
    readables = files.select do |f|
      File.readable?(f)
    end
    return readables
  end

  # Returns array of unreadable files from the given file array
  def self.unreadable_files(files)
    files.reject! do |f|
      File.readable?(f)
    end
    return files
  end
  
  # Check if given environment variable is set
  # Return false unless ALL files are present
  def self.env_configured?(oneenvs)
    undef_oneenvs = oneenvs.select do |oneenv|
      ENV[oneenv].nil?
    end
    if undef_oneenvs.empty?
      true
    else
      puts "Following OpenNebula environment variables are required to run this:"
      undef_oneenvs.each { |undef_oneenv| puts undef_oneenv }
      exit 1
    end
  end
  
end

# Main code
## Ensure env vars are configured
one_envs = ['ONE_AUTH','ONE_XMLRPC']
OneEnvironment.env_configured?(one_envs)

## Ensure file pointed by ONE_AUTH is readable 
if ! OneEnvironment.files_readable?(ENV['ONE_AUTH'])
  puts "ONE_AUTH file #{ENV['ONE_AUTH']} is not readable"
  exit 1
end
