# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task default: :spec

task :'update:protocols' do
  require 'csv'
  require 'json'
  require 'open-uri'
  URI('https://www.iana.org/assignments/protocol-numbers/protocol-numbers-1.csv').open do |f|
    protomap = CSV.new(f, headers: :first_row).to_h do |row|
      protonum = row['Decimal']
      name = row['Keyword']
      [protonum, name]
    end
    File.write(File.join(__dir__, 'iana', 'protocol-numbers.json'), JSON.dump(protomap))
  end
end
