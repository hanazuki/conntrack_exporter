# frozen_string_literal: true

require 'open3'
require 'rack/mock'

RSpec.describe 'Metrics from the kernel conntrack table' do
  def conntrack(*args)
    stdout, stderr, status = Open3.capture3('conntrack', *args)
    raise "conntrack #{args.join(' ')} failed: #{stderr}" unless status.success?

    stdout
  end

  def scrape
    response = Rack::MockRequest.new(ConntrackExporter::App).get('/metrics')
    expect(response.status).to eq(200)
    response.body.lines.grep_v(/^#/).map(&:strip).reject(&:empty?)
  end

  before do
    host_namespace = ENV.fetch('CONNTRACK_TEST_HOST_NETNS') { raise 'Run with bundle exec rake spec:integration' }
    unless Process.uid.zero? && File.readlink('/proc/self/ns/net') != host_namespace
      raise 'The integration test requires a fresh network namespace; run with bundle exec rake spec:integration'
    end
  end

  it 'exports inserted IPv4/TCP and IPv6/UDP entries' do
    # Require a fresh namespace so these assertions never depend on host traffic.
    expect(conntrack('-L')).to be_empty
    expect(scrape.grep(/^conntrack_entries\{/)).to be_empty

    [12345, 12346].each do |port|
      conntrack('-I', '-p', 'tcp', '-s', '192.0.2.1', '-d', '192.0.2.2',
                '--sport', port.to_s, '--dport', '80', '--state', 'ESTABLISHED', '-t', '300')
    end
    conntrack('-I', '-p', 'udp', '-s', '2001:db8::1', '-d', '2001:db8::2',
              '--sport', '12345', '--dport', '53', '-t', '300')

    samples = scrape
    expect(samples.grep(/^conntrack_entries\{/)).to contain_exactly(
      'conntrack_entries{l3proto="IPv4",l4proto="TCP"} 2.0',
      'conntrack_entries{l3proto="IPv6",l4proto="UDP"} 1.0',
    )
  end
end
