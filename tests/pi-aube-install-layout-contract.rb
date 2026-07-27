# frozen_string_literal: true

repo_root = File.expand_path('..', __dir__)
tasks = File.read(File.join(repo_root, 'roles/common/tasks/main.yml'))
current_package = 'node_modules/@earendil-works/pi-coding-agent'
current_bin = 'node_modules/.bin/pi'
legacy_bin = %q{npm:@earendil-works/pi-coding-agent')/bin/pi}

abort "missing current Pi package path: #{current_package}" unless tasks.include?(current_package)
abort "missing current Pi executable path: #{current_bin}" unless tasks.include?(current_bin)
abort "legacy Pi executable path remains: #{legacy_bin}" if tasks.include?(legacy_bin)

puts 'Pi Aube install layout contract passed'
