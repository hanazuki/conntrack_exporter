# frozen_string_literal: true

require 'open3'
require 'socket'
require 'tmpdir'
require 'timeout'

RSpec.describe 'Metrics from the kernel conntrack table' do
  def conntrack(*args)
    stdout, stderr, status = Open3.capture3('conntrack', *args)
    raise "conntrack #{args.join(' ')} failed: #{stderr}" unless status.success?

    stdout
  end

  def scrape
    response = Timeout.timeout(10) do
      UNIXSocket.open(@socket_path) do |socket|
        socket.write("GET /metrics HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        socket.read
      end
    end
    headers, body = response.split("\r\n\r\n", 2)
    expect(headers.lines.first).to match(%r{\AHTTP/1\.[01] 200\b})
    body.lines.grep_v(/^#/).map(&:strip).reject(&:empty?)
  end

  def wait_for_exporter(server, log_path)
    Timeout.timeout(10) do
      loop do
        raise "Exporter exited during startup:\n#{File.read(log_path)}" if server.join(0)

        begin
          UNIXSocket.open(@socket_path) { return }
        rescue Errno::ENOENT, Errno::ECONNREFUSED
          sleep 0.05
        end
      end
    end
  rescue Timeout::Error
    raise "Exporter did not start within 10 seconds:\n#{File.read(log_path)}"
  end

  def stop_exporter(server)
    return if server.join(0)

    Process.kill('TERM', server.pid)
    Process.kill('KILL', server.pid) unless server.join(5)
  rescue Errno::ESRCH
    # The exporter exited between checking its status and sending the signal.
  ensure
    server.join
  end

  around do |example|
    host_namespace = ENV.fetch('CONNTRACK_TEST_HOST_NETNS') { raise 'Run with bundle exec rake spec:integration' }
    unless Process.uid.zero? && File.readlink('/proc/self/ns/net') != host_namespace
      raise 'The integration test requires a fresh network namespace; run with bundle exec rake spec:integration'
    end

    Dir.mktmpdir('conntrack-exporter-') do |dir|
      @socket_path = File.join(dir, 'metrics.sock')
      log_path = File.join(dir, 'exporter.log')
      executable = File.expand_path('../exe/conntrack_exporter', __dir__)
      server = Process.detach(
        Process.spawn(
          executable, '--bind', "unix://#{@socket_path}",
          out: log_path, err: [:child, :out],
        )
      )
      begin
        wait_for_exporter(server, log_path)
        example.run
      ensure
        stop_exporter(server)
      end
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
