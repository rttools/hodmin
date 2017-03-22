def hodmin_remove(copts)
  fw_checksum = copts[:checksum] || ''
  fw_name = copts[:fw_name] || ''

  if fw_checksum.empty? && fw_name.empty?
    puts "ERR: No valid firmware-referrer found. (Chksum:#{fw_checksum}, Name: #{fw_name})"
    return
  end
  unless (!fw_checksum.empty? && fw_name.empty?) || (fw_checksum.empty? && !fw_name.empty?)
    puts 'ERR: Please specify firmware either by checksum or by name (for newest of this name).'
    return
  end

  # first find our firmware-files:
  my_fws = fetch_homie_fw_list.select_by_opts(copts)
                              .sort { |a, b| [a.fw_name, b.fw_version] <=> [b.fw_name, a.fw_version] }

  if my_fws.empty?
    puts 'ERR: None of available firmwares does match this pattern'
    return
  else
    my_fws.each do |f|
      puts "found Fw: Name: #{f.fw_name}, Version: #{f.fw_version}, MD5: #{f.checksum}"
    end
  end

  my_fws.each do |my_fw|
    print "Remove firmware: #{my_fw.fw_name}, #{my_fw.fw_version}, #{my_fw.checksum}. Remove now? <Yn>:"
    answer = STDIN.gets.chomp.downcase
    File.delete(my_fw.file_path) if 'y' == answer
  end
end
