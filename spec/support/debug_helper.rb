puts "=== DEBUG: These support files are being loaded ==="
puts $LOADED_FEATURES.select { |f| f.include?('/spec/support/') }.sort
puts "=== END DEBUG ==="
