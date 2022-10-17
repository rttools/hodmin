# Uploads firmware to Homie-Device(s)
def hodmin_push_firmware(gopts, copts)
  fw_checksum = copts[:checksum] || ''
  fw_name = copts[:fw_name] || ''
  batchmode = copts[:auto] || false
  offlinemode = copts[:offline] || false
  mac = gopts[:mac] || ''
  hd_upgrade = gopts[:upgradable_given] && gopts[:upgradable]
  fw_upgrade = copts[:upgrade_given] && copts[:upgrade]

  gopts[:mac] = mac = '*' if hd_upgrade && gopts[:mac_given]

  if fw_checksum.empty? && fw_name.empty?
    puts "ERR: No valid firmware-referrer found. (Chksum:#{fw_checksum}, Name: #{fw_name})"
    return
  end
  unless (!fw_checksum.empty? && fw_name.empty?) || (fw_checksum.empty? && !fw_name.empty?)
    puts 'ERR: Please specify firmware either by checksum or by name (for newest of this name).'
    return
  end

  unless !mac.empty? || !fw_name.empty?
    puts 'ERR: No valid device specified.'
    return
  end

  # first find our firmware:
  my_fws = fetch_homie_fw_list.select_by_opts(copts)
                              .sort { |a, b| [a.fw_name, b.fw_version] <=> [b.fw_name, a.fw_version] }

  if my_fws.empty?
    puts 'ERR: None of available firmwares does match this pattern'
    return
  else
    if my_fws.size > 1 && !fw_upgrade
      puts 'ERR: Firmware specification is ambigous'
      return
    end
  end

  # only first firmware selected for pushing:
  my_fw = my_fws.first

  # now find our device(s)
  my_devs = fetch_homie_dev_list(my_fws).select_by_opts(gopts)

  return if my_devs.empty?

  my_devs.each do |up_dev|
    next if hd_upgrade && !up_dev.upgradable
    my_fw = my_fws.select { |f| f.fw_name == up_dev.fw_name }.sort_by(&:fw_version).last if hd_upgrade
    puts "Device #{up_dev.mac} is #{up_dev.online_status}. (installed FW-Checksum: #{up_dev.fw_checksum})"
    next unless (up_dev.online? || offlinemode) && up_dev.fw_checksum != my_fw.checksum
    if batchmode
      answer = 'y'
    else
      print "New firmware: #{my_fw.checksum}. Start pushing? <Yn>:"
      answer = STDIN.gets.chomp.downcase
    end
    Log.log.info "Dev. #{up_dev.mac} (running #{up_dev.fw_version}) upgrading to #{my_fw.fw_version}"
    up_dev.push_firmware_to_dev(my_fw, offlinemode) if 'y' == answer
  end
end
