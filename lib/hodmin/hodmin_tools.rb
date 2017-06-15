# Defines a comfortable way to use logging.
class Log
  def self.log
    if @logger.nil?
      log = case configatron.logging.logdestination
            when 'STDOUT' then STDOUT
            when 'nil' then nil
            else configatron.logging.logdestination.to_s
            end
      @logger = Logger.new(log)
      @logger.level = Logger::DEBUG
      @logger.datetime_format = '%Y-%m-%d %H:%M:%S '
    end
    @logger
  end
end

# Defines a class for storing all attributes of a Homie-firmware.
# Check kind of esp8266-firmware: Homie (>= V.2.0 because of magic bytes)
# Homie: see https://github.com/marvinroger/homie-esp8266
# Returns hash with fw-details if <filename> includes magic bytes,
# returns empty hash if doesn't
class FirmwareHomie < File
  attr_reader :checksum, :fw_name, :fw_version, :fw_brand, :file_path

  # Initialize a firmware-file for Homie-device. File is recognized by so called Homie-patterns (strings
  # in binary file) that can be injected through sourcecode.
  # Possible patterns are firmware-name, firmware-version and firmware-brand.
  def initialize(filename)
    @firmware_homie = false
    return unless homie_firmware?(filename)
    @file_path = filename
    @firmware_homie = true
    binfile = IO.binread(filename)
    @checksum = Digest::MD5.hexdigest(binfile)
    binfile = binfile.unpack('H*').first

    fw_name_pattern    = ["\xbf\x84\xe4\x13\x54".unpack('H*').first, "\x93\x44\x6b\xa7\x75".unpack('H*').first]
    fw_version_pattern = ["\x6a\x3f\x3e\x0e\xe1".unpack('H*').first, "\xb0\x30\x48\xd4\x1a".unpack('H*').first]
    fw_brand_pattern   = ["\xfb\x2a\xf5\x68\xc0".unpack('H*').first, "\x6e\x2f\x0f\xeb\x2d".unpack('H*').first]

    @fw_brand = @fw_name = @fw_version = '<none>'
    # find Firmware-Branding
    @fw_brand = fw_brand_pattern.find_pattern(binfile)
    # find Firmware-Name:
    @fw_name = fw_name_pattern.find_pattern(binfile)
    # find Firmware-Version:
    @fw_version = fw_version_pattern.find_pattern(binfile)
    Log.log.info "FW found: #{@fw_name}, #{@fw_version}, #{@checksum}"
  end

  def homie?
    @firmware_homie
  end
end

# Searches inside binfile for Homie-patterns and returns a string with
# firmware-brand, name or version.
class Array
  def find_pattern(binfile)
    result = ''
    if binfile.include?(first)
      result = binfile.split(first)[1].split(last).first.to_s
      result = [result].pack('H*') unless result.empty?
    end
    result
  end
end

# Searches within a binaryfile for so called Homie-magic-bytes to detect
# a Homie-firmware.
# See https://homie-esp8266.readme.io/v2.0.0/docs/magic-bytes
def homie_firmware?(filename)
  # returns TRUE, if Homiepattern is found inside binary
  binfile = IO.binread(filename).unpack('H*').first
  homie_pattern = "\x25\x48\x4f\x4d\x49\x45\x5f\x45\x53\x50\x38\x32\x36\x36\x5f\x46\x57\x25".unpack('H*').first
  binfile.include?(homie_pattern)
end

# Methods connects to a MQTT-broker and returns an object linking to this connection.
def mqtt_connect
  # establish connection for publishing, return client-object
  credentials = configatron.mqtt.auth ? configatron.mqtt.user + ':' + configatron.mqtt.password + '@' : ''
  connection = configatron.mqtt.protocol + credentials + configatron.mqtt.host
  begin
    MQTT::Client.connect(connection, configatron.mqtt.port)
  rescue MQTT::ProtocolException
    puts "ERR: Username and / or password wrong?\n#{connection} at port #{configatron.mqtt.port}"
    exit
  end
end

# Defines a class for storing all attributes of a Homie-device (aka ESP8266 with
# Homie-Firmware 2.0 (see: https://github.com/marvinroger/homie).
class HomieDevice
  attr_reader :mac, :checksum, :fw_brand, :fw_name, :fw_version, :upgradable
  def initialize(mqtt, *fw_list)
    fw_list.flatten!
    startseq = mqtt.select { |t, _m| t.include?('/$homie') }.first.first.split('$').first
    @mac = startseq.split(/\//).last
    mqtt.map! { |t, m| [t.gsub(startseq, ''), m] }
    mhash = Hash[*mqtt.flatten]
    create_attr('homieVersion', mhash['$homie'])
    if mhash['$homie'] > configatron.MAX_HOMIEVERSION
      Log.log.warn "Device #{mac}: Detected new Homie-version (#{mhash['$homie']})"\
      + ' check hodmin for updates'
    end
    mhash.tap { |hs| hs.delete('$homie') }
    # Some topics-names from homie do not fit our needs due to special chars like '/'.
    # ['$fw/name','$fw/version','$fw/checksum']
    # Replace '/' by '_':
    mhash.each { |k, v| create_attr(k.to_s.delete('$').gsub(/\//, '_').tr('-', '_'), v) }

    # mac only downcase and without separating ':'
    @mac = mac.delete(':').downcase

    # for selecting purposes we need some of our topics in different varnames:
    @checksum = @fw_checksum
    # do we find a higher version of this firmware than installed one?
    @upgradable = fw_list.empty? ? false : upgradable?(fw_name, fw_version, fw_list)
    Log.log.info "Homie-Device detected: mac=#{@mac}, #{online_status}, " \
      + " running #{fw_name}, #{fw_version}, upgr=#{upgradable}"
  end

  # Helper to create instance variables on the fly:
  def create_method(name, &block)
    self.class.send(:define_method, name, &block)
  end

  # Helper to remove some special chars from string to avoid problems in instance_variable_set:
  def remove_special_chars(str)
    to_be_replaced = ['%', '!', '(', ')', '&', '?', ',', '.', ':', '^', ' ']
    to_be_replaced.each{|char| str.gsub!(char,'')}
    str
  end
  
  # Helper to create instance variables on the fly:
  def create_attr(name, value)
    # replace chars
    name = remove_special_chars(name)
    create_method(name.to_sym) { instance_variable_get('@' + name) }
    instance_variable_set('@' + name, value)
  end

  # Helper to determine status of a device (online/offline). Checks it via reading the online-topic
  # of device at time of creating this object.
  # WARNING: If you use this in a longer running program, this info may be outdated.
  # In this case you should create a method that establishes a connection to your broker and
  # reads the online-topic of this device during execution time.
  def online?
    online.casecmp('true').zero?
  end

  # Helper to create a string containing ONLINE or OFFLINE. Gets it via reading the online-topic
  # of the device at time of creating this object.
  # WARNING: If you use this in a longer running program, this info may be outdated.
  # In this case you should create a method that establishes a connection to your broker and
  # reads the online-topic of this device during execution time.
  def online_status
    online? ? 'ONLINE' : 'OFFLINE'
  end

  # Helper to push a firmware-file vai MQTT to our Homie-Device.
  def push_firmware_to_dev(new_firmware)
    bin_file = File.read(new_firmware.file_path)
    md5_bin_file = Digest::MD5.hexdigest(bin_file)
    base_topic = configatron.mqtt.base_topic + mac + '/'
    client = mqtt_connect
    sended = FALSE
    client.publish(base_topic + '$implementation/ota/checksum', md5_bin_file, retain = false)
    sleep 0.1
    client.subscribe(base_topic + '$implementation/ota/status')
    cursor = TTY::Cursor
    puts ' '
    client.get do |_topic, message|
      ms = message
      ms = message.split(/ /).first.strip if message.include?(' ')
      if ms == '206'
        now, ges = message.split(/ /).last.strip.split(/\//).map(&:to_i)
        actual = (now / ges.to_f * 100).round(0)
        print cursor.column(1)
        print "Pushing firmware, #{actual}% done"
      end
      if ms == '304'
        puts '304, file already installed. No action needed. ' + message
        break
      end
      if ms == '403'
        puts '403, OTA disabled:' + message
        break
      end
      if ms == '400'
        puts '400, Bad checksum:' + message
        break
      end
      if ms == '202'
        puts '202, pushing file'
        client.publish(base_topic + '$implementation/ota/firmware', bin_file, retain = false)
        sended = TRUE
      end
      if ms == '200' && sended
        puts "\nFile-md5=#{md5_bin_file} installed, device #{name} is rebooting"
        break
      end
    end
  end
end

# Class represents a pair of a Homie-Device and a firmware running on this device
class HomiePair
  attr_reader :hdev, :hfw
  def initialize(dev, *fw)
    fw.flatten!
    @hdev = dev.nil? ? nil : dev
    @hfw  = fw.empty? ? nil : fw.first
  end
end

# Reads all Homie-Devices from given broker.
# To be called with connected MQTT-client. Topic has to be set in calling program.
# Variable timeout_seconds defines, after what time out client.get will be cancelled. Choose
# a value high enough for your data, but fast enough for quick response. default is 0.7 sec,
# which should be enough for a lot of Homies controlled by a broker running on a Raspberry-PI.
def get_homies(client, *fw_list)
  allmqtt = []
  begin
    Timeout.timeout(configatron.mqtt.timeout.to_f) do
      client.get { |topic, message| allmqtt << [topic, message] }
    end
  # we want to read all published messages right now and then leave (otherwise we are blocked)
  rescue Timeout::Error
  end
  # find all homie-IDs (MAC-addresses)
  macs = allmqtt.select { |t, _m| t.include?('/$homie') }.map { |t, _m| t.split('/$').first.split('/').last }
  # create a array of homie-devices for macs in our list:
  homies = []
  macs.each do |mac|
    mqtt = allmqtt.select { |t, _m| t.include?(mac) }
    homies << HomieDevice.new(mqtt, fw_list)
  end
  homies
end

# Return a list of Homie-Devices controlled by given broker.
def fetch_homie_dev_list(*fw_list)
  client = mqtt_connect
  base_topic = configatron.mqtt.base_topic + '#'
  client.subscribe(base_topic)
  list = get_homies(client, fw_list)
  client.disconnect
  list
end

# Return a list of Homie-firmwares found in given diretory-tree. Firmwares are identfied
# by Magic-byte (see https://homie-esp8266.readme.io/v2.0.0/docs/magic-bytes). Filenames
# are ignored, you can specify a pattern in hodmin-config to speed up searching.
# Default filename-pattern is '*.bin'
def fetch_homie_fw_list
  directory = configatron.firmware.dir + '**/' + configatron.firmware.filepattern
  Log.log.info "Scanning dir: #{directory}"
  binlist = Dir[directory]
  fw_list = []
  binlist.each do |fw|
    fw_list << FirmwareHomie.new(fw) if homie_firmware?(fw)
  end
  fw_list
end

# Extends Array class with some specific selection-methods for devices and firmware
class Array
  # Selects Array of HomieDevices or firmwares based on options
  def select_by_opts(options)
    this_object = first.class == HomieDevice ? 'HD' : 'FW'

    # Options valid for selecting Homie-Devices OR for firmwares
    valid_dev_options =
      this_object == 'HD' ? [:mac, :fw_name, :checksum, :localip] : [:checksum, :fw_name, :config]

    # use only valid options:
    my_opts = options.select { |k, _v| valid_dev_options.include?(k) }

    # remove all options not used as CLI argument:
    my_opts = my_opts.select { |_k, v| !v.to_s.empty? }
    return self if my_opts.empty? # no options set, so all devices are selected

    my_devs = self
    # selects objects (devices or firmwares) from an array due to a filter defined by key-value-pair
    # Example: [:checksum => 'c79*']
    my_opts.each_pair do |k, v|
      # puts "looking for #{k} = #{v}"
      my_devs = my_devs.select { |h| SelectObject.new(v) =~ h.instance_variable_get("@#{k}") }
    end
    my_devs
  end

  # Creates an array of rows with desired output from HomiePair-objects.
  def create_output_table(attribs, _style)
    pastel = Pastel.new
    empty_field = ' '
    empty_field = configatron.output.nil.strip unless configatron.output.nil? || configatron.output.nil.nil?
    empty_field = pastel.dim(empty_field) # dim this message
    rows = []
    each do |r|
      row = []
      # color for checksum if applicable:
      checksum_color = if r.hdev.nil?
                         'none'
                       else
                         r.hdev.upgradable ? 'yellow' : 'green'
                       end
      attribs.each do |a|
        row << case a.slice(0, 2)
               when 'HD' then
                 var_name = a.gsub(/HD./, '')
                 var = r.hdev.nil? ? empty_field : r.hdev.instance_variable_get("@#{a.gsub(/HD./, '')}")
                 case var_name
                 when 'online'
                   var = pastel.green(var) if var == 'true'
                   var = pastel.red(var) if var == 'false'
                   var if var != 'true' && var != 'false'
                 else
                   var = var.nil? ? empty_field : var
                 end
               when 'FW' then
                 if r.hfw.nil?
                   empty_field
                 else
                   var_name = a.gsub(/FW./, '')
                   var = r.hfw.instance_variable_get("@#{var_name}")
                   case var_name
                   when 'checksum'
                     case checksum_color
                     when 'none' then var
                     when 'green' then pastel.green(var)
                     when 'yellow' then pastel.yellow(var)
                     end
                   else
                     var.nil? ? empty_field : var
                   end
                 end
               when 'AD' then
                 var = r.instance_variable_get("@#{a.gsub(/AD./, '')}")
                 var.nil? ? empty_field : var
               end
      end
      rows << row
    end
    rows
  end
end

# Check a firmware against available bin-files of Homie-firmwares.
# Returns true, if there is a higher Version than installed.
# Returns false, if there is no suitable firmware-file found or installed version is the
# highest version found.
def upgradable?(fw_name, fw_version, fw_list)
  fw_list.flatten!
  # select highest Version of fw_name from given firmware_list:
  return false if fw_list.empty? # No entries in Softwarelist
  best_version = fw_list.select { |h| h.fw_name == fw_name }\
                        .sort_by(&:fw_version).last
  best_version.nil? ? false : fw_version < best_version.fw_version
end

# Special class to select a string via Regex. Needed for flexible search for MAC,
# firmware-name and so on. Helper to construct a Regex.
class SelectObject
  def self.string_to_regex(var)
    Regexp.new "^#{Regexp.escape(var).gsub('\*', '.*?')}$"
  end

  # Helper
  def initialize(var)
    @regex = self.class.string_to_regex(var)
  end

  # Helper
  def =~(other)
    !!(other =~ @regex)
  end
end

# Extends String-class with the ability to check whether JSON-items with Hodmin-CFG-data
# within self-string includes given string. Compares two strings as Hashes: if key/values
# from str are included in self: TRUE, otherwise FALSE
class String
  def include_cfg?(str)
    return false if self == '' || str == ''
    h1 = JSON.parse(self)
    h2 = JSON.parse(str)
    (h2.to_a - h1.to_a).empty?
  end
end

# Checks Hash with config-data
def check_config_ok?(config, configfile)
  status_ok = true
  if config['mqtt']['host'] == 'mqtt.example.com'
    puts "ERR: No valid config-file found.\nPlease edit config file: #{configfile}."
    status_ok = false
  end

  if !config['mqtt']['base_topic'].empty? && config['mqtt']['base_topic'].split(//).last != '/'
    puts "ERR: mqtt: base_topic MUST end with '/'. Base_topic given: #{config['mqtt']['base_topic']}"
    status_ok = false
  end
  status_ok
end

# Returns Hash with default config-data for Hodmin. File MUST be edited after creation by user.
def default_config
  config = {}
  config['mqtt'] = Hash['protocol' => 'mqtt://', 'host' => 'mqtt.example.com', 'port' => '1883',\
                        'user' => 'username', 'password' => 'password', 'base_topic' => 'devices/homie/',\
                        'auth' => true, 'timeout' => 0.3]
  config['firmware'] = Hash['dir' => '/home/user/sketchbook/', 'filepattern' => '*.bin']
  config['logging'] = Hash['logdestination' => 'nil']
  config['output'] = Hash['list' => 'HD.mac HD.online HD.localip HD.name FW.checksum'\
                   + 'FW.fw_name FW.fw_version HD.upgradable', 'nil' => '']
  config
end

# Returns Hash with default config-data to initialize a Homie-device. File MUST be edited after creation by user.
def default_config_initialize
  config = {}
  config['name'] = 'Homie1234'
  config['wifi'] = Hash['ssid' => 'myWifi', 'password'=>'password']
  config['mqtt'] = Hash['host' => 'myhost.mydomain.local', 'port' => 1883, 'base_topic'=>'devices/homie/'\
           , 'auth'=>true, 'username'=>'user1', 'password' => 'mqttpassword']
  config['ota'] = Hash['enabled' => true]
  config
end
