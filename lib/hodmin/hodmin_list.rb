# Homie-Admin LIST
# Print list of Homie-Decices with installed firmware and available firmware in our repo
def hodmin_list(gopts, copts)
  all_fws = fetch_homie_fw_list # we need it for checking upgrade-availability
  my_fws = all_fws.select_by_opts(copts)\
                  .sort do |a, b|
                    [a.fw_brand, a.fw_name, b.fw_version] <=> \
                      [b.fw_brand, b.fw_name, a.fw_version]
                  end
                  
  # fetch all devices, set upgradable-attribute based on my_fws:
  my_devs = fetch_homie_dev_list(my_fws).select_by_opts(gopts)
  my_list = []
  already_listed = []

  my_devs.each do |d|
    firmware = my_fws.select { |f| f.checksum == d.fw_checksum }
    if firmware.count > 0
      # found installed firmware
      my_list << HomiePair.new(d, firmware)
      already_listed << firmware.first.checksum # remember this firmware as already listed
    else
      # did not find firmware-file installed on this device
      my_list << HomiePair.new(d, nil) unless gopts[:upgradable_given]
    end
  end

  # now append remaining firmwares (for which we did not find any Homie running this) to my_list:
  already_listed.uniq!
  my_fws.select { |f| !already_listed.include?(f.checksum) }.each { |f| my_list << HomiePair.new(nil, f) }

  # attributes of my_list we want to see in output:
  # HD: attributes coming from HomieDevice
  # FW: attributes coming from firmware-file
  # AD: additional attributes in HomiePair-class for special purposes
  # Read our format for table from config-file:
  attribs = configatron.output.list.strip.split(/ /) unless configatron.output.nil?
  
  # create output-table
  rows = my_list.create_output_table(attribs, copts[:style])
  # define a header for our output-table
  # header = attribs.map { |a| a.gsub(/HD./, '').gsub(/FW./, '').gsub(/AD./, '') }
  header = attribs.map(&:setup_header)
  # build table object:
  output = TTY::Table.new header, rows
  table_style = copts[:style_given] ? copts[:style].to_sym : :unicode # :ascii :basic
  
  # show our table:
  puts output.render(table_style, alignment: copts[:style] == 'basic' ? [:left] : [:center])
end

# Extends class String with methods for using Pastel-Methods
class String
  def setup_header
    pastel = Pastel.new
    case slice(0, 2)
    when 'HD' then pastel.white(gsub(/HD./, ''))
    when 'FW' then pastel.white(gsub(/FW./, ''))
    else gsub(/AD./, '')
    end
  end
end
