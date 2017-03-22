# Initiate a Homie-Device with first config from a YAML-file.
# Uses bash CLI calling Curl-binary. Will not work, if curl is not available.
# Perhaps a better solution should use http-requests => to be done
# Status: experimental
def hodmin_initialize(gopts, copts)
  c1 = 'command -v curl >/dev/null 2>&1 || { echo  "curl required but it is not installed."; }'
  ip = '192.168.123.1'
  ans = `#{c1}`.to_s.strip
  if ans.empty?
    default_filename = 'homie-initialize.yaml'
    filename = copts[:configfile_given] ? copts[:configfile] : default_filename

    unless File.exists?(filename)
      puts "ERR: Configfile with initializing data not found: #{filename}"
      exit if filename != default_filename
      # create example config-file:
      File.open(filename, 'w') { |f| f.puts default_config_initialize.to_yaml }
      puts "WARN: Default initializing data written to: #{filename}. Please edit this file!"
      exit
    end
    
    # write config in JSON-Format to tempfile:
    tempfile = 'configHOMIEjson.tmp'
    File.open(tempfile,'w'){|f| f.puts YAML.load_file(filename).to_json}
    
    # upload to device:
    puts "trying to connect to #{ip} ..."
    c2 = "curl -X PUT http://#{ip}/config -d @#{tempfile} --header 'Content-Type: application/json'"
    ans = `#{c2}`.to_s
    json = JSON.parse(ans)
    if json['success']
      puts "\nDevice is initialized now."
    else
      puts "\nOops. Something went wrong: curl answered: #{ans}"
    end
    File.delete(tempfile)
  else
    # curl not installed
    puts 'ERR: curl required, but it is not installed. Aborting.'
    exit
  end
end
