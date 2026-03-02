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
    protomap = CSV.new(f, headers: :first_row).filter_map do |row|
      protonum = Integer(row['Decimal']) rescue nil
      name = row['Keyword']&.sub(%r[\s\(.+\)\z], '')
      [protonum, name] if protonum and name
    end.to_h
    File.write(File.join(__dir__, 'iana', 'protocol-numbers.json'), JSON.dump(protomap))
  end
end
