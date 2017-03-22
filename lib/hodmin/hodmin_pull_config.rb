# pullCF reads Homie-device config-data via mqtt-protocol.
# Output-format is YAML
def hodmin_pull_config(gopts, copts)
  my_devs = fetch_homie_dev_list.select_by_opts(gopts)

  my_devs.each do |pull_dev|
    if copts[:outputfile_given]
      filename = pull_dev.config_yaml_filename_homie(copts[:outputfile])
      File.open(filename, 'w') do |f|
        f.puts "# YAML Configfile written by hodmin Version #{configatron.VERSION}"
        f.puts "# MAC: #{pull_dev.mac}"
        f.puts "# Status during pullCF: #{pull_dev.online_status}"
        f.puts "# #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
        f.puts pull_dev.implementation_config.config_from_string
      end
    else
      puts "Config of device #{pull_dev.name} (#{pull_dev.mac}):"
      puts pull_dev.implementation_config.config_from_string
    end
  end
end

# Converts string with config-Data (json-format) to nice output.
class String
  def config_from_string
    return '' if strip.empty?
    JSON.parse(self).to_yaml
  end
end

# Create filename for config-data of a HomieDevice depending on default pattern
# (Homie-<MAC>.yaml) or a given parameter replacing 'Homie'.
class HomieDevice
  def config_yaml_filename_homie(fn)
    config_extension = '.yaml'
    if fn.include?('<MAC>')
      fn.gsub(/<MAC>/, mac) + config_extension
    else
      fn.gsub(/[^A-Za-z0-9]/, '') + '-' + mac + config_extension
    end
  end
end
