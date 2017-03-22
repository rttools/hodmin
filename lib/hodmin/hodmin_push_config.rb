# Pushes a config to Homie-device via MQTT-Broker.
def hodmin_push_config(gopts, copts)
  conf_cmd  = copts[:jsonconfig] || ''
  conf_file = copts[:inputfile] || ''
  conf_short = copts[:shortconfig] || ''

  number_of_options = [:jsonconfig_given, :inputfile_given, :shortconfig_given]\
                      .count { |e| copts.keys.include?(e) }

  unless number_of_options == 1
    puts 'ERR: please specify exactly ONE option of: -s, -j, -i'
    return
  end

  if copts[:inputfile_given] && !File.exist?(conf_file)
    puts "ERR: File not found: #{conf_file}"
    return
  end

  conf_file = YAML.load_file(conf_file).to_json if copts[:inputfile_given]

  conf_new = conf_cmd if copts[:jsonconfig_given]
  conf_new = conf_file if copts[:inputfile_given]
  conf_new = options_long(conf_short) if copts[:shortconfig_given]

  if conf_new.empty?
    puts 'ERR: No valid config-options found.'
    return
  end

  my_devs = fetch_homie_dev_list.select_by_opts(gopts)

  my_devs.each do |up_dev|
    copts = get_config_from_option(conf_new)
    puts "Device #{up_dev.mac} is #{up_dev.online_status}"
    next unless up_dev.online?
    print 'Start updating? <Yn>:'
    answer = STDIN.gets.chomp.downcase
    next unless up_dev.online && 'y' == answer
    client = mqtt_connect
    base_topic = configatron.mqtt.base_topic + up_dev.mac + '/'
    client.subscribe(base_topic + '$implementation/config')
    conf_old = ''
    client.get do |_topic, message|
      # wait for next message in our queue:
      if conf_old == ''
        # first loop, store existing config to compare after update:
        conf_old = message # we do need message only
        client.publish(base_topic + '$implementation/config/set', copts.to_json, retain: false)
        puts 'done, device reboots, waiting for ACK...'
      else
        # we received a new config
        new_conf = message
        break if JSON.parse(new_conf).values_at(*copts.keys) == copts.values
      end
      puts "ACK received, device #{up_dev.mac} rebooted with new config."
    end
    client.disconnect
  end
end

def get_config_from_option(cline)
  # Example: cline = '{"ota":{"enabled":"true"}, "wifi":{"ssid":"abc", "password":"secret"}}'
  return '' if cline.to_s.strip.empty?
  JSON.parse(cline)
end

# Returns JSON-String with key-value pairs depending on input-string.
# Example: hodmin pushCF -s "name:test-esp8266 ota:on ssid:xy wifipw:xy host:xy port:xy
# base_topic:xy auth:off user:xy mqttpw:xy"
# Enclose multiple options in "", separate options with a blank
def options_long(short)
  list = short.split(/ /)
  cfg = { 'wifi' => {}, 'mqtt' => {} }
  list.each do |o|
    key, value = o.split(/:/).map(&:strip)
    case key.downcase
    when 'name' then cfg['name'] = value
    when 'ssid' then cfg['wifi'] = Hash['ssid' => value]
    when 'wifipw' then cfg['wifi'] = Hash['password' => value]
    when 'host' then cfg['mqtt'] << Hash['host' => value]
    when 'port' then cfg['mqtt'] << Hash['port' => value]
    when 'base_topic' then cfg['mqtt'] = Hash['base_topic' => value]
    when 'auth' then cfg['mqtt'] = cfg['mqtt'].merge(Hash['auth' => value == 'on' ? true : false])
    when 'user' then cfg['mqtt'] << Hash['username' => value]
    when 'mqttpw' then cfg['mqtt'] = cfg['mqtt'].merge(Hash['password' => value])
    when 'ota' then cfg['ota'] = Hash['enabled' => value == 'on' ? true : false]
    else
      puts "ERR: illegal option: #{key.downcase}"
      exit
    end
  end
  cfg = cfg.delete_if { |_k, v| v.nil? || v.empty? }
  puts "\nNew config will be: #{cfg.inspect}"
  cfg.to_json
end
