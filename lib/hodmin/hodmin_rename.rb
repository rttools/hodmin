def hodmin_rename(_gopts, copts)
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
    puts 'ERR: None of available firmware does match this pattern'
    return
  else
    my_fws.each do |f|
      puts "found Fw: Name: #{f.fw_name}, Version: #{f.fw_version}, MD5: #{f.checksum}"
    end
  end

  my_fws.each do |my_fw|
    bin_pattern = "Homie_#{my_fw.fw_name}_#{my_fw.fw_version}_#{my_fw.checksum}.bin"
    fileobj = Pathname.new(my_fw.file_path)
    next if bin_pattern == Pathname.new(my_fw.file_path).basename.to_s
    puts "Rename firmware: #{my_fw.fw_name}, #{my_fw.fw_version}, #{my_fw.checksum}."
    print "Rename to #{bin_pattern}? <Yn>:"
    answer = STDIN.gets.chomp.downcase
    fileobj.rename(fileobj.dirname + bin_pattern) if 'y' == answer
  end
end
